#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm
cd "$(consumer_root)" && pnpm install --frozen-lockfile
