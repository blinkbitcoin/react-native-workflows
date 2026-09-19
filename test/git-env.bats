#!/usr/bin/env bats
# A git hook's environment must not reach a test's scratch repository.
#
# The suite runs from the pre-push hook, where git has exported GIT_DIR. This
# reproduces that from the outside: a nested bats run, started with the
# hook-shaped variables aimed at a victim repo, whose one test does what dozens
# of tests here do - `git init` a temp dir and commit into it. The commit must
# land in the temp dir, and the victim must come out exactly as it went in.
load test_helper

setup() {
  TMP="$(mktemp -d)"
  VICTIM="$TMP/victim"
  git init -q "$VICTIM"
  mkdir -p "$TMP/suite"
  cat > "$TMP/suite/inner.bats" <<INNER
load "$REPO_ROOT/test/test_helper"
@test "a scratch repo takes its own commit" {
  git init -q "\$BATS_TEST_TMPDIR/scratch"
  git -C "\$BATS_TEST_TMPDIR/scratch" -c user.name=t -c user.email=t@example.test \\
    commit -q --allow-empty -m leaked
  git -C "\$BATS_TEST_TMPDIR/scratch" tag leaked-tag
  [ "\$(git -C "\$BATS_TEST_TMPDIR/scratch" rev-list --count HEAD)" = 1 ]
}
INNER
}

teardown() { rm -rf "$TMP"; }

@test "hook-exported GIT_DIR, GIT_WORK_TREE and GIT_INDEX_FILE never reach a test's git calls" {
  GIT_DIR="$VICTIM/.git" GIT_WORK_TREE="$VICTIM" GIT_INDEX_FILE="$VICTIM/.git/index" \
    run bats "$TMP/suite/inner.bats"
  [ "$status" -eq 0 ] || fail "the nested suite failed under a hook environment: $output"

  commits="$(git -C "$VICTIM" rev-list --all --count)"
  [ "$commits" = 0 ] || fail "the victim repo received $commits commit(s) meant for a scratch repo"
  tags="$(git -C "$VICTIM" tag)"
  [ -z "$tags" ] || fail "the victim repo received a tag meant for a scratch repo: $tags"
  bare="$(git -C "$VICTIM" config --get core.bare)"
  [ "$bare" = false ] || fail "the victim repo's core.bare became '$bare'"
}

@test "test_helper clears every variable git calls repository-local" {
  # Set each one first: on a laptop none is set, and "still unset" would pass
  # against a helper that clears nothing.
  run env GIT_LOCAL_VARS="$(git rev-parse --local-env-vars)" BATS_TEST_FILENAME="$BATS_TEST_FILENAME" \
    bash -c '
      for var in $GIT_LOCAL_VARS; do export "$var=$PWD"; done
      . "$(dirname "$BATS_TEST_FILENAME")/test_helper.bash"
      for var in $GIT_LOCAL_VARS; do
        [ -z "${!var+set}" ] || { echo "$var"; exit 1; }
      done'
  [ "$status" -eq 0 ] || fail "still set after test_helper loaded: $output"
}
