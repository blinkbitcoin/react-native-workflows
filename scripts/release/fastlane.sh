#!/usr/bin/env bash
# Run one fastlane lane in the consumer root.
#
# Usage: fastlane.sh PLATFORM LANE [key:value ...]
#   fastlane.sh ios build
#   fastlane.sh android rollout percentage:0.1
#
# $LANE_ARGS adds the same key:value pairs from the environment. That exists so
# a workflow can forward a caller-supplied argument list without an unquoted
# expansion in its `run:` line (which shellcheck rightly rejects).
#
# Lane names (the consumer's Fastfile must define exactly these):
#   ios     build verify upload_internal promote_beta release_production phased upload_symbols
#   android build verify upload_internal promote_beta release_production rollout halt
#
# The lanes read their inputs from the environment - APP_VERSION,
# APP_BUILD_NUMBER, RELEASE_NOTES_STORE_FILE, IOS_BUNDLE_ID, IOS_SCHEME,
# ANDROID_PACKAGE, BUILD_INFO_FILE, RNW_OUTPUT_DIR plus the credentials
# decode-secrets.sh materialised - so this wrapper only exports RNW_OUTPUT_DIR
# and passes the key:value pairs through verbatim.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

platform="$(rnw_release_platform "${1:-}")"
shift
lane="${1:?usage: fastlane.sh PLATFORM LANE [key:value ...]}"
shift

args=("$@")
if [ -n "${LANE_ARGS:-}" ]; then
  read -r -a extra <<< "$LANE_ARGS"
  args+=("${extra[@]}")
fi
set -- "${args[@]+"${args[@]}"}"

root="$(consumer_root)"
cd "$root"
mkdir -p "$RNW_OUTPUT_DIR"
export RNW_OUTPUT_DIR

group "fastlane $platform $lane"
if [ -f "$root/Gemfile" ] && command -v bundle >/dev/null 2>&1; then
  bundle exec fastlane "$platform" "$lane" "$@"
else
  # No Gemfile means the consumer is not pinning fastlane; a global fastlane is
  # then the only thing that can run, and its absence must be an explicit error
  # rather than a confusing "command not found" in the middle of a release.
  require_cmd fastlane
  log "no Gemfile in $root - running the fastlane on PATH (unpinned)"
  fastlane "$platform" "$lane" "$@"
fi
endgroup
