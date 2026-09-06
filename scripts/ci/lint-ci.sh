#!/usr/bin/env bash
# Lint a consumer's own scripts/ and .github/workflows/ with the same pinned
# actionlint/shellcheck versions this repo's own `make check` uses.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/versions.sh"

root="$(consumer_root)"
cd "$root"

if [ ! -d scripts ]; then
  log "lint-ci: no scripts/ directory in $root; nothing to lint"
  exit 0
fi

require_cmd mise

if [ -d .github/workflows ]; then
  mise x "actionlint@$ACTIONLINT_VERSION" -- actionlint -color
fi

files=()
while IFS= read -r f; do
  files+=("$f")
done < <(find scripts -name '*.sh' -not -path '*/.rnw/*')
if [ "${#files[@]}" -gt 0 ]; then
  mise x "shellcheck@$SHELLCHECK_VERSION" -- shellcheck -x "${files[@]}"
fi
