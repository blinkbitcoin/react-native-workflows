#!/usr/bin/env bats
load test_helper

setup() {
  SECRETS="$BATS_TEST_TMPDIR/secrets"
  GH_ENV="$BATS_TEST_TMPDIR/gh_env"
  : > "$GH_ENV"
  export RNW_SECRETS_DIR="$SECRETS" GITHUB_ENV="$GH_ENV"
}

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

@test "round-trips a keystore and publishes its path" {
  ANDROID_UPLOAD_KEYSTORE_BASE64="$(b64 'keystore-bytes')" \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SECRETS/upload.keystore")" = "keystore-bytes" ]
  grep -q "^ANDROID_UPLOAD_KEYSTORE_PATH=$SECRETS/upload.keystore$" "$GH_ENV"
}

@test "decoded files are 0600 inside a 0700 directory" {
  ASC_KEY_P8_BASE64="$(b64 'p8-bytes')" \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  # `stat` differs between BSD and GNU; ls -l is the portable reading.
  [[ "$(ls -ld "$SECRETS" | cut -c1-10)" == "drwx------" ]]
  [[ "$(ls -l "$SECRETS/asc-key.p8" | cut -c1-10)" == "-rw-------" ]]
}

@test "never echoes a decoded value" {
  ASC_KEY_P8_BASE64="$(b64 'super-secret-key-material')" \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"super-secret-key-material"* ]]
  [[ "$output" == *"asc-key.p8"* ]]
}

@test "a raw (non-base64) Play service account JSON is written verbatim" {
  PLAY_SERVICE_ACCOUNT_JSON='{"type":"service_account"}' \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SECRETS/play-service-account.json")" = '{"type":"service_account"}' ]
  grep -q "^PLAY_SERVICE_ACCOUNT_JSON_PATH=$SECRETS/play-service-account.json$" "$GH_ENV"
}

@test "the base64 Play variable wins over the raw one" {
  PLAY_SERVICE_ACCOUNT_JSON='raw' \
    PLAY_SERVICE_ACCOUNT_JSON_BASE64="$(b64 '{"from":"base64"}')" \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SECRETS/play-service-account.json")" = '{"from":"base64"}' ]
}

@test "unset secrets are skipped, not fatal" {
  run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$SECRETS/upload.keystore" ]
  [ ! -f "$SECRETS/asc-key.p8" ]
}

@test "a value that decodes to nothing is fatal" {
  # A single space is valid base64 padding-wise but decodes to zero bytes - the
  # shape a truncated or wrongly-copied secret takes.
  ANDROID_UPLOAD_KEYSTORE_BASE64=' ' \
    run bash "$REPO_ROOT/scripts/release/decode-secrets.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
}
