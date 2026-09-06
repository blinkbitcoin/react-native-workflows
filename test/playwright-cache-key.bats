#!/usr/bin/env bats
load test_helper

@test "prints a plain version to stdout when GITHUB_OUTPUT is unset" {
  unset GITHUB_OUTPUT
  run bash "$REPO_ROOT/scripts/web/playwright-cache-key.sh" "$FIXTURES/consumer/pnpm-lock.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"version=1.62.1"* ]]
}

@test "writes version=<x> to GITHUB_OUTPUT when set" {
  out="$BATS_TEST_TMPDIR/gh_output"
  : > "$out"
  GITHUB_OUTPUT="$out" run bash "$REPO_ROOT/scripts/web/playwright-cache-key.sh" "$FIXTURES/consumer/pnpm-lock.yaml"
  [ "$status" -eq 0 ]
  grep -q '^version=1.62.1$' "$out"
}
