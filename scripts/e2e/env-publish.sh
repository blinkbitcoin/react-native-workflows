#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

# Sourcing e2e-env.sh is the whole point: it publishes WORKFLOWS_OUT and WORKFLOWS_RUN_START
# to $GITHUB_ENV (once per job) so later `with:` blocks can use ${{ env.WORKFLOWS_OUT }}
# before any other script in the family has run.
log "WORKFLOWS_OUT=$WORKFLOWS_OUT"
log "WORKFLOWS_RUN_START=$WORKFLOWS_RUN_START"
