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

# RNW_ACTIONLINT / RNW_SHELLCHECK let a single invocation toggle either half
# independently (checks.yml's `actionlint` and `shellcheck` inputs), while
# `make check` (no env set) still runs both.
if [ "${RNW_ACTIONLINT:-true}" = "true" ] && [ -d .github/workflows ]; then
  mise x "actionlint@$ACTIONLINT_VERSION" -- actionlint -color
fi

if [ "${RNW_SHELLCHECK:-true}" = "true" ]; then
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find scripts -name '*.sh' -not -path '*/.rnw/*')
  if [ "${#files[@]}" -gt 0 ]; then
    mise x "shellcheck@$SHELLCHECK_VERSION" -- shellcheck -x "${files[@]}"
  fi
fi
