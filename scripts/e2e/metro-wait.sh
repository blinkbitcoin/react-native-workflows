#!/usr/bin/env bash
# Wait for Metro (metro-start.sh) and prewarm the bundle for the given platform
# so the first app launch does not race a cold transform of the whole graph.
# The URL is Expo's virtual entry, not index.bundle: expo-router apps have no
# physical entry file.
# Usage: metro-wait.sh <ios|android>
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

platform="$(rnw_platform "${1:-}")"
require_cmd curl
base="http://localhost:$RNW_METRO_PORT"

ready=false
for i in $(seq 1 90); do
  if curl -s --max-time 5 "$base/status" | grep -q packager-status:running; then
    log "Metro is ready (after $((i * 2))s)"
    ready=true
    break
  fi
  sleep 2
done
if [ "$ready" != true ]; then
  log "--- tail of $RNW_OUT/metro.log ---"
  tail -50 "$RNW_OUT/metro.log" >&2 || true
  die "Metro did not report packager-status:running within 180s"
fi

# The first bundle build of a cold app is minutes on a runner; do it here so a
# launch timeout later means a real launch problem.
group "prewarming the $platform bundle"
bundle="$base/.expo/.virtual-metro-entry.bundle?platform=$platform&dev=true&hot=false&lazy=true&transform.engine=hermes"
curl -sf --max-time 300 "$bundle" -o /dev/null || die "bundle prewarm failed for $platform"
endgroup
log "Bundle prewarmed ($platform)"
