#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

root="${1:-$(consumer_root)}"
ver="${NATIVE_CACHE_VERSION:-v1}"
os="${RUNNER_OS:-}"
arch="${RUNNER_ARCH:-}"
xcode="${XCODE:-}"
[ -n "$xcode" ] || xcode="default"

hash=$(bash "$(dirname "$0")/native-hash.sh" "$root")

gh_output hash "$hash"
gh_output ios-key "ios-app-${ver}-${os}-${arch}-xcode${xcode}-${hash}"
gh_output android-key "android-apk-${ver}-${hash}"
gh_output pods-key "pods-${os}-${hash}"
