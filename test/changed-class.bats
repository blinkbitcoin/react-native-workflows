#!/usr/bin/env bats
load test_helper

setup() {
  repo="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "Test"
}

commit_file() {
  local path="$1"
  mkdir -p "$(dirname "$repo/$path")"
  echo "content $RANDOM" >> "$repo/$path"
  git -C "$repo" add "$path"
  git -C "$repo" commit -q -m "touch $path"
}

@test "docs-only=true when only docs/ files changed" {
  commit_file "README.md"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

@test "docs-only=false when a src file changed" {
  commit_file "README.md"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "src/a.ts"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=false" ]
}

@test "docs-only=true when README.md and docs/ changed together" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "README.md"
  commit_file "docs/y.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

@test "docs-only=false when a workflow file changed" {
  commit_file "README.md"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file ".github/workflows/ci.yml"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=false" ]
}

@test "docs-only=false when BASE is empty (push event)" {
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=false" ]
}
