#!/usr/bin/env bash
# iOS simulator plumbing for the E2E job.
#   pick             boot a simulator and remember its udid ($RNW_OUT/sim-udid,
#                    $GITHUB_OUTPUT udid, RNW_SIM_UDID in $GITHUB_ENV). Runner
#                    images rotate generations, so no model is hardcoded: an
#                    already-booted device wins, then the newest iPhone.
#   wait             block until the picked device finished booting
#   install <src>    install the .app (tar from ios-pack.sh, or a .app dir)
#   record start|stop screen recording to $RNW_OUT/ios.mp4
#   shutdown         shut the picked device down (best effort)
# Usage: ios-simulator.sh pick | wait | install <app.tar|App.app> | record start|stop | shutdown
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

require_cmd xcrun jq
rec_pid_file="$RNW_OUT/ios-record.pid"

case "${1:-}" in
  pick)
    devices="$(xcrun simctl list -j devices available)"
    # Prefer a device that is already up (a developer Mac, and a warm runner):
    # booting a second one costs a minute and confuses `simctl ... booted`.
    udid="$(printf '%s' "$devices" | jq -r '
      [.devices[][] | select(.isAvailable and .state == "Booted" and (.name | startswith("iPhone")))] | .[0].udid // ""')"
    if [ -z "$udid" ]; then
      udid="$(printf '%s' "$devices" | jq -r '
        [.devices[][] | select(.isAvailable and (.name | test("iPhone 1[5-9]|iPhone 2")))] | .[0].udid // ""')"
    fi
    if [ -z "$udid" ]; then
      udid="$(printf '%s' "$devices" | jq -r '
        [.devices[][] | select(.isAvailable and (.name | startswith("iPhone")))] | .[0].udid // ""')"
    fi
    [ -n "$udid" ] || { xcrun simctl list devices available >&2; die "no available iPhone simulator on this machine"; }
    name="$(printf '%s' "$devices" | jq -r --arg u "$udid" '[.devices[][] | select(.udid == $u)] | .[0].name')"
    log "Using simulator: $name ($udid)"
    printf '%s\n' "$udid" > "$RNW_OUT/sim-udid"
    gh_output udid "$udid"
    gh_env RNW_SIM_UDID "$udid"
    # Already-booted is the normal case here, hence the tolerated failure.
    xcrun simctl boot "$udid" || true
    ;;
  wait)
    xcrun simctl bootstatus "$(rnw_sim_udid)" -b
    ;;
  install)
    src="${2:?usage: ios-simulator.sh install <app.tar|App.app>}"
    if [ -d "$src" ]; then
      app="$src"
    else
      [ -f "$src" ] || die "no such app bundle or tar: $src"
      dest="$RNW_OUT/app"
      rm -rf "$dest"
      mkdir -p "$dest"
      tar -C "$dest" -xf "$src"
      app="$(find "$dest" -maxdepth 1 -name '*.app' | head -1)"
      [ -n "$app" ] || die "no .app inside $src"
    fi
    xcrun simctl install "$(rnw_sim_udid)" "$app"
    log "installed $app"
    ;;
  record)
    case "${2:-}" in
      start)
        # h264 (not the hevc default): the artifact has to play in a browser.
        xcrun simctl io "$(rnw_sim_udid)" recordVideo --codec=h264 --force "$RNW_OUT/ios.mp4" &
        printf '%s\n' "$!" > "$rec_pid_file"
        log "recording to $RNW_OUT/ios.mp4 (pid $(cat "$rec_pid_file"))"
        ;;
      stop)
        [ -f "$rec_pid_file" ] || { log "no recording in progress"; exit 0; }
        pid="$(cat "$rec_pid_file")"
        # SIGINT, not SIGKILL: simctl only finalises the mp4 container on a
        # clean interrupt, and a killed recording is an unplayable file.
        kill -INT "$pid" 2>/dev/null || true
        for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
        rm -f "$rec_pid_file"
        log "recording stopped ($RNW_OUT/ios.mp4)"
        ;;
      *) die "usage: ios-simulator.sh record start|stop" ;;
    esac
    ;;
  shutdown)
    xcrun simctl shutdown "$(rnw_sim_udid)" || true
    ;;
  *) die "usage: ios-simulator.sh pick | wait | install <app.tar|App.app> | record start|stop | shutdown" ;;
esac
