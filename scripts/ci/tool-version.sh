#!/usr/bin/env bash
# Read a tool's pinned version out of a mise.toml [tools] table.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
tool="${1:?usage: tool-version.sh TOOL [file]}"
file="${2:-$(consumer_root)/.mise.toml}"
[ -f "$file" ] || die "no such file: $file"
version=$(awk -F'"' -v t="$tool" '$0 ~ "^"t" *= *\"" {print $2; exit}' "$file")
[ -n "$version" ] || die "tool not found in $file: $tool"
printf '%s\n' "$version"
