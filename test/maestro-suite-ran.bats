#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# Maestro exits 0 when its flow selection matches nothing at all: a tag filter no
# flow carries, a renamed flows directory, a config.yaml whose includeTags
# stopped matching. The E2E job then went green having tested nothing, which is
# the most expensive kind of pass - indistinguishable from a real one, and it
# stays green until someone ships a broken build.
#
# workflows_assert_suite_ran reads the count out of the junit report Maestro already
# writes, so nothing extra runs. It lives in scripts/lib/e2e-env.sh, which both
# ios-maestro.sh and android-maestro.sh source, so the two platforms cannot
# drift apart on it.
load test_helper

setup() {
  export WORKFLOWS_OUT="$BATS_TEST_TMPDIR/out"
  export RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$WORKFLOWS_OUT" "$RUNNER_TEMP"
  unset GITHUB_ENV GITHUB_OUTPUT WORKFLOWS_MAESTRO_INCLUDE_TAGS WORKFLOWS_MAESTRO_EXCLUDE_TAGS
  JUNIT="$WORKFLOWS_OUT/junit.xml"
}

# Runs the assertion in a subshell that sources the library the same way the
# maestro scripts do.
assert_ran() {
  run bash -c '
    source "$1/scripts/lib/common.sh"
    source "$1/scripts/lib/e2e-env.sh"
    workflows_assert_suite_ran "$2" "$3"
  ' _ "$REPO_ROOT" "$1" "${2:-iOS}"
}

write_junit() {
  cat > "$JUNIT" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<testsuites>
  <testsuite name="Test Suite" tests="$1" failures="$2" time="1.0">
  </testsuite>
</testsuites>
XML
}

@test "a suite that ran zero flows is a failure, not a pass" {
  write_junit 0 0
  assert_ran "$JUNIT"
  [ "$status" -ne 0 ] || fail "a suite that ran nothing passed: $output"
  contains "$output" "ran 0 flows" || fail "the error does not say the suite was empty: $output"
}

@test "the zero-flow error names the tag filters, which are the usual cause" {
  write_junit 0 0
  run bash -c '
    source "$1/scripts/lib/common.sh"
    source "$1/scripts/lib/e2e-env.sh"
    WORKFLOWS_MAESTRO_INCLUDE_TAGS=smoke workflows_assert_suite_ran "$2" iOS
  ' _ "$REPO_ROOT" "$JUNIT"
  [ "$status" -ne 0 ] || fail "expected a failure: $output"
  contains "$output" "smoke" || fail "the error does not name the include tag: $output"
}

@test "a suite that ran flows passes and says how many" {
  write_junit 4 0
  assert_ran "$JUNIT"
  [ "$status" -eq 0 ] || fail "a real suite was rejected: $output"
  contains "$output" "ran 4 flow" || fail "the count is not reported: $output"
}

@test "a single flow is enough" {
  write_junit 1 0
  assert_ran "$JUNIT"
  [ "$status" -eq 0 ] || fail "exited $status: $output"
}

# Maestro's own exit status already covers failing flows; this guard is only
# about whether the suite existed. A report with failures still reaches here
# only when Maestro exited 0, but it must not be rejected by this check.
@test "the guard does not second-guess Maestro on failing flows" {
  write_junit 3 2
  assert_ran "$JUNIT"
  [ "$status" -eq 0 ] || fail "the guard rejected a suite that did run: $output"
}

@test "no junit report at all is a failure" {
  # Success with no report means nothing can show the suite ran, which is the
  # same hole by another route.
  assert_ran "$WORKFLOWS_OUT/does-not-exist.xml"
  [ "$status" -ne 0 ] || fail "a missing report passed: $output"
  contains "$output" "no junit report" || fail "unexpected message: $output"
}

@test "a junit report with no tests= attribute is a failure" {
  printf '<?xml version="1.0"?>\n<testsuites></testsuites>\n' > "$JUNIT"
  assert_ran "$JUNIT"
  [ "$status" -ne 0 ] || fail "an uncountable report passed: $output"
  contains "$output" "cannot confirm" || fail "unexpected message: $output"
}

@test "both platform scripts call the guard, and only on success" {
  for f in ios-maestro android-maestro; do
    path="$REPO_ROOT/scripts/e2e/$f.sh"
    grep -q 'workflows_assert_suite_ran' "$path" || fail "$f.sh does not assert the suite ran"
    # Gated on status 0: on a real failure Maestro's own status is the answer,
    # and an empty-report complaint would bury it.
    grep -qF 'if [ "$status" -eq 0 ]; then' "$path" \
      || fail "$f.sh calls the guard unconditionally; it must only run on success"
  done
}
