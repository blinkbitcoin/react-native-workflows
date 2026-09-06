#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
version=$(bash "$(dirname "$0")/tool-version.sh" ruby "$(consumer_root)/.mise.toml")
gh_output version "$version"
