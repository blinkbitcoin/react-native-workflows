#!/usr/bin/env bats
load test_helper

@test "summary includes pass/fail counts and the artifact url" {
  run bash "$REPO_ROOT/scripts/ci/artifact-summary.sh" "E2E Results" "https://example.com/artifact/123" "$FIXTURES/junit-sample.xml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 passed, 1 failed"* ]]
  [[ "$output" == *"https://example.com/artifact/123"* ]]
  [[ "$output" == *"E2E Results"* ]]
}

@test "writes to GITHUB_STEP_SUMMARY when set, instead of stdout" {
  summary_file="$BATS_TEST_TMPDIR/summary.md"
  GITHUB_STEP_SUMMARY="$summary_file" run bash "$REPO_ROOT/scripts/ci/artifact-summary.sh" "E2E Results" "https://example.com/artifact/123" "$FIXTURES/junit-sample.xml"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q "2 passed, 1 failed" "$summary_file"
  grep -q "https://example.com/artifact/123" "$summary_file"
}

@test "works without a junit file (title and url only)" {
  run bash "$REPO_ROOT/scripts/ci/artifact-summary.sh" "Build" "https://example.com/artifact/9"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Build"* ]]
  [[ "$output" == *"https://example.com/artifact/9"* ]]
}
