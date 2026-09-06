#!/usr/bin/env bash
# Print the pnpm content-addressable store path for the consumer, so CI can
# key a cache on it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm
cd "$(consumer_root)" && pnpm store path
