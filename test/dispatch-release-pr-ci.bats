#!/usr/bin/env bats
load test_helper

SCRIPT="$REPO_ROOT/scripts/self/dispatch-release-pr-ci.sh"

setup() {
  # A fake gh that records its arguments; the script must never reach GitHub
  # from a test.
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/gh.args"\n' "$BATS_TEST_TMPDIR" > "$bin/gh"
  chmod +x "$bin/gh"
  export PATH="$bin:$PATH"
  export GH_TOKEN=fake GH_REPO=blinkbitcoin/shared-workflows
}

@test "dispatches self-ci.yml on the release PR's head branch" {
  PR_JSON='{"headBranchName":"release-please--branches--main--components--shared-workflows","number":40}' \
    run bash "$SCRIPT"
  [ "$status" -eq 0 ] || fail "output: $output"
  args="$(tr '\n' ' ' < "$BATS_TEST_TMPDIR/gh.args")"
  contains "$args" "workflow run self-ci.yml" || fail "args: $args"
  contains "$args" "--repo blinkbitcoin/shared-workflows" || fail "args: $args"
  contains "$args" "--ref release-please--branches--main--components--shared-workflows" || fail "args: $args"
}

@test "an empty PR_JSON is an error, not a silent skip" {
  PR_JSON='' run bash "$SCRIPT"
  [ "$status" -ne 0 ] || fail "exited 0 with no PR"
  contains "$output" "::error::" || fail "output: $output"
  [ ! -f "$BATS_TEST_TMPDIR/gh.args" ] || fail "gh was called anyway"
}

@test "a PR without headBranchName is an error naming the missing field" {
  PR_JSON='{"number":40}' run bash "$SCRIPT"
  [ "$status" -ne 0 ] || fail "exited 0 without a branch"
  contains "$output" "headBranchName" || fail "output: $output"
  [ ! -f "$BATS_TEST_TMPDIR/gh.args" ] || fail "gh was called anyway"
}

@test "fails without GH_REPO" {
  unset GH_REPO
  PR_JSON='{"headBranchName":"x"}' run bash "$SCRIPT"
  [ "$status" -ne 0 ] || fail "exited 0 without GH_REPO"
  contains "$output" "GH_REPO" || fail "output: $output"
}
