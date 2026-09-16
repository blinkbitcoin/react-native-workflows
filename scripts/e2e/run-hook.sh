#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/e2e-env.sh"

# Runs a consumer-relative hook script named by $HOOK (empty = no-op). The
# workflow drives the E2E setup/teardown hooks through this so they bracket the
# whole device job, not just the Maestro step.
if [ -z "${HOOK:-}" ]; then
  log "run-hook: HOOK is empty; nothing to run"
  exit 0
fi
workflows_run_hook HOOK
