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

platform="$(rnw_platform "${1:-}")"
app_id="$(rnw_app_id "$platform")"
log "launching $app_id on $platform (dev-client=$RNW_DEV_CLIENT)"

# The bundle request Metro logs is the launch's receipt; anything before it can
# be an app that started and died on the launcher.
metro_log="$RNW_OUT/metro.log"
[ -f "$metro_log" ] || die "no $metro_log - run metro-start.sh first"
before=$(( $(wc -l < "$metro_log") + 1 ))

if [ "$platform" = ios ]; then
  udid="$(rnw_sim_udid)"
  if [ "$RNW_DEV_CLIENT" = "true" ]; then
    scheme="$(rnw_scheme)"
    xcrun simctl openurl "$udid" \
      "$scheme://expo-development-client/?url=http%3A%2F%2Flocalhost%3A$RNW_METRO_PORT"
  else
    xcrun simctl launch "$udid" "$app_id"
  fi
else
  if [ "$RNW_DEV_CLIENT" = "true" ]; then
    scheme="$(rnw_scheme)"
    # 10.0.2.2 is the emulator's alias for the host loopback; `adb reverse`
    # covers the app's own localhost traffic but not this launch URL.
    adb shell am start -a android.intent.action.VIEW \
      -d "$scheme://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A$RNW_METRO_PORT"
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
