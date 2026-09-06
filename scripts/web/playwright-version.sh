#!/usr/bin/env bash
# Print the resolved @playwright/test version from a pnpm lockfile, so CI can
# pin the Playwright browsers/Docker image to match what the app installs.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
lock="${1:-$(consumer_root)/pnpm-lock.yaml}"
require_cmd yq
[ -f "$lock" ] || die "no such file: $lock"
version=$(yq -r '.importers["."].devDependencies["@playwright/test"].version // ""' "$lock" | grep -vE '^(---)?$' | tail -n1)
[ -n "$version" ] || die "@playwright/test not found in $lock"
printf '%s\n' "$version" | sed 's/(.*//'
