#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
load test_helper

# `gh` is stubbed with a script that emits the next line of a canned response
# file on each call, so a multi-poll sequence (queued -> in_progress -> success)
# is exercised without a network or a real 30s sleep.
setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  RESPONSES="$BATS_TEST_TMPDIR/responses"
  COUNTER="$BATS_TEST_TMPDIR/counter"
  printf '0\n' > "$COUNTER"
  cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
n=$(cat "$RNW_TEST_COUNTER")
n=$((n + 1))
printf '%s\n' "$n" > "$RNW_TEST_COUNTER"
line=$(sed -n "${n}p" "$RNW_TEST_RESPONSES")
[ -n "$line" ] || line=$(tail -1 "$RNW_TEST_RESPONSES")
printf '%s\n' "$line"
SH
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  export RNW_TEST_RESPONSES="$RESPONSES" RNW_TEST_COUNTER="$COUNTER"
  export RNW_GREEN_POLL_SECONDS=0
  unset GITHUB_OUTPUT
}

green() { run bash "$REPO_ROOT/scripts/release/require-green-run.sh" release-internal.yml abc123; }

@test "a completed successful run passes immediately" {
  printf '%s\n' '[{"conclusion":"success","status":"completed","databaseId":11}]' > "$RESPONSES"
  green
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$output" "run 11 for abc123 succeeded" || fail "unexpected message: $output"
}

@test "polls while the run is still going, then passes" {
  {
    printf '%s\n' '[{"conclusion":null,"status":"queued","databaseId":11}]'
    printf '%s\n' '[{"conclusion":null,"status":"in_progress","databaseId":11}]'
    printf '%s\n' '[{"conclusion":"success","status":"completed","databaseId":11}]'
  } > "$RESPONSES"
  green
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$output" "is queued" || fail "did not report the queued poll: $output"
  contains "$output" "is in_progress" || fail "did not report the in_progress poll: $output"
  contains "$output" "succeeded" || fail "did not report success: $output"
}

@test "a failed run is fatal" {
  printf '%s\n' '[{"conclusion":"failure","status":"completed","databaseId":12}]' > "$RESPONSES"
  green
  [ "$status" -ne 0 ] || fail "passed on a failed run: $output"
  contains "$output" "concluded 'failure'" || fail "unexpected message: $output"
}

@test "a cancelled run is fatal" {
  printf '%s\n' '[{"conclusion":"cancelled","status":"completed","databaseId":13}]' > "$RESPONSES"
  green
  [ "$status" -ne 0 ] || fail "passed on a cancelled run: $output"
  contains "$output" "concluded 'cancelled'" || fail "unexpected message: $output"
}

@test "a skipped run is fatal - nothing verified the commit" {
  printf '%s\n' '[{"conclusion":"skipped","status":"completed","databaseId":14}]' > "$RESPONSES"
  green
  [ "$status" -ne 0 ] || fail "passed on a skipped run: $output"
  contains "$output" "was skipped" || fail "unexpected message: $output"
}

@test "no run at all within the discovery window is fatal" {
  printf '%s\n' '[]' > "$RESPONSES"
  RNW_GREEN_DISCOVERY_MINUTES=0 green
  [ "$status" -ne 0 ] || fail "passed with no run at all: $output"
  contains "$output" "no release-internal.yml run found for abc123" || fail "unexpected message: $output"
}

@test "an unfinished run past the overall timeout is fatal" {
  printf '%s\n' '[{"conclusion":null,"status":"in_progress","databaseId":15}]' > "$RESPONSES"
  RNW_GREEN_TIMEOUT_MINUTES=0 green
  [ "$status" -ne 0 ] || fail "passed past the timeout: $output"
  contains "$output" "did not complete for abc123" || fail "unexpected message: $output"
}

@test "writes the run id to GITHUB_OUTPUT" {
  printf '%s\n' '[{"conclusion":"success","status":"completed","databaseId":99}]' > "$RESPONSES"
  out="$BATS_TEST_TMPDIR/gh_output"
  : > "$out"
  GITHUB_OUTPUT="$out" green
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -q '^run-id=99$' "$out" || fail "no run-id=99 in: $(cat "$out")"
}
