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

# The iOS .app embeds EXPO_PUBLIC_* at bundle time, so two different build-env
# values must never share a cache entry. native-hash.sh hashes file contents and
# cannot see a workflow input, so the digest is folded in here instead. An empty
# build-env leaves the key exactly as it was, so a consumer that does not pass
# the input keeps its existing caches.
env_suffix=""
build_env="${BUILD_ENV:-}"
if [ -n "$build_env" ] && [ "$build_env" != "{}" ]; then
  env_suffix="-env$(printf '%s' "$build_env" | shasum -a 256 | cut -c1-8)"
fi

gh_output hash "$hash"
gh_output ios-key "ios-app-${ver}-${os}-${arch}-xcode${xcode}-${hash}${env_suffix}"
gh_output android-key "android-apk-${ver}-${hash}"
gh_output pods-key "pods-${os}-${hash}"
