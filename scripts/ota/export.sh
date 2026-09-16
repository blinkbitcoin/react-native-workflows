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
rm -rf "$WORKFLOWS_OTA_DIR"
mkdir -p "$WORKFLOWS_OTA_DIR"

group "expo export (ota)"
CI=1 npx expo export --platform all --source-maps --output-dir "$WORKFLOWS_OTA_DIR"
endgroup

# On content, not on the directory: mkdir -p above already guarantees the
# directory exists, so `[ -d ]` here could never fire.
[ -n "$(ls -A "$WORKFLOWS_OTA_DIR" 2>/dev/null)" ] ||
  die "expo export produced no output in $WORKFLOWS_OTA_DIR"
[ -f "$WORKFLOWS_OTA_DIR/metadata.json" ] ||
  die "expo export wrote no metadata.json in $WORKFLOWS_OTA_DIR - the export is not a publishable update"
log "ota export contents:"
ls -l "$WORKFLOWS_OTA_DIR" >&2
