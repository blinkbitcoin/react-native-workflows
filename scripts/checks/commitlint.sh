#!/usr/bin/env bash
# Lint $PR_TITLE (a GitHub Actions expression, e.g. github.event.pull_request.title)
# against Conventional Commits. PR_TITLE is attacker-influenced (any contributor
# can set a PR title) so it is only ever read from the environment and piped to
# commitlint's stdin -- never interpolated into a command line or shell string.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

title="${PR_TITLE:?PR_TITLE not set}"
root="$(consumer_root)"

has_commitlint_dep() {
  [ -f "$root/package.json" ] || return 1
  PKG_PATH="$root/package.json" node -e \
    "process.exit(require(process.env.PKG_PATH).devDependencies?.['@commitlint/cli'] ? 0 : 1)" \
    2>/dev/null
}

if has_commitlint_dep; then
  require_cmd pnpm
  cd "$root"
  printf '%s\n' "$title" | pnpm exec commitlint
else
  require_cmd npx
  tmp="${RUNNER_TEMP:-/tmp}"
  config="$tmp/commitlint.config.mjs"
  cat > "$config" <<'EOF'
export default { extends: ["@commitlint/config-conventional"] };
EOF
  # npx's single-package positional form only installs the first package and
  # passes the rest as CLI args to it, so config-conventional never resolves;
  # -p/--package must be repeated to install both (verified against npx 11.x).
  printf '%s\n' "$title" |
    npx --yes -p @commitlint/cli@21 -p @commitlint/config-conventional@21 \
      commitlint --config "$config"
fi
