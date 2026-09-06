#!/usr/bin/env bats
load test_helper

setup() {
  work="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$work"
  git -C "$work" init -q -b main
  git -C "$work" config user.email test@example.com
  git -C "$work" config user.name test
  git -C "$work" commit -q --allow-empty -m "chore: init"
}

@test "fails without TAG set" {
  run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -ne 0 ]
  [[ "$output" == *"TAG"* ]]
}

@test "--local moves vN and vN.M to the tagged commit without pushing" {
  git -C "$work" tag v0.1.0
  cd "$work"
  TAG=v0.1.0 run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -eq 0 ]
  run git tag --points-at HEAD
  [[ "$output" == *"v0"* ]]
  [[ "$output" == *"v0.1"* ]]
}

@test "moving major tag follows a later release to a new commit" {
  cd "$work"
  git tag v0.1.0
  TAG=v0.1.0 bash "$REPO_ROOT/scripts/self/tag-major.sh" --local

  git commit -q --allow-empty -m "feat: two"
  git tag v0.2.0
  TAG=v0.2.0 bash "$REPO_ROOT/scripts/self/tag-major.sh" --local

  run git tag --points-at HEAD
  [[ "$output" == *"v0"* ]]
  [[ "$output" == *"v0.2"* ]]

  older_commit=$(git rev-parse HEAD~1)
  run git tag --points-at "$older_commit"
  [[ "$output" == *"v0.1"* ]]
  [[ "$output" == *"v0.1.0"* ]]
  for line in "${lines[@]}"; do
    [ "$line" != "v0" ]
  done
}

@test "rejects a TAG that is not a plain vX.Y.Z" {
  cd "$work"
  git tag v0.1.0
  TAG=not-a-tag run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -ne 0 ]
}

@test "without --local it attempts to push (fails fast: no remote 'origin')" {
  cd "$work"
  git tag v0.1.0
  TAG=v0.1.0 run bash "$REPO_ROOT/scripts/self/tag-major.sh"
  [ "$status" -ne 0 ]
}

@test "a prerelease tag is skipped, not moved" {
  cd "$work"
  git tag v1.2.0-rc.1
  TAG=v1.2.0-rc.1 run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping prerelease"* ]]
  run git tag --points-at HEAD
  [ "$output" = "v1.2.0-rc.1" ]
  ! git rev-parse -q --verify refs/tags/v1 >/dev/null
  ! git rev-parse -q --verify refs/tags/v1.2 >/dev/null
}

@test "running the same TAG twice is idempotent" {
  cd "$work"
  git tag v0.1.0
  TAG=v0.1.0 run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -eq 0 ]
  first_v0="$(git rev-parse v0)"
  first_v01="$(git rev-parse v0.1)"

  TAG=v0.1.0 run bash "$REPO_ROOT/scripts/self/tag-major.sh" --local
  [ "$status" -eq 0 ]
  [ "$(git rev-parse v0)" = "$first_v0" ]
  [ "$(git rev-parse v0.1)" = "$first_v01" ]
  [ "$(git rev-parse v0)" = "$(git rev-parse HEAD)" ]
}
