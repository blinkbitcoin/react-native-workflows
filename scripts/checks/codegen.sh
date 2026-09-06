#!/usr/bin/env bash
# Regenerate GraphQL codegen output and fail if that produced any uncommitted
# diff, i.e. the checked-in generated code is stale relative to the schema.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd git

root="$(consumer_root)"
paths="${CODEGEN_PATHS:-src/graphql/generated}"

bash "$(dirname "$0")/run-script.sh" codegen

cd "$root"
# shellcheck disable=SC2086 # CODEGEN_PATHS is an intentionally space-separated list of pathspecs
git diff --exit-code -- $paths ||
  die "codegen produced uncommitted changes in: $paths (run \"pnpm run codegen\" and commit the result)"
