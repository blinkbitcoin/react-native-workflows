#!/usr/bin/env bash
# Publish the release output directories to $GITHUB_ENV up front, so an
# upload/download step's `path:` resolves even when an earlier step failed
# before any other release script ran (the same reason
# scripts/e2e/env-publish.sh exists for the E2E jobs).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

log "RNW_OUT=$RNW_OUT"
log "RNW_OUTPUT_DIR=$RNW_OUTPUT_DIR"
log "RNW_RELEASE_META_DIR=$RNW_RELEASE_META_DIR"
log "RNW_OTA_DIR=$RNW_OTA_DIR"
log "RNW_ASSETS_DIR=$RNW_ASSETS_DIR"
