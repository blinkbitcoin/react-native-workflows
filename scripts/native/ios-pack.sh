#!/usr/bin/env bash
# Pack the simulator .app into a tar for upload-artifact. A tar (not the raw
# directory) because upload-artifact does not preserve the executable bit or
# symlinks inside a .app bundle, and an unpacked app then refuses to launch.
# Needs: ios-build.sh. Output: $RNW_OUT/<scheme>.app.tar
# Usage: ios-pack.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

root="$(consumer_root)"
cd "$root"
scheme="$(rnw_ios_scheme)"
[ -d "$RNW_IOS_PRODUCTS_DIR/$scheme.app" ] || die "no $RNW_IOS_PRODUCTS_DIR/$scheme.app - run ios-build.sh first"

tar_path="$RNW_OUT/$scheme.app.tar"
tar -C "$RNW_IOS_PRODUCTS_DIR" -cf "$tar_path" "$scheme.app"
log "packed $tar_path ($(du -h "$tar_path" | cut -f1))"
gh_output app_tar "$tar_path"
