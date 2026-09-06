#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash for why a bare
# mid-body `[[ ]]` cannot fail a test under bash 3.2. That mattered most here:
# the "never echoes a decoded value" control below was previously the
# second-to-last line of its body and could not fail.
load test_helper

setup() {
  SECRETS="$BATS_TEST_TMPDIR/secrets"
  GH_ENV="$BATS_TEST_TMPDIR/gh_env"
  : > "$GH_ENV"
  export RNW_SECRETS_DIR="$SECRETS" GITHUB_ENV="$GH_ENV"
}

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }
decode() { run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"; }

@test "round-trips a keystore and publishes its path" {
  ANDROID_UPLOAD_KEYSTORE_BASE64="$(b64 'keystore-bytes')" decode
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(cat "$SECRETS/upload.keystore")" = "keystore-bytes" ] || fail "keystore content did not round-trip"
  grep -q "^ANDROID_UPLOAD_KEYSTORE_PATH=$SECRETS/upload.keystore$" "$GH_ENV" \
    || fail "no ANDROID_UPLOAD_KEYSTORE_PATH in: $(cat "$GH_ENV")"
}

@test "decoded files are 0600 inside a 0700 directory" {
  ASC_KEY_P8_BASE64="$(b64 'p8-bytes')" decode
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  # `stat` differs between BSD and GNU; ls -l is the portable reading.
  dir_mode="$(ls -ld "$SECRETS" | cut -c1-10)"
  file_mode="$(ls -l "$SECRETS/asc-key.p8" | cut -c1-10)"
  [ "$dir_mode" = "drwx------" ] || fail "secrets dir is $dir_mode, expected drwx------"
  [ "$file_mode" = "-rw-------" ] || fail "asc-key.p8 is $file_mode, expected -rw-------"
}

@test "never echoes a decoded value" {
  ASC_KEY_P8_BASE64="$(b64 'super-secret-key-material')" decode
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  not_contains "$output" "super-secret-key-material" \
    || fail "the decoded secret leaked into the log: $output"
  contains "$output" "asc-key.p8" || fail "no destination path logged: $output"
}

@test "a raw (non-base64) Play service account JSON is written verbatim" {
  PLAY_SERVICE_ACCOUNT_JSON='{"type":"service_account"}' decode
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(cat "$SECRETS/play-service-account.json")" = '{"type":"service_account"}' ] \
    || fail "raw JSON was not written verbatim"
  grep -q "^PLAY_SERVICE_ACCOUNT_JSON_PATH=$SECRETS/play-service-account.json$" "$GH_ENV" \
    || fail "no PLAY_SERVICE_ACCOUNT_JSON_PATH in: $(cat "$GH_ENV")"
}

@test "the base64 Play variable wins over the raw one" {
  PLAY_SERVICE_ACCOUNT_JSON='raw' \
    PLAY_SERVICE_ACCOUNT_JSON_BASE64="$(b64 '{"from":"base64"}')" decode
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(cat "$SECRETS/play-service-account.json")" = '{"from":"base64"}' ] \
    || fail "the raw variable won: $(cat "$SECRETS/play-service-account.json")"
}

# A one-character paste used to produce a 1-byte "service account" that only
# failed deep inside a Play lane, long after the expensive part of the release.
@test "a raw Play service account that is not JSON is fatal" {
  PLAY_SERVICE_ACCOUNT_JSON='{' decode
  [ "$status" -ne 0 ] || fail "accepted a truncated service account: $output"
  contains "$output" "is not valid JSON" || fail "unexpected message: $output"
  PLAY_SERVICE_ACCOUNT_JSON='x' decode
  [ "$status" -ne 0 ] || fail "accepted a one-character service account: $output"
}

@test "the raw guard does not leak the value it rejected" {
  PLAY_SERVICE_ACCOUNT_JSON='{"private_key":"super-secret-key-material"' decode
  [ "$status" -ne 0 ] || fail "accepted invalid JSON: $output"
  not_contains "$output" "super-secret-key-material" || fail "the rejected value leaked: $output"
}

@test "unset secrets are skipped, not fatal" {
  decode
  [ "$status" -eq 0 ] || fail "exited $status with no secrets set: $output"
  [ ! -f "$SECRETS/upload.keystore" ] || fail "wrote a keystore with no input"
  [ ! -f "$SECRETS/asc-key.p8" ] || fail "wrote a p8 with no input"
}

@test "a value that decodes to nothing is fatal" {
  # A single space is valid base64 padding-wise but decodes to zero bytes - the
  # shape a truncated or wrongly-copied secret takes.
  ANDROID_UPLOAD_KEYSTORE_BASE64=' ' decode
  [ "$status" -ne 0 ] || fail "exited 0 on an empty decode: $output"
  contains "$output" "::error::" || fail "no ::error:: annotation in: $output"
}
