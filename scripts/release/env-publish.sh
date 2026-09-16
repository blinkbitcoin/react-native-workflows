#!/usr/bin/env bash
# Publish the release output directories to $GITHUB_ENV up front, so an
# upload/download step's `path:` resolves even when an earlier step failed
# before any other release script ran (the same reason
# scripts/e2e/env-publish.sh exists for the E2E jobs).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

log "WORKFLOWS_OUT=$WORKFLOWS_OUT"
log "WORKFLOWS_OUTPUT_DIR=$WORKFLOWS_OUTPUT_DIR"
log "WORKFLOWS_RELEASE_META_DIR=$WORKFLOWS_RELEASE_META_DIR"
log "WORKFLOWS_OTA_DIR=$WORKFLOWS_OTA_DIR"
log "WORKFLOWS_ASSETS_DIR=$WORKFLOWS_ASSETS_DIR"
