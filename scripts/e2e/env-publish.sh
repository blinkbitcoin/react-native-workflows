#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

# Sourcing e2e-env.sh is the whole point: it publishes RNW_OUT and RNW_RUN_START
# to $GITHUB_ENV (once per job) so later `with:` blocks can use ${{ env.RNW_OUT }}
# before any other script in the family has run.
log "RNW_OUT=$RNW_OUT"
log "RNW_RUN_START=$RNW_RUN_START"
