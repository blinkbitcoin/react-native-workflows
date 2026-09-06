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
  run die "boom"; [ "$status" -eq 1 ]; [[ "$output" == *"::error::boom"* ]] || fail "assertion failed; output: $output"
}
@test "gh_env_once appends key=value once, even called twice with the same GITHUB_ENV" {
  GITHUB_ENV="$BATS_TEST_TMPDIR/env"; export GITHUB_ENV
  : > "$GITHUB_ENV"
  gh_env_once RNW_OUT /tmp/out
  gh_env_once RNW_OUT /tmp/out
  [ "$(grep -c '^RNW_OUT=' "$GITHUB_ENV")" -eq 1 ]
  grep -qxF "RNW_OUT=/tmp/out" "$GITHUB_ENV"
}
@test "gh_env_once exports the variable even when GITHUB_ENV is unset" {
  unset GITHUB_ENV
  gh_env_once FOO bar
  [ "$FOO" = "bar" ]
}
@test "gh_env writes the plain form for a plain value and exports it" {
  GITHUB_ENV="$BATS_TEST_TMPDIR/env"; export GITHUB_ENV
  : > "$GITHUB_ENV"
  gh_env RNW_SHA deadbeef
  grep -qx 'RNW_SHA=deadbeef' "$GITHUB_ENV" || fail "not the plain form: $(cat "$GITHUB_ENV")"
  [ "$RNW_SHA" = "deadbeef" ] || fail "gh_env did not export the value"
}
@test "gh_env routes a newline-bearing value through the heredoc form" {
  GITHUB_ENV="$BATS_TEST_TMPDIR/env"; export GITHUB_ENV
  : > "$GITHUB_ENV"
  gh_env NOTES "$(printf 'one\ntwo')"
  head -1 "$GITHUB_ENV" | grep -q '^NOTES<<__rnw_eof_' || fail "not the heredoc form: $(cat "$GITHUB_ENV")"
  delim="$(head -1 "$GITHUB_ENV" | sed 's/^NOTES<<//')"
  [ "$(tail -1 "$GITHUB_ENV")" = "$delim" ] || fail "the block is not closed with its delimiter: $(cat "$GITHUB_ENV")"
  [ "$NOTES" = "$(printf 'one\ntwo')" ] || fail "gh_env did not export the value intact"
}
@test "gh_env_multiline refuses a value carrying its own delimiter" {
  GITHUB_ENV="$BATS_TEST_TMPDIR/env"; export GITHUB_ENV
  : > "$GITHUB_ENV"
  # Seeding RANDOM makes the generated delimiter reproducible *within one
  # process* (bash re-seeds it in a subshell), which is the only way a value can
  # be crafted to contain it - so the whole case runs inside one `bash -c`.
  run bash -c '
    source "$1/scripts/lib/common.sh"
    RANDOM=42; delim="__rnw_eof_${RANDOM}${RANDOM}"
    RANDOM=42; gh_env_multiline NOTES "before
$delim
after"
  ' _ "$REPO_ROOT"
  [ "$status" -ne 0 ] || fail "accepted a value containing the delimiter"
  contains "$output" "heredoc delimiter" || fail "unexpected message: $output"
}
@test "consumer_root honours WORKING_DIRECTORY" {
  GITHUB_WORKSPACE="$BATS_TEST_TMPDIR"; WORKING_DIRECTORY=app; export GITHUB_WORKSPACE WORKING_DIRECTORY
  mkdir -p "$BATS_TEST_TMPDIR/app"
  expected="$(cd "$BATS_TEST_TMPDIR/app" && pwd -P)"
  run consumer_root; [ "$output" = "$expected" ]
}
