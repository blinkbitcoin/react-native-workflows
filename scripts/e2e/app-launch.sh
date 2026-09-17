#!/usr/bin/env bash
# Bring the app to the foreground and prove Metro actually served it. A
# dev-client build is launched through its deep link with the Metro URL baked
# in: launching the app plainly lands on the dev-client launcher screen, where
# every flow would then have to tap through a list of servers.
# Needs: app installed, Metro running (metro-wait.sh).
# Usage: app-launch.sh <ios|android>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

# Taps through the "Open in <app>?" confirmation, if iOS raised one. A one-shot
# maestro flow because nothing else on a runner can touch the screen: simctl
# cannot tap, and the suite's own flows do not start until this script returns.
workflows_confirm_ios_open() { # <app id>
  local flow
  command -v maestro >/dev/null 2>&1 || { log "maestro not on PATH - skipping the open-in-app tap"; return 0; }
  flow="$(mktemp -t workflows-open-XXXXXX).yaml"
  # Wait for the prompt rather than glancing once. An `optional: true` tap is a
  # race - it reports success when the button is not on screen yet, and the same
  # script then passed one run and failed the next with no code change between
  # them. extendedWaitUntil bounds the wait instead; if no prompt ever appears
  # the flow fails, which the caller ignores, so the cost of being wrong is the
  # timeout and nothing else.
  cat >"$flow" <<YAML
appId: $1
---
- extendedWaitUntil:
    visible:
      text: '^Open\$'
    timeout: ${WORKFLOWS_IOS_OPEN_PROMPT_TIMEOUT_MS:-20000}
- tapOn:
    text: '^Open\$'
YAML
  maestro test "$flow" >/dev/null 2>&1 || log "no open-in-app prompt to confirm (or maestro could not reach it)"
  rm -f "$flow"
}

platform="$(workflows_platform "${1:-}")"
app_id="$(workflows_app_id "$platform")"
log "launching $app_id on $platform (dev-client=$WORKFLOWS_DEV_CLIENT)"

# The bundle request Metro logs is the launch's receipt; anything before it can
# be an app that started and died on the launcher.
metro_log="$WORKFLOWS_OUT/metro.log"
[ -f "$metro_log" ] || die "no $metro_log - run metro-start.sh first"
before=$(( $(wc -l < "$metro_log") + 1 ))

if [ "$platform" = ios ]; then
  udid="$(workflows_sim_udid)"
  if [ "$WORKFLOWS_DEV_CLIENT" = "true" ]; then
    scheme="$(workflows_scheme)"
    url="$scheme://expo-development-client/?url=http%3A%2F%2Flocalhost%3A$WORKFLOWS_METRO_PORT"
    # iOS asks "Open in <app>?" for a URL arriving from elsewhere, and on a
    # simulator that has never been asked - every fresh runner - the prompt sits
    # there unanswered until the bundle wait below times out. A developer's
    # simulator answered it once and remembers, which is why this only ever
    # failed in CI. Foregrounding the app first does NOT avoid it: verified on a
    # runner, the prompt appears over the dev client's own launcher.
    #
    # So answer it. maestro is installed by this point and is the only thing
    # here that can tap; the flow is optional, so it is a no-op on a simulator
    # that does not ask.
    log "opening $url"
    xcrun simctl openurl "$udid" "$url"
    workflows_confirm_ios_open "$app_id"
  else
    xcrun simctl launch "$udid" "$app_id"
  fi
else
  if [ "$WORKFLOWS_DEV_CLIENT" = "true" ]; then
    scheme="$(workflows_scheme)"
    # 10.0.2.2 is the emulator's alias for the host loopback; `adb reverse`
    # covers the app's own localhost traffic but not this launch URL.
    adb shell am start -a android.intent.action.VIEW \
      -d "$scheme://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A$WORKFLOWS_METRO_PORT"
  else
    adb shell am start -n "$app_id/.MainActivity"
  fi
fi

for i in $(seq 1 60); do
  # "iOS Bundled 1479ms .../entry.js" is what Expo's Metro logs per request;
  # older RN CLI Metro logs "Bundling"/a raw ".bundle" URL instead.
  if tail -n "+$before" "$metro_log" | grep -qE 'Bundled|Bundling|\.bundle'; then
    log "Metro served a bundle after $((i * 2))s - app is up"
    exit 0
  fi
  sleep 2
done
log "--- tail of $metro_log ---"
tail -50 "$metro_log" >&2 || true
die "$app_id did not request a bundle within 120s of launch"
