#!/usr/bin/env bats
# The two halves of the published contract, checked against the real first
# consumer instead of a fixture:
#   1. every script docs/consumer-guide.md's script-contract table marks "yes"
#      actually exists in the template's package.json;
#   2. every input a reusable workflow declares is documented in that
#      workflow's own section of the guide.
# (1) needs the consumer checkout; point RNW_CONSUMER_ROOT elsewhere or let it
# default, and the tests skip with a message when it is not there.
load test_helper

GUIDE="$REPO_ROOT/docs/consumer-guide.md"
CONSUMER="${RNW_CONSUMER_ROOT:-/Users/jonas/Dev/blink/react-native-mobile-template}"

# bats-core ships no `fail`, and bats-assert is not a dependency here.
fail() {
  echo "$*" >&2
  return 1
}

require_consumer() {
  [ -f "$CONSUMER/package.json" ] || skip "no consumer checkout at $CONSUMER (set RNW_CONSUMER_ROOT)"
}

# Prints the consumer's package.json script names, one per line.
consumer_scripts() {
  node -e 'const p=require(process.argv[1]);console.log(Object.keys(p.scripts||{}).join("\n"))' \
    "$CONSUMER/package.json"
}

# Prints the section of the guide for heading "### `NAME`", stopping at the
# next heading of any level.
guide_section() {
  awk -v want="### \`$1\`" '
    $0 == want { inside = 1; next }
    inside && /^#{1,6} / { exit }
    inside { print }
  ' "$GUIDE"
}

@test "every script the guide's contract table marks yes exists in the consumer" {
  require_consumer
  scripts="$(consumer_scripts)"
  for name in typecheck lint format:check spell i18n:extract i18n:check \
    codegen codegen:check test test:coverage test:scripts build:web \
    test:e2e:web deps:check deps:audit deps:licenses check-prebuild; do
    echo "checking package.json script: $name"
    grep -qxF "$name" <<<"$scripts"
  done
}

@test "knip is a consumer devDependency (the guide's binary-fallback claim)" {
  require_consumer
  run node -e 'const p=require(process.argv[1]);process.exit(p.devDependencies&&p.devDependencies.knip?0:1)' \
    "$CONSUMER/package.json"
  [ "$status" -eq 0 ]
}

@test "knip is deliberately NOT a consumer package.json script" {
  require_consumer
  run grep -qxF knip <<<"$(consumer_scripts)"
  [ "$status" -ne 0 ]
}

@test "every workflow_call input is documented in the guide's table for that workflow" {
  command -v yq >/dev/null || skip "yq not installed"
  missing=()
  for wf in checks unit e2e web pr-title; do
    section="$(guide_section "$wf.yml")"
    [ -n "$section" ] || fail "no '### \`$wf.yml\`' section in docs/consumer-guide.md"
    while read -r input; do
      [ -n "$input" ] || continue
      grep -qF -- "\`$input\`" <<<"$section" || missing+=("$wf.yml:$input")
    done < <(yq -r '.on.workflow_call.inputs | keys | .[]' "$REPO_ROOT/.github/workflows/$wf.yml")
  done
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented inputs: ${missing[*]}"
}

@test "pr-closed.yml really declares no workflow_call inputs" {
  command -v yq >/dev/null || skip "yq not installed"
  run yq -r '.on.workflow_call.inputs // "null"' "$REPO_ROOT/.github/workflows/pr-closed.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
