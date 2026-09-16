#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm
# Two steps, not `cd "$(consumer_root)"`. A command substitution used as an
# argument does not propagate its exit status, and `cd ""` is a successful
# no-op, so a failing consumer_root would leave this running `pnpm install` in
# whatever directory the runner happened to be in.
root="$(consumer_root)"
cd "$root"
pnpm install --frozen-lockfile
