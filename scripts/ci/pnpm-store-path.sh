#!/usr/bin/env bash
# Print the pnpm content-addressable store path for the consumer, so CI can
# key a cache on it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm
# Two steps: a command substitution used as an argument does not propagate its
# exit status, and `cd ""` is a successful no-op, so a failing consumer_root
# would silently report the store path of the wrong directory.
root="$(consumer_root)"
path=$(cd "$root" && pnpm store path)
gh_output path "$path"
