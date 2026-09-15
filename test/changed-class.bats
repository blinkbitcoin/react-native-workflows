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

@test "docs-only=true when base branch advances with a src/ change after the PR forked (merge-base semantics)" {
  commit_file "README.md"
  fork_point=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" checkout -q -b pr "$fork_point"
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  git -C "$repo" checkout -q main
  commit_file "src/unrelated.ts"
  base=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

@test "DOCS_GLOBS_EXTRA is additive: the built-in docs patterns still apply" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "spec/a.txt"
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && DOCS_GLOBS_EXTRA='^spec/' run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

@test "DOCS_GLOBS_EXTRA does not make a src file docs" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "spec/a.txt"
  commit_file "src/a.ts"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && DOCS_GLOBS_EXTRA='^spec/' run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=false" ]
}

@test "DOCS_GLOBS still replaces the default pattern outright" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && DOCS_GLOBS='^spec/' run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
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

# checks.yml now passes github.event.before on a push, so the classifier sees
# push-shaped ranges too. A merge to main that only moved docs must skip the
# matrix exactly as the PR that preceded it did.
@test "docs-only=true for a push-shaped range (previous tip -> new tip) of only docs/" {
  commit_file "src/a.ts"
  before=$(git -C "$repo" rev-parse HEAD)
  commit_file "docs/guide.md"
  commit_file "docs/other.md"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$before" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

# `^LICENSE$` matched only the root copy, so a copyright bump across a
# monorepo's per-package LICENSE files ran the whole native matrix.
@test "docs-only=true for a per-package LICENSE, not just the root one" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "LICENSE"
  commit_file "packages/core/LICENSE"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=true" ]
}

@test "docs-only=false when a LICENSE-adjacent path is not a LICENSE file" {
  commit_file "other.txt"
  base=$(git -C "$repo" rev-parse HEAD)
  commit_file "src/LICENSE.ts"
  head=$(git -C "$repo" rev-parse HEAD)
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$base" "$head"
  [ "$status" -eq 0 ]
  [ "$output" = "docs-only=false" ]
}

# github.event.before on the first push of a new branch. Failing open here
# means docs-only=false and exit 0 - never an aborted step under `set -e`.
@test "all-zero BASE fails open: docs-only=false, exit 0, with a notice" {
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  zero=0000000000000000000000000000000000000000
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$zero" "$head"
  [ "$status" -eq 0 ]
  grep -qF "docs-only=false" <<<"$output" || fail "expected docs-only=false, got: $output"
  grep -qF "::notice::" <<<"$output" || fail "expected a ::notice:: annotation, got: $output"
}

# A force-push or a shallow clone can leave the recorded base absent from the
# checkout; `git diff` would exit non-zero and take the step with it.
@test "unreachable BASE fails open: docs-only=false, exit 0, with a notice" {
  commit_file "docs/x.md"
  head=$(git -C "$repo" rev-parse HEAD)
  missing=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  cd "$repo" && run bash "$REPO_ROOT/scripts/ci/changed-class.sh" "$missing" "$head"
  [ "$status" -eq 0 ]
  grep -qF "docs-only=false" <<<"$output" || fail "expected docs-only=false, got: $output"
  grep -qF "::notice::" <<<"$output" || fail "expected a ::notice:: annotation, got: $output"
}
