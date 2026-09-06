#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# `fastlane` and `bundle` are stubbed with scripts that record their argv and
# the path variables they were handed, because those two things are the whole
# job of this wrapper: fastlane runs a lane with cwd = `fastlane/`, so a
# relative path silently resolves one directory too deep.
load test_helper

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  ROOT="$BATS_TEST_TMPDIR/app"
  mkdir -p "$STUB" "$ROOT"
  export RNW_TEST_LOG="$BATS_TEST_TMPDIR/lane.log"
  : > "$RNW_TEST_LOG"
  cat > "$STUB/fastlane" <<'SH'
#!/usr/bin/env bash
printf 'argv: %s\n' "$*" >> "$RNW_TEST_LOG"
for v in RNW_OUTPUT_DIR BUILD_INFO_FILE RELEASE_NOTES_STORE_FILE STORE_NOTES_JSON \
  ANDROID_UPLOAD_KEYSTORE_PATH PLAY_SERVICE_ACCOUNT_JSON_PATH ASC_KEY_P8_PATH BUNDLETOOL_JAR; do
  printf '%s=%s\n' "$v" "${!v-}" >> "$RNW_TEST_LOG"
done
printf 'argc: %s\n' "$#" >> "$RNW_TEST_LOG"
exit 0
SH
  cat > "$STUB/bundle" <<'SH'
#!/usr/bin/env bash
printf 'bundle: %s\n' "$*" >> "$RNW_TEST_LOG"
shift 2  # `exec fastlane`
exec fastlane "$@"
SH
  chmod +x "$STUB/fastlane" "$STUB/bundle"
  export PATH="$STUB:$PATH"
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR" WORKING_DIRECTORY=app
  export RNW_OUT="$BATS_TEST_TMPDIR/out" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$RUNNER_TEMP"
  unset GITHUB_ENV LANE_ARGS BUILD_INFO_FILE RELEASE_NOTES_STORE_FILE STORE_NOTES_JSON
}

lane() { run bash "$REPO_ROOT/scripts/release/fastlane.sh" "$@"; }

@test "runs the lane on PATH when the consumer has no Gemfile" {
  lane ios build
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx 'argv: ios build' "$RNW_TEST_LOG" || fail "unexpected argv: $(cat "$RNW_TEST_LOG")"
  ! grep -q '^bundle:' "$RNW_TEST_LOG" || fail "used bundler without a Gemfile"
  contains "$output" "unpinned" || fail "the unpinned fastlane was not called out: $output"
}

@test "prefers bundle exec when the consumer ships a Gemfile" {
  : > "$ROOT/Gemfile"
  lane android build
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -q '^bundle: exec fastlane android build$' "$RNW_TEST_LOG" \
    || fail "did not go through bundler: $(cat "$RNW_TEST_LOG")"
}

# The reason this wrapper exists: a lane's cwd is `fastlane/`, so a relative
# path resolves one directory too deep and the lane reads the wrong file.
@test "every path variable reaches the lane absolute" {
  root="$(cd "$ROOT" && pwd -P)"
  BUILD_INFO_FILE=release-meta/build-info.json \
    RELEASE_NOTES_STORE_FILE=release-meta/notes-store.txt \
    STORE_NOTES_JSON=release-meta/store-notes.json \
    ANDROID_UPLOAD_KEYSTORE_PATH=secrets/upload.jks \
    PLAY_SERVICE_ACCOUNT_JSON_PATH=/already/absolute.json \
    lane android build
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "BUILD_INFO_FILE=$root/release-meta/build-info.json" "$RNW_TEST_LOG" \
    || fail "BUILD_INFO_FILE was not absolutised: $(cat "$RNW_TEST_LOG")"
  grep -qx "RELEASE_NOTES_STORE_FILE=$root/release-meta/notes-store.txt" "$RNW_TEST_LOG" \
    || fail "RELEASE_NOTES_STORE_FILE was not absolutised: $(cat "$RNW_TEST_LOG")"
  grep -qx "STORE_NOTES_JSON=$root/release-meta/store-notes.json" "$RNW_TEST_LOG" \
    || fail "STORE_NOTES_JSON was not absolutised: $(cat "$RNW_TEST_LOG")"
  grep -qx "ANDROID_UPLOAD_KEYSTORE_PATH=$root/secrets/upload.jks" "$RNW_TEST_LOG" \
    || fail "ANDROID_UPLOAD_KEYSTORE_PATH was not absolutised: $(cat "$RNW_TEST_LOG")"
  # An already-absolute path is passed through untouched, not re-rooted.
  grep -qx "PLAY_SERVICE_ACCOUNT_JSON_PATH=/already/absolute.json" "$RNW_TEST_LOG" \
    || fail "an absolute path was rewritten: $(cat "$RNW_TEST_LOG")"
  # An unset variable stays unset rather than becoming the root directory.
  grep -qx "ASC_KEY_P8_PATH=" "$RNW_TEST_LOG" \
    || fail "an unset path variable was invented: $(cat "$RNW_TEST_LOG")"
  grep -q "^RNW_OUTPUT_DIR=/" "$RNW_TEST_LOG" || fail "RNW_OUTPUT_DIR is not absolute: $(cat "$RNW_TEST_LOG")"
}

@test "LANE_ARGS becomes separate argv entries, after the explicit ones" {
  LANE_ARGS='percentage:0.1 track:beta' lane android rollout skip:true
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx 'argv: android rollout skip:true percentage:0.1 track:beta' "$RNW_TEST_LOG" \
    || fail "unexpected argv: $(cat "$RNW_TEST_LOG")"
  # The point of the split: two arguments, not one string containing a space.
  grep -qx 'argc: 5' "$RNW_TEST_LOG" || fail "LANE_ARGS did not split: $(cat "$RNW_TEST_LOG")"
}

@test "an empty LANE_ARGS adds no argument at all" {
  LANE_ARGS='' lane ios build
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx 'argc: 2' "$RNW_TEST_LOG" || fail "an empty LANE_ARGS became an argument: $(cat "$RNW_TEST_LOG")"
}

@test "an unknown platform is fatal before anything runs" {
  lane windows build
  [ "$status" -ne 0 ] || fail "accepted an unknown platform: $output"
  contains "$output" "platform must be ios or android" || fail "unexpected message: $output"
  [ ! -s "$RNW_TEST_LOG" ] || fail "ran a lane anyway: $(cat "$RNW_TEST_LOG")"
}

@test "a missing lane name is fatal" {
  lane ios
  [ "$status" -ne 0 ] || fail "accepted a missing lane: $output"
  contains "$output" "usage" || fail "unexpected message: $output"
}

@test "no Gemfile and no fastlane on PATH is an explicit error" {
  rm "$STUB/fastlane"
  # /usr/bin and /bin only: a fastlane installed on this machine would
  # otherwise satisfy the lookup and the case would not test anything.
  export PATH="$STUB:/usr/bin:/bin"
  lane ios build
  [ "$status" -ne 0 ] || fail "succeeded without fastlane: $output"
  contains "$output" "missing command: fastlane" || fail "unexpected message: $output"
}
