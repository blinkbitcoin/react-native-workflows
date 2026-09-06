#!/usr/bin/env bats
load test_helper
@test "returns node version from .mise.toml" {
  run bash "$REPO_ROOT/scripts/ci/tool-version.sh" node "$FIXTURES/consumer/.mise.toml"
  [ "$status" -eq 0 ]
  [ "$output" = "24" ]
}
@test "returns ruby version from .mise.toml" {
  run bash "$REPO_ROOT/scripts/ci/tool-version.sh" ruby "$FIXTURES/consumer/.mise.toml"
  [ "$status" -eq 0 ]
  [ "$output" = "3.3" ]
}
@test "unknown tool exits 1 with an ::error annotation" {
  run bash "$REPO_ROOT/scripts/ci/tool-version.sh" nonexistent-tool "$FIXTURES/consumer/.mise.toml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"* ]] || fail "assertion failed; output: $output"
}
