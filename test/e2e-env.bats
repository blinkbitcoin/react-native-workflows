#!/usr/bin/env bats
load test_helper

# e2e-env.sh is a library (sourced, not executed), so each case sources it
# from a throwaway bash -c process rather than `run bash script.sh`.
setup() {
  GITHUB_ENV="$BATS_TEST_TMPDIR/github_env"
  : > "$GITHUB_ENV"
  export GITHUB_ENV
  RNW_OUT="$BATS_TEST_TMPDIR/out"
  export RNW_OUT
}

@test "publishes RNW_OUT and RNW_RUN_START to GITHUB_ENV" {
  run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; source '$REPO_ROOT/scripts/lib/e2e-env.sh'"
  [ "$status" -eq 0 ]
  grep -qxF "RNW_OUT=$RNW_OUT" "$GITHUB_ENV"
  grep -qxF "RNW_RUN_START=$RNW_OUT/run-start" "$GITHUB_ENV"
}

@test "sourcing twice in the same process appends each variable once" {
  run bash -c "
    source '$REPO_ROOT/scripts/lib/common.sh'
    source '$REPO_ROOT/scripts/lib/e2e-env.sh'
    source '$REPO_ROOT/scripts/lib/e2e-env.sh'
  "
  [ "$status" -eq 0 ]
  [ "$(grep -c '^RNW_OUT=' "$GITHUB_ENV")" -eq 1 ]
  [ "$(grep -c '^RNW_RUN_START=' "$GITHUB_ENV")" -eq 1 ]
}
