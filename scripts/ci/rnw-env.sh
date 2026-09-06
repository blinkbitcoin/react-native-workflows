#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

gh_env RNW "$GITHUB_WORKSPACE/.rnw"
gh_env WORKING_DIRECTORY "${WORKING_DIRECTORY:-.}"

exclude_dir="$(consumer_root)/.git/info"
mkdir -p "$exclude_dir"
exclude="$exclude_dir/exclude"
touch "$exclude"
grep -qxF '.rnw/' "$exclude" || printf '%s\n' '.rnw/' >> "$exclude"
