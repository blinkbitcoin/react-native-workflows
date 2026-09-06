#!/usr/bin/env bats
load test_helper
setup() { source "$REPO_ROOT/scripts/lib/common.sh"; }
@test "gh_output appends key=value to GITHUB_OUTPUT" {
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"; export GITHUB_OUTPUT
  gh_output hash abc123
  run cat "$GITHUB_OUTPUT"; [ "$output" = "hash=abc123" ]
}
@test "gh_output prints to stdout when GITHUB_OUTPUT is unset" {
  unset GITHUB_OUTPUT
  run gh_output hash abc123; [ "$output" = "hash=abc123" ]
}
@test "die exits 1 with an ::error annotation" {
  run die "boom"; [ "$status" -eq 1 ]; [[ "$output" == *"::error::boom"* ]]
}
@test "consumer_root honours WORKING_DIRECTORY" {
  GITHUB_WORKSPACE="$BATS_TEST_TMPDIR"; WORKING_DIRECTORY=app; export GITHUB_WORKSPACE WORKING_DIRECTORY
  mkdir -p "$BATS_TEST_TMPDIR/app"
  expected="$(cd "$BATS_TEST_TMPDIR/app" && pwd -P)"
  run consumer_root; [ "$output" = "$expected" ]
}
