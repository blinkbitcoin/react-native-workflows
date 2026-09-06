#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# build-info.json is the one machine-readable record of what a release build is:
# the OTA gate compares its `fingerprint`, the store lanes read
# `version`/`buildNumber`, and it ships as a release asset. The schema is
# asserted key by key here because renaming one is a breaking change for all
# three readers.
load test_helper

setup() {
  ROOT="$BATS_TEST_TMPDIR/app"
  mkdir -p "$ROOT"
  cat > "$ROOT/package.json" <<'JSON'
{
  "name": "consumer",
  "dependencies": { "expo": "^54.0.0", "react-native": "0.81.4" }
}
JSON
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR" WORKING_DIRECTORY=app
  export RNW_OUT="$BATS_TEST_TMPDIR/out" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  export RNW_RELEASE_META_DIR="$BATS_TEST_TMPDIR/meta"
  mkdir -p "$RUNNER_TEMP"
  unset GITHUB_ENV GITHUB_OUTPUT RNW_SHA GITHUB_SHA RNW_STAGE FP_IOS FP_ANDROID GITHUB_RUN_ID
  DEST="$RNW_RELEASE_META_DIR/build-info.json"
}

build_info() { run bash "$REPO_ROOT/scripts/release/build-info.sh"; }
field() { node -e 'const i=require(process.argv[1]);const p=process.argv[2].split(".");let v=i;for(const k of p)v=v?.[k];console.log(v===undefined?"undefined":JSON.stringify(v))' "$DEST" "$1"; }

@test "writes the documented schema" {
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1042 RNW_STAGE=beta RNW_SHA=deadbeef \
    FP_IOS=fp-i FP_ANDROID=fp-a GITHUB_RUN_ID=99 build_info
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ -f "$DEST" ] || fail "no build-info.json was written"
  [ "$(field sha)" = '"deadbeef"' ] || fail "wrong sha: $(cat "$DEST")"
  [ "$(field version)" = '"1.2.3"' ] || fail "wrong version: $(cat "$DEST")"
  # A number, not a string: the store lanes compare it numerically.
  [ "$(field buildNumber)" = '1042' ] || fail "buildNumber is not a number: $(cat "$DEST")"
  [ "$(field stage)" = '"beta"' ] || fail "wrong stage: $(cat "$DEST")"
  [ "$(field fingerprint.ios)" = '"fp-i"' ] || fail "wrong ios fingerprint: $(cat "$DEST")"
  [ "$(field fingerprint.android)" = '"fp-a"' ] || fail "wrong android fingerprint: $(cat "$DEST")"
  [ "$(field reactNative)" = '"0.81.4"' ] || fail "wrong reactNative: $(cat "$DEST")"
  [ "$(field workflowRunId)" = '"99"' ] || fail "wrong workflowRunId: $(cat "$DEST")"
  [ "$(field artifacts)" = '{}' ] || fail "artifacts is not an empty object: $(cat "$DEST")"
}

# The range operator is stripped so this file stays byte-comparable with the one
# the template writes: "^54.0.0" and "54.0.0" describe the same installed SDK.
@test "the version range operator is stripped" {
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1 RNW_SHA=x build_info
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field expoSdk)" = '"54.0.0"' ] || fail "the range operator survived: $(cat "$DEST")"
}

@test "a missing dependency and an unreadable package.json give null, not a failure" {
  rm "$ROOT/package.json"
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1 RNW_SHA=x build_info
  [ "$status" -eq 0 ] || fail "a consumer without package.json failed the release: $output"
  [ "$(field expoSdk)" = 'null' ] || fail "expoSdk is not null: $(cat "$DEST")"
  [ "$(field reactNative)" = 'null' ] || fail "reactNative is not null: $(cat "$DEST")"
}

@test "an unset fingerprint is null rather than an empty string" {
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1 RNW_SHA=x build_info
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field fingerprint.ios)" = 'null' ] || fail "ios fingerprint is not null: $(cat "$DEST")"
}

@test "the sha falls back to GITHUB_SHA when target-sha.sh did not run" {
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1 GITHUB_SHA=fallbacksha build_info
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field sha)" = '"fallbacksha"' ] || fail "wrong sha: $(cat "$DEST")"
}

@test "the stage defaults to development" {
  APP_VERSION=1.2.3 APP_BUILD_NUMBER=1 RNW_SHA=x build_info
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field stage)" = '"development"' ] || fail "wrong default stage: $(cat "$DEST")"
}

@test "a missing version or build number is fatal, and names the script to run" {
  APP_BUILD_NUMBER=1 build_info
  [ "$status" -ne 0 ] || fail "wrote a build-info without a version: $output"
  contains "$output" "resolve-version.sh" || fail "unexpected message: $output"
  APP_VERSION=1.2.3 build_info
  [ "$status" -ne 0 ] || fail "wrote a build-info without a build number: $output"
  contains "$output" "resolve-version.sh" || fail "unexpected message: $output"
  [ ! -f "$DEST" ] || fail "wrote a build-info.json anyway"
}
