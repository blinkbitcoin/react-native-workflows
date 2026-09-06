#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/versions.sh
command -v yq >/dev/null 2>&1 || { echo "::error::check-versions.sh needs yq on PATH (run it through 'mise exec --')"; exit 1; }
fail=0
# Anchored to the input, not to "some input in this file defaults to 34":
# yq reads the declared default rather than any line that happens to match.
api_level=$(yq -r '.on.workflow_call.inputs."android-api-level".default' .github/workflows/e2e.yml)
[ "$api_level" = "$ANDROID_API_LEVEL" ] || { echo "::error::e2e.yml android-api-level default ($api_level) != $ANDROID_API_LEVEL"; fail=1; }
maestro_input=$(yq -r '.on.workflow_call.inputs."maestro-version".default' .github/workflows/e2e.yml)
[ "$maestro_input" = "$MAESTRO_VERSION" ] || { echo "::error::e2e.yml maestro-version default ($maestro_input) != $MAESTRO_VERSION"; fail=1; }
grep -q "default: '$MAESTRO_VERSION'" .github/actions/maestro/action.yml || { echo "::error::maestro action default != $MAESTRO_VERSION"; fail=1; }
grep -q "shellcheck = \"$SHELLCHECK_VERSION\"" .mise.toml || { echo "::error::.mise.toml shellcheck != $SHELLCHECK_VERSION"; fail=1; }
grep -q "actionlint = \"$ACTIONLINT_VERSION\"" .mise.toml || { echo "::error::.mise.toml actionlint != $ACTIONLINT_VERSION"; fail=1; }
# yq is installed by the native-key action from YQ_VERSION (scripts/ci/yq-version.sh),
# so a drift between versions.sh and .mise.toml means CI and `make check` run different yq.
grep -q "yq = \"$YQ_VERSION\"" .mise.toml || { echo "::error::.mise.toml yq != $YQ_VERSION"; fail=1; }
# bats is pinned in .mise.toml only (nothing installs it from versions.sh); assert
# the pin exists and is exact, so a bare `bats = "latest"` cannot creep in.
grep -qE '^bats = "[0-9]+\.[0-9]+\.[0-9]+"$' .mise.toml || { echo "::error::.mise.toml bats must be pinned to an exact version"; fail=1; }
exit $fail
