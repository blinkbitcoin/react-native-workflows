#!/usr/bin/env bash
# Lint a consumer's own scripts/ and .github/workflows/ with the same pinned
# actionlint/shellcheck versions this repo's own `make check` uses.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/versions.sh"

root="$(consumer_root)"
cd "$root"

if [ ! -d scripts ] && [ ! -d .github/workflows ]; then
  log "lint-ci: no scripts/ and no .github/workflows/ in $root; nothing to lint"
  exit 0
fi

require_cmd mise

# RNW_ACTIONLINT / RNW_SHELLCHECK let a single invocation toggle either half
# independently (checks.yml's `actionlint` and `shellcheck` inputs), while
# `make check` (no env set) still runs both. The two halves are guarded
# separately on purpose: a consumer with workflows but no scripts/ directory (a
# perfectly normal Expo app) must still get actionlint.
if [ "${RNW_ACTIONLINT:-true}" = "true" ] && [ -d .github/workflows ]; then
  mise x "actionlint@$ACTIONLINT_VERSION" -- actionlint -color
else
  log "lint-ci: skipping actionlint"
fi

if [ "${RNW_SHELLCHECK:-true}" = "true" ] && [ -d scripts ]; then
  files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(find scripts -name '*.sh')
  if [ "${#files[@]}" -gt 0 ]; then
    mise x "shellcheck@$SHELLCHECK_VERSION" -- shellcheck -x "${files[@]}"
  fi
else
  log "lint-ci: skipping shellcheck"
fi
