#!/usr/bin/env bash
# Fail the build on known vulnerabilities in production dependencies at or
# above AUDIT_LEVEL (default: high). Dev-only vulnerabilities don't ship.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm

root="$(consumer_root)"
cd "$root"
pnpm audit --audit-level "${AUDIT_LEVEL:-high}" --prod
