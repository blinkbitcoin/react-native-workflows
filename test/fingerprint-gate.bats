#!/usr/bin/env bats
load test_helper

setup() {
  export RNW_OUT="$BATS_TEST_TMPDIR/out"
  INFO="$BATS_TEST_TMPDIR/build-info.json"
  cat > "$INFO" <<'JSON'
{
  "sha": "deadbeef",
  "version": "1.2.3",
  "buildNumber": 1042,
  "stage": "internal",
  "fingerprint": { "ios": "iosfp", "android": "androidfp" },
  "expoSdk": "^54.0.0",
  "reactNative": "0.81.0",
  "workflowRunId": "7",
  "artifacts": {}
}
JSON
}

@test "matching fingerprints pass the gate" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp \
    run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$INFO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ios fingerprint matches"* ]]
  [[ "$output" == *"android fingerprint matches"* ]]
}

@test "an iOS mismatch fails and names both hashes" {
  RNW_FP_IOS=changed RNW_FP_ANDROID=androidfp \
    run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$INFO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ios fingerprint mismatch"* ]]
  [[ "$output" == *"iosfp"* ]]
  [[ "$output" == *"changed"* ]]
  [[ "$output" == *"needs a new store build"* ]]
}

@test "an Android mismatch fails even when iOS matches" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=changed \
    run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$INFO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"android fingerprint mismatch"* ]]
}

@test "a missing build-info.json is fatal" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp \
    run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$BATS_TEST_TMPDIR/nope.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no channel build-info.json"* ]]
}

@test "a build-info.json without a fingerprint block is fatal, not a pass" {
  printf '{"version":"1.0.0"}\n' > "$BATS_TEST_TMPDIR/old.json"
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp \
    run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$BATS_TEST_TMPDIR/old.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"has no fingerprint.ios"* ]]
}
