#!/usr/bin/env bats
load test_helper

# e2e-env.sh is a library (sourced, not executed), so each case sources it
# from a throwaway bash -c process rather than `run bash script.sh`.
setup() {
  GITHUB_ENV="$BATS_TEST_TMPDIR/github_env"
  : > "$GITHUB_ENV"
  export GITHUB_ENV
  WORKFLOWS_OUT="$BATS_TEST_TMPDIR/out"
  export WORKFLOWS_OUT
}

@test "publishes WORKFLOWS_OUT and WORKFLOWS_RUN_START to GITHUB_ENV" {
  run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; source '$REPO_ROOT/scripts/lib/e2e-env.sh'"
  [ "$status" -eq 0 ]
  grep -qxF "WORKFLOWS_OUT=$WORKFLOWS_OUT" "$GITHUB_ENV"
  grep -qxF "WORKFLOWS_RUN_START=$WORKFLOWS_OUT/run-start" "$GITHUB_ENV"
}

@test "sourcing twice in the same process appends each variable once" {
  run bash -c "
    source '$REPO_ROOT/scripts/lib/common.sh'
    source '$REPO_ROOT/scripts/lib/e2e-env.sh'
    source '$REPO_ROOT/scripts/lib/e2e-env.sh'
  "
  [ "$status" -eq 0 ]
  [ "$(grep -c '^WORKFLOWS_OUT=' "$GITHUB_ENV")" -eq 1 ]
  [ "$(grep -c '^WORKFLOWS_RUN_START=' "$GITHUB_ENV")" -eq 1 ]
}

@test "sourcing from separate processes sharing GITHUB_ENV appends each variable once" {
  # Each GitHub Actions step is its own process; the dedupe guard must be
  # file-based (grep $GITHUB_ENV itself), not a shell-variable flag that only
  # survives within one process.
  run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; source '$REPO_ROOT/scripts/lib/e2e-env.sh'"
  [ "$status" -eq 0 ]
  run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; source '$REPO_ROOT/scripts/lib/e2e-env.sh'"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^WORKFLOWS_OUT=' "$GITHUB_ENV")" -eq 1 ]
  [ "$(grep -c '^WORKFLOWS_RUN_START=' "$GITHUB_ENV")" -eq 1 ]
}
