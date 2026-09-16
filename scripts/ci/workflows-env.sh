#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

gh_env WORKFLOWS_DIR "$GITHUB_WORKSPACE/.workflows"
gh_env WORKING_DIRECTORY "${WORKING_DIRECTORY:-.}"

exclude_dir="$(consumer_root)/.git/info"
mkdir -p "$exclude_dir"
exclude="$exclude_dir/exclude"
touch "$exclude"
grep -qxF '.workflows/' "$exclude" || printf '%s\n' '.workflows/' >> "$exclude"
