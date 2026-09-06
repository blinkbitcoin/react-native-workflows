#!/usr/bin/env bats
load test_helper

setup() {
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo/src/graphql/generated"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
  echo "original" > "$repo/src/graphql/generated/schema.ts"
  git -C "$repo" add .
  git -C "$repo" commit -q -m "initial"
}

run_assert() {
  bash -c '
    set -euo pipefail
    cd "$1"
    source "$2/scripts/lib/common.sh"
    source "$2/scripts/lib/git-clean.sh"
    assert_clean_paths "$3"
  ' _ "$repo" "$REPO_ROOT" "src/graphql/generated"
}

@test "passes when the path tree is clean" {
  run run_assert
  [ "$status" -eq 0 ]
}

@test "fails on a tracked-file diff" {
  echo "changed" > "$repo/src/graphql/generated/schema.ts"
  run run_assert
  [ "$status" -ne 0 ]
  [[ "$output" == *"schema.ts"* ]]
}

@test "fails on a brand-new untracked file" {
  echo "new" > "$repo/src/graphql/generated/new-file.ts"
  run run_assert
  [ "$status" -ne 0 ]
  [[ "$output" == *"new-file.ts"* ]]
}
