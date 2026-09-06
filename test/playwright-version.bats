#!/usr/bin/env bats
load test_helper
@test "extracts the playwright version from the lockfile" {
  run bash "$REPO_ROOT/scripts/web/playwright-version.sh" "$FIXTURES/consumer/pnpm-lock.yaml"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
  [ "$output" = "1.62.1" ]
}
