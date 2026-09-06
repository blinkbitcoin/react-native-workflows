#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
load test_helper

setup() {
  export GITHUB_ENV="$BATS_TEST_TMPDIR/gh_env" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$RUNNER_TEMP"
  : > "$GITHUB_ENV"
}

publish() { run bash "$REPO_ROOT/scripts/release/build-env.sh"; }

@test "publishes valid keys to GITHUB_ENV" {
  RNW_BUILD_ENV='{"OTA_ENABLED":"true","EXPO_PUBLIC_API_URL":"https://x","STORE_NOTES_INCLUDE_CHANGELOG":true}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx 'OTA_ENABLED=true' "$GITHUB_ENV" || fail "OTA_ENABLED missing: $(cat "$GITHUB_ENV")"
  grep -qx 'EXPO_PUBLIC_API_URL=https://x' "$GITHUB_ENV" || fail "EXPO_PUBLIC_API_URL missing: $(cat "$GITHUB_ENV")"
  # A JSON boolean is coerced to the string GitHub's env file needs.
  grep -qx 'STORE_NOTES_INCLUDE_CHANGELOG=true' "$GITHUB_ENV" || fail "boolean not coerced: $(cat "$GITHUB_ENV")"
}

@test "logs key names but never values" {
  RNW_BUILD_ENV='{"EXPO_UPDATES_URL":"https://updates.example.test/very-distinctive"}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$output" "EXPO_UPDATES_URL" || fail "the key was not logged: $output"
  not_contains "$output" "very-distinctive" || fail "the value leaked into the log: $output"
}

@test "an empty object is a no-op, not an error" {
  RNW_BUILD_ENV='{}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -s "$GITHUB_ENV" ] || fail "wrote something for an empty build-env: $(cat "$GITHUB_ENV")"
}

@test "a lower-case or malformed key is rejected" {
  RNW_BUILD_ENV='{"ota_enabled":"true"}' publish
  [ "$status" -ne 0 ] || fail "accepted a lower-case key: $output"
  contains "$output" "not an upper-case env name" || fail "unexpected message: $output"
  RNW_BUILD_ENV='{"1BAD":"x"}' publish
  [ "$status" -ne 0 ] || fail "accepted a key starting with a digit: $output"
}

# build-env is a workflow input: GitHub neither masks it nor hides it from the
# run's parameters, so a credential passed through it is public.
@test "a key that looks like a credential is refused" {
  for k in API_KEY GITHUB_TOKEN ANDROID_UPLOAD_KEY_PASSWORD SOME_SECRET DB_CREDENTIALS; do
    RNW_BUILD_ENV="{\"$k\":\"x\"}" publish
    [ "$status" -ne 0 ] || fail "accepted the credential-looking key $k: $output"
    contains "$output" "looks like a credential" || fail "unexpected message for $k: $output"
  done
}

@test "a known credential name is refused even though it does not match the suffix rule" {
  RNW_BUILD_ENV='{"PLAY_SERVICE_ACCOUNT_JSON":"{}"}' publish
  [ "$status" -ne 0 ] || fail "accepted PLAY_SERVICE_ACCOUNT_JSON: $output"
  contains "$output" "looks like a credential" || fail "unexpected message: $output"
}

@test "a non-object or non-scalar value is rejected" {
  RNW_BUILD_ENV='["a"]' publish
  [ "$status" -ne 0 ] || fail "accepted an array: $output"
  contains "$output" "flat JSON object" || fail "unexpected message: $output"
  RNW_BUILD_ENV='{"A":{"b":1}}' publish
  [ "$status" -ne 0 ] || fail "accepted a nested object: $output"
  contains "$output" "must be a scalar" || fail "unexpected message: $output"
  RNW_BUILD_ENV='not json' publish
  [ "$status" -ne 0 ] || fail "accepted invalid JSON: $output"
  contains "$output" "not valid JSON" || fail "unexpected message: $output"
}

@test "the scratch env file does not survive" {
  RNW_BUILD_ENV='{"OTA_ENABLED":"true"}' publish
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -f "$RUNNER_TEMP/rnw-build-env.env" ] || fail "left a scratch file behind"
}
