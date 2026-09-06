#!/usr/bin/env bash
# Compute the @expo/fingerprint hash for both platforms and publish them as
# step outputs `fp-ios` / `fp-android` plus $GITHUB_ENV FP_IOS / FP_ANDROID
# (build-info.sh reads the latter).
#
# Usage: fingerprint.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

group "fingerprint"
fp_ios="$(rnw_fingerprint ios)"
fp_android="$(rnw_fingerprint android)"
log "ios=$fp_ios android=$fp_android"
endgroup

gh_output fp-ios "$fp_ios"
gh_output fp-android "$fp_android"
gh_env FP_IOS "$fp_ios"
gh_env FP_ANDROID "$fp_android"
