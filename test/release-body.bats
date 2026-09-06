#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
load test_helper

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  export RNW_TEST_BODY="$BATS_TEST_TMPDIR/body.md"
  export RNW_TEST_FAIL="$BATS_TEST_TMPDIR/fail"
  cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
[ -f "$RNW_TEST_FAIL" ] && exit 1
cat "$RNW_TEST_BODY"
SH
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  export RNW_OUT="$BATS_TEST_TMPDIR/out" GITHUB_ENV="$BATS_TEST_TMPDIR/gh_env"
  : > "$GITHUB_ENV"
}

body() { run bash "$REPO_ROOT/scripts/release/release-body.sh" "$@"; }

@test "writes the release body and publishes RELEASE_BODY_FILE" {
  printf '## [1.2.3](https://x) (2026-09-06)\n\n- a feature\n' > "$RNW_TEST_BODY"
  body v1.2.3
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$(cat "$RNW_OUT/release-body.md")" "a feature" \
    || fail "the body was not written: $(cat "$RNW_OUT/release-body.md")"
  grep -q "^RELEASE_BODY_FILE=$RNW_OUT/release-body.md$" "$GITHUB_ENV" \
    || fail "RELEASE_BODY_FILE was not published: $(cat "$GITHUB_ENV")"
}

@test "an empty tag is fatal" {
  printf 'x\n' > "$RNW_TEST_BODY"
  body ""
  [ "$status" -ne 0 ] || fail "accepted an empty tag: $output"
  contains "$output" "release-tag input is empty" || fail "unexpected message: $output"
}

@test "a release that cannot be read is fatal" {
  : > "$RNW_TEST_FAIL"
  body v9.9.9
  [ "$status" -ne 0 ] || fail "succeeded on a missing release: $output"
  contains "$output" "could not read the body" || fail "unexpected message: $output"
}

@test "an empty body is fatal, not a silent fallback to the commit log" {
  : > "$RNW_TEST_BODY"
  body v1.2.3
  [ "$status" -ne 0 ] || fail "accepted an empty body: $output"
  contains "$output" "empty body" || fail "unexpected message: $output"
}
