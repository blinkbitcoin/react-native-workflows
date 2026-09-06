#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/versions.sh
fail=0
[ -f .github/workflows/e2e.yml ] && { grep -q "default: '$MAESTRO_VERSION'" .github/workflows/e2e.yml || { echo "::error::e2e.yml maestro-version default != $MAESTRO_VERSION"; fail=1; }; }
[ -f .github/workflows/e2e.yml ] && { grep -q "default: $ANDROID_API_LEVEL" .github/workflows/e2e.yml || { echo "::error::e2e.yml android-api-level default != $ANDROID_API_LEVEL"; fail=1; }; }
grep -q "shellcheck = \"$SHELLCHECK_VERSION\"" .mise.toml || { echo "::error::.mise.toml shellcheck != $SHELLCHECK_VERSION"; fail=1; }
grep -q "actionlint = \"$ACTIONLINT_VERSION\"" .mise.toml || { echo "::error::.mise.toml actionlint != $ACTIONLINT_VERSION"; fail=1; }
exit $fail
