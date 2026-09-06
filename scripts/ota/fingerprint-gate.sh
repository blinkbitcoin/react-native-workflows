#!/usr/bin/env bash
# Refuse to publish an OTA update whose native fingerprint differs from the
# build already installed on the channel.
#
# This is the single most important guard in the OTA path. An update whose JS
# expects a native module the installed binary does not have does not fail
# loudly - it crashes on launch, for every user on the channel, with no way to
# roll back except a new store build. So the comparison is per-platform, and any
# mismatch is fatal rather than a warning.
#
# Usage: fingerprint-gate.sh CHANNEL_BUILD_INFO_JSON
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"
require_cmd yq

file="${1:?usage: fingerprint-gate.sh CHANNEL_BUILD_INFO_JSON}"
[ -f "$file" ] || die "no channel build-info.json at $file - the channel has no known build to gate against"

group "ota fingerprint gate"
fail=0
for platform in ios android; do
  expected="$(yq -r ".fingerprint.$platform // \"\"" "$file")"
  if [ -z "$expected" ] || [ "$expected" = "null" ]; then
    die "$file has no fingerprint.$platform - it was written by an older build-info.sh; re-run the release"
  fi
  actual="$(rnw_fingerprint "$platform")"
  if [ "$expected" = "$actual" ]; then
    log "$platform fingerprint matches ($actual)"
  else
    printf '::error::%s fingerprint mismatch: the channel runs %s, this commit fingerprints as %s. The native layer changed, so this update needs a new store build, not an OTA.\n' \
      "$platform" "$expected" "$actual" >&2
    fail=1
  fi
done
endgroup

[ "$fail" -eq 0 ] || die "ota fingerprint gate failed - refusing to publish"
