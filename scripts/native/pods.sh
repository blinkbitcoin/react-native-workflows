#!/usr/bin/env bash
# CocoaPods install for the prebuilt ios/ tree. Uses Bundler when the consumer
# pins CocoaPods in a Gemfile (the Expo template default), plain `pod` otherwise
# -- a repo without a Gemfile has no bundle to exec.
# Usage: pods.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

root="$(consumer_root)"
[ -d "$root/ios" ] || die "no ios/ in $root - run prebuild.sh ios first"
cd "$root/ios"

group "pod install"
if [ -f "$root/Gemfile" ] && command -v bundle >/dev/null 2>&1; then
  COCOAPODS_DISABLE_STATS=1 bundle exec pod install
else
  require_cmd pod
  COCOAPODS_DISABLE_STATS=1 pod install
fi
endgroup

# The first lines carry the pod count and the first resolved versions - enough
# to tell a cache hit from a real resolve in the log.
log "Podfile.lock (first 5 lines):"
head -5 Podfile.lock >&2
