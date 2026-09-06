#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# env-json.sh is build-env.sh's near-twin (same validator shape, same
# $GITHUB_ENV writer, a looser key rule), so the cases here mirror
# test/build-env.bats deliberately: the two files carry the same holes when they
# drift, and mirrored tests are what notices.
load test_helper

setup() {
  export GITHUB_ENV="$BATS_TEST_TMPDIR/gh_env" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$RUNNER_TEMP"
  : > "$GITHUB_ENV"
}

publish() { run bash "$REPO_ROOT/scripts/release/env-json.sh"; }

# See test/build-env.bats: the runner's own parse of $GITHUB_ENV.
gh_env_keys() {
  awk '
    delim != "" { if ($0 == delim) delim = ""; next }
    /^[A-Za-z_][A-Za-z0-9_]*<</ { i = index($0, "<<"); print substr($0, 1, i - 1); delim = substr($0, i + 2); next }
    /^[A-Za-z_][A-Za-z0-9_]*=/ { i = index($0, "="); print substr($0, 1, i - 1); next }
  ' "$GITHUB_ENV"
}

@test "publishes keys to GITHUB_ENV, coercing scalars" {
  RNW_ENV_JSON='{"APP_VARIANT":"beta","track":"internal","PHASED":true,"N":3,"EMPTY":null}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx 'APP_VARIANT=beta' "$GITHUB_ENV" || fail "APP_VARIANT missing: $(cat "$GITHUB_ENV")"
  grep -qx 'track=internal' "$GITHUB_ENV" || fail "a lower-case key was rejected: $(cat "$GITHUB_ENV")"
  grep -qx 'PHASED=true' "$GITHUB_ENV" || fail "boolean not coerced: $(cat "$GITHUB_ENV")"
  grep -qx 'N=3' "$GITHUB_ENV" || fail "number not coerced: $(cat "$GITHUB_ENV")"
  grep -qx 'EMPTY=' "$GITHUB_ENV" || fail "null not coerced to empty: $(cat "$GITHUB_ENV")"
}

@test "an empty object is a no-op, not an error" {
  RNW_ENV_JSON='{}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -s "$GITHUB_ENV" ] || fail "wrote something for an empty object: $(cat "$GITHUB_ENV")"
  RNW_ENV_JSON='' publish
  [ "$status" -eq 0 ] || fail "an unset value is not a no-op: $output"
}

@test "a malformed key is rejected" {
  RNW_ENV_JSON='{"1BAD":"x"}' publish
  [ "$status" -ne 0 ] || fail "accepted a key starting with a digit: $output"
  contains "$output" "not a valid env name" || fail "unexpected message: $output"
  RNW_ENV_JSON='{"A B":"x"}' publish
  [ "$status" -ne 0 ] || fail "accepted a key with a space: $output"
}

@test "a non-object or non-scalar value is rejected" {
  RNW_ENV_JSON='["a"]' publish
  [ "$status" -ne 0 ] || fail "accepted an array: $output"
  contains "$output" "flat JSON object" || fail "unexpected message: $output"
  RNW_ENV_JSON='{"A":{"b":1}}' publish
  [ "$status" -ne 0 ] || fail "accepted a nested object: $output"
  contains "$output" "must be a scalar" || fail "unexpected message: $output"
  RNW_ENV_JSON='not json' publish
  [ "$status" -ne 0 ] || fail "accepted invalid JSON: $output"
  contains "$output" "not valid JSON" || fail "unexpected message: $output"
}

# C1, the env-json half.
@test "a value containing a newline cannot inject a second variable" {
  RNW_ENV_JSON='{"APP_VARIANT":"a\nPATH=/evil"}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  keys="$(gh_env_keys)"
  [ "$keys" = "APP_VARIANT" ] || fail "GITHUB_ENV yields the wrong variables ($keys): $(cat "$GITHUB_ENV")"
  grep -q '^APP_VARIANT<<__rnw_eof_' "$GITHUB_ENV" \
    || fail "the multi-line value was not written in the heredoc form: $(cat "$GITHUB_ENV")"
  grep -qx 'PATH=/evil' "$GITHUB_ENV" || fail "the value was mangled: $(cat "$GITHUB_ENV")"
}

# I3, the env-json half: this input reaches $GITHUB_ENV just like build-env.
@test "a key owned by the family or the runner is refused" {
  for k in RNW_FP_IOS RNW_ASSETS_DIR GITHUB_REPOSITORY RUNNER_TEMP ACTIONS_STEP_DEBUG PATH HOME LD_PRELOAD NODE_OPTIONS; do
    RNW_ENV_JSON="{\"$k\":\"x\"}" publish
    [ "$status" -ne 0 ] || fail "accepted the reserved key $k: $output"
    contains "$output" "is reserved by react-native-workflows" || fail "unexpected message for $k: $output"
    [ ! -s "$GITHUB_ENV" ] || fail "wrote $k to GITHUB_ENV anyway: $(cat "$GITHUB_ENV")"
  done
}

@test "the scratch env file does not survive, on either path" {
  RNW_ENV_JSON='{"APP_VARIANT":"beta"}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -f "$RUNNER_TEMP/rnw-env-json.env" ] || fail "left a scratch file behind"
  RNW_ENV_JSON='{"A":{"b":1}}' publish
  [ "$status" -ne 0 ] || fail "accepted a nested object: $output"
  [ ! -f "$RUNNER_TEMP/rnw-env-json.env" ] || fail "left a scratch file behind after a rejection"
}
