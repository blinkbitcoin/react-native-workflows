#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
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
  "expoSdk": "54.0.0",
  "reactNative": "0.81.0",
  "workflowRunId": "7",
  "artifacts": {}
}
JSON
}

gate() { run bash "$REPO_ROOT/scripts/ota/fingerprint-gate.sh" "$1"; }

@test "matching fingerprints pass the gate" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp gate "$INFO"
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$output" "ios fingerprint matches" || fail "no ios match line in: $output"
  contains "$output" "android fingerprint matches" || fail "no android match line in: $output"
}

@test "an iOS mismatch fails and names both hashes" {
  RNW_FP_IOS=changed RNW_FP_ANDROID=androidfp gate "$INFO"
  [ "$status" -ne 0 ] || fail "the gate passed on an iOS mismatch: $output"
  contains "$output" "ios fingerprint mismatch" || fail "no mismatch line in: $output"
  contains "$output" "iosfp" || fail "the expected hash is not in the message: $output"
  contains "$output" "changed" || fail "the computed hash is not in the message: $output"
  contains "$output" "needs a new store build" || fail "no remediation in the message: $output"
}

@test "an Android mismatch fails even when iOS matches" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=changed gate "$INFO"
  [ "$status" -ne 0 ] || fail "the gate passed on an Android mismatch: $output"
  contains "$output" "android fingerprint mismatch" || fail "no mismatch line in: $output"
}

@test "a missing build-info.json is fatal" {
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp gate "$BATS_TEST_TMPDIR/nope.json"
  [ "$status" -ne 0 ] || fail "the gate passed with no baseline file: $output"
  contains "$output" "no channel build-info.json" || fail "unexpected message: $output"
}

@test "a build-info.json without a fingerprint block is fatal, not a pass" {
  printf '{"version":"1.0.0"}\n' > "$BATS_TEST_TMPDIR/old.json"
  RNW_FP_IOS=iosfp RNW_FP_ANDROID=androidfp gate "$BATS_TEST_TMPDIR/old.json"
  [ "$status" -ne 0 ] || fail "the gate passed on a baseline with no fingerprints: $output"
  contains "$output" "has no fingerprint.ios" || fail "unexpected message: $output"
}
