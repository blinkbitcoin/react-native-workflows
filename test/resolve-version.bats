#!/usr/bin/env bats
load test_helper

# `gh` is one of resolve-version.sh's optional version sources. On a developer
# machine it exists and would talk to whatever remote the temp repo appears to
# have, so every test runs with a stub that reports "no open release PR" - the
# gh path itself is not what these tests are about.
setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"
  chmod +x "$STUB/gh"
  PATH="$STUB:$PATH"
  REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name t
  unset GITHUB_OUTPUT GITHUB_ENV RELEASE_PR_TITLE BUILD_NUMBER_OFFSET
}

commit() { git -C "$REPO" commit -q --allow-empty -m "${1:-c}"; }

@test "a vX.Y.Z tag on HEAD wins over everything else" {
  commit
  git -C "$REPO" tag v1.2.3
  RELEASE_PR_TITLE='chore(main): release 9.9.9' \
    run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_VERSION=1.2.3"* ]]
}

@test "RELEASE_PR_TITLE supplies the version when HEAD has no tag" {
  commit
  RELEASE_PR_TITLE='chore(main): release 2.5.0' \
    run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_VERSION=2.5.0"* ]]
}

@test "falls back to a patch bump of the newest v* tag" {
  commit
  git -C "$REPO" tag v0.4.9
  commit second
  run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_VERSION=0.4.10"* ]]
}

@test "an untagged repository falls back to the default version" {
  commit
  run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_VERSION=0.1.0"* ]]
}

@test "build number is the first-parent commit count plus the default offset" {
  commit one
  commit two
  commit three
  run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_BUILD_NUMBER=1003"* ]]
}

@test "BUILD_NUMBER_OFFSET shifts the build number" {
  commit one
  BUILD_NUMBER_OFFSET=42 run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"APP_BUILD_NUMBER=43"* ]]
}

@test "a merge does not inflate the build number (first-parent only)" {
  commit base
  git -C "$REPO" checkout -q -b side
  commit side1
  commit side2
  git -C "$REPO" checkout -q main
  commit main1
  git -C "$REPO" merge -q --no-ff -m merge side
  run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  # base + main1 + the merge itself = 3 first-parent commits, not 5.
  [[ "$output" == *"APP_BUILD_NUMBER=1003"* ]]
}

@test "writes version and build-number to GITHUB_OUTPUT and GITHUB_ENV" {
  commit
  git -C "$REPO" tag v3.1.4
  out="$BATS_TEST_TMPDIR/gh_output"
  env_file="$BATS_TEST_TMPDIR/gh_env"
  : > "$out"
  : > "$env_file"
  GITHUB_OUTPUT="$out" GITHUB_ENV="$env_file" \
    run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -eq 0 ]
  grep -q '^version=3.1.4$' "$out"
  grep -q '^build-number=1001$' "$out"
  grep -q '^APP_VERSION=3.1.4$' "$env_file"
  grep -q '^APP_BUILD_NUMBER=1001$' "$env_file"
}

@test "a non-numeric BUILD_NUMBER_OFFSET is fatal" {
  commit
  BUILD_NUMBER_OFFSET=abc run bash "$REPO_ROOT/scripts/release/resolve-version.sh" "$REPO"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
}
