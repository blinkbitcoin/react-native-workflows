#!/usr/bin/env bash
# Export the JS bundle and assets for an OTA update, with source maps.
#
# Source maps are not optional here: an OTA update is the one build whose crash
# reports cannot be symbolicated from a store-side dSYM/mapping, so the maps
# produced next to the bundle are the only way to read a stack trace from it.
#
# Usage: export.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"
require_cmd npx

root="$(consumer_root)"
cd "$root"
rm -rf "$RNW_OTA_DIR"
mkdir -p "$RNW_OTA_DIR"

group "expo export (ota)"
CI=1 npx expo export --platform all --source-maps --output-dir "$RNW_OTA_DIR"
endgroup

[ -d "$RNW_OTA_DIR" ] || die "expo export produced no output at $RNW_OTA_DIR"
log "ota export contents:"
ls -l "$RNW_OTA_DIR" >&2
