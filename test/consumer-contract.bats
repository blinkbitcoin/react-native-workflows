#!/usr/bin/env bats
# The published contract, checked three ways:
#   1. every script docs/consumer-guide.md's script-contract table marks "yes"
#      exists in a consumer's package.json — the table is *parsed*, so adding a
#      row to the guide immediately becomes an assertion;
#   2. every input a reusable workflow declares is documented in that workflow's
#      own section of the guide;
#   3. the guide's four caller examples are the files a consumer actually ships.
# Runs against test/fixtures/consumer-min by default, so all of this is asserted
# on every push including self-ci. Set RNW_CONSUMER_ROOT to a real consumer
# checkout (e.g. a react-native-mobile-template clone) to assert against that
# instead; the consumer tests skip with a message if that path has no
# package.json.
load test_helper

GUIDE="$REPO_ROOT/docs/consumer-guide.md"
CONSUMER="${RNW_CONSUMER_ROOT:-$FIXTURES/consumer-min}"

# bats-core ships no `fail`, and bats-assert is not a dependency here.
fail() {
  echo "$*" >&2
  return 1
}

require_consumer() {
  [ -f "$CONSUMER/package.json" ] || skip "no consumer package.json at $CONSUMER (RNW_CONSUMER_ROOT)"
}

# Prints the consumer's package.json script names, one per line.
consumer_scripts() {
  node -e 'const p=require(process.argv[1]);console.log(Object.keys(p.scripts||{}).join("\n"))' \
    "$CONSUMER/package.json"
}

# Prints the script names from the "## Script contract" table whose
# "Present in the template?" cell starts with "yes", one per line.
guide_table_yes_scripts() {
  awk -F'|' '
    /^## Script contract/ { inside = 1; next }
    inside && /^#+ / { exit }
    inside && NF >= 5 {
      cell = $4
      gsub(/^[ \t]+/, "", cell); gsub(/[ \t]+$/, "", cell)
      if (cell !~ /^yes/) next
      if (match($2, /`[^`]+`/)) print substr($2, RSTART + 1, RLENGTH - 2)
    }
  ' "$GUIDE"
}

# Prints the section of the guide under the heading "### `NAME`", stopping at
# the next heading of any level.
guide_section() {
  awk -v want="### \`$1\`" '
    $0 == want { inside = 1; next }
    inside && /^#+ / { exit }
    inside { print }
  ' "$GUIDE"
}

# Prints the Nth ```yaml block of the guide (1-based), dropping a leading
# "# .github/workflows/..." filename comment if present.
guide_yaml_block() {
  awk -v want="$1" '
    /^```yaml$/ { n++; if (n == want) inside = 1; next }
    inside && /^```$/ { exit }
    inside { print }
  ' "$GUIDE" | awk 'NR == 1 && /^# \.github\/workflows\// { next } { print }'
}

@test "every script the guide's contract table marks yes exists in the consumer" {
  require_consumer
  wanted="$(guide_table_yes_scripts)"
  [ "$(grep -c . <<<"$wanted")" -ge 10 ] \
    || fail "parsed only '$wanted' from the guide's script-contract table"
  scripts="$(consumer_scripts)"
  missing=()
  while read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" <<<"$scripts" || missing+=("$name")
  done <<<"$wanted"
  [ "${#missing[@]}" -eq 0 ] \
    || fail "the guide marks these 'yes' but $CONSUMER has no such script: ${missing[*]}"
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

@test "the guide's caller examples match the fixture's workflow files byte for byte" {
  n=0
  for wf in ci web pr-closed pr-title; do
    n=$((n + 1))
    file="$FIXTURES/consumer-min/.github/workflows/$wf.yml"
    [ -f "$file" ] || fail "missing fixture caller $file"
    diff -u "$file" <(guide_yaml_block "$n") \
      || fail "the guide's $wf.yml example has drifted from $file"
  done
}

@test "every workflow_call input is documented in the guide's table for that workflow" {
  command -v yq >/dev/null || skip "yq not installed"
  missing=()
  for wf in checks unit e2e web pr-title \
    expo-prepare expo-build-ios expo-build-android \
    fastlane-lane github-release expo-ota-publish; do
    file="$REPO_ROOT/.github/workflows/$wf.yml"
    section="$(guide_section "$wf.yml")"
    [ -n "$section" ] || fail "no '### \`$wf.yml\`' section in docs/consumer-guide.md"
    inputs="$(yq -r '.on.workflow_call.inputs | keys | .[]' "$file")" \
      || fail "yq failed to read inputs from $file"
    # Every one of these declares at least the six common inputs; an empty read
    # means the file moved or its shape changed, not that it has no inputs.
    [ "$(grep -c . <<<"$inputs")" -ge 6 ] || fail "read only '$inputs' from $file"
    while read -r input; do
      [ -n "$input" ] || continue
      grep -qF -- "\`$input\`" <<<"$section" || missing+=("$wf.yml:$input")
    done <<<"$inputs"
  done
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented inputs: ${missing[*]}"
}

@test "pr-closed.yml really declares no workflow_call inputs" {
  command -v yq >/dev/null || skip "yq not installed"
  run yq -r '.on.workflow_call.inputs // "null"' "$REPO_ROOT/.github/workflows/pr-closed.yml"
  [ "$status" -eq 0 ]
  [ "$output" = "null" ]
}
