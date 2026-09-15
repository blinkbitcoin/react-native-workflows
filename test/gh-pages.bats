#!/usr/bin/env bats
# gh-pages-lib.sh, publish-badges.sh and badges-cleanup.sh against a throwaway
# bare remote. This is the one place in the repo where a bug rewrites a branch
# instead of failing a check, so both risky paths are exercised for real: the
# orphan created when gh-pages does not exist yet, and the rebase-retry when a
# concurrent publish landed between our fetch and our push.
load test_helper

PUBLISH="$REPO_ROOT/scripts/ci/publish-badges.sh"
CLEANUP="$REPO_ROOT/scripts/ci/badges-cleanup.sh"

setup() {
  TMP="$(mktemp -d)"
  REMOTE="$TMP/remote.git"
  CONSUMER="$TMP/consumer"
  git init -q --bare "$REMOTE"
  git init -q -b main "$CONSUMER"
  git -C "$CONSUMER" config user.email t@example.com
  git -C "$CONSUMER" config user.name test
  echo "app source" > "$CONSUMER/app.txt"
  git -C "$CONSUMER" add app.txt
  git -C "$CONSUMER" commit -qm "feat: app"
  git -C "$CONSUMER" remote add origin "$REMOTE"
  git -C "$CONSUMER" push -q -u origin main
  render_badges "$CONSUMER" 100%
  export GITHUB_WORKSPACE="$CONSUMER"
  export RUNNER_TEMP="$TMP/runner"
  mkdir -p "$RUNNER_TEMP"
  export GH_PAGES_RETRY_DELAY=0
  export SHA=0123456789abcdef0123456789abcdef01234567
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# The render script's output, stubbed: these scripts only ever copy files.
render_badges() {
  local root="$1" coverage="$2"
  mkdir -p "$root/coverage/badge"
  for name in unit e2e; do
    printf '<svg>%s</svg>\n' "$name" > "$root/coverage/badge/$name.svg"
    printf '{"label":"%s"}\n' "$name" > "$root/coverage/badge/$name.json"
  done
  printf '<svg>%s</svg>\n' "$coverage" > "$root/coverage/badge/coverage.svg"
}

# A clone of the published branch, so assertions read what the remote actually has.
gh_pages_checkout() {
  local dir="$TMP/verify-$RANDOM"
  git clone -q -b gh-pages "$REMOTE" "$dir" 2>/dev/null || return 1
  echo "$dir"
}

remote_has_gh_pages() {
  git -C "$REMOTE" rev-parse --verify -q refs/heads/gh-pages >/dev/null
}

@test "the first publish creates gh-pages as an orphan carrying only badges" {
  ! remote_has_gh_pages || fail "the remote already has a gh-pages branch"
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "publish failed: $output"
  out="$(gh_pages_checkout)" || fail "no gh-pages branch on the remote after publishing"
  [ -f "$out/badges/main/unit.svg" ] || fail "no unit badge: $(find "$out" -type f)"
  [ -f "$out/badges/main/coverage.svg" ]
  [ -f "$out/badges/main/e2e.json" ]
  [ -f "$out/README.md" ]
  # The orphan must not carry the consumer's source tree with it.
  [ ! -e "$out/app.txt" ] || fail "gh-pages carries the consumer's source tree"
  # A true orphan: no parent, so gh-pages shares no history with main.
  parents="$(git -C "$out" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')"
  [ "$parents" = "1" ] || fail "the first gh-pages commit has a parent"
  contains "$(git -C "$out" log -1 --pretty=%s)" "chore(ci): badges for main @ 0123456" \
    || fail "unexpected commit subject: $(git -C "$out" log -1 --pretty=%s)"
}

@test "the consumer checkout is left on its own branch, untouched" {
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "publish failed: $output"
  [ "$(git -C "$CONSUMER" rev-parse --abbrev-ref HEAD)" = "main" ]
  [ -z "$(git -C "$CONSUMER" status --porcelain -- app.txt)" ]
}

@test "a second publish on another branch keeps the first branch's badges" {
  BRANCH=main bash "$PUBLISH"
  render_badges "$CONSUMER" 91%
  BRANCH=feat/two run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "second publish failed: $output"
  out="$(gh_pages_checkout)"
  [ -f "$out/badges/main/unit.svg" ] || fail "the first branch's badges were lost"
  contains "$(cat "$out/badges/feat/two/coverage.svg")" "91%" \
    || fail "the second branch's coverage badge is not the one just rendered"
  [ "$(git -C "$out" rev-list --count HEAD)" = "2" ]
}

@test "publishing identical badges again commits nothing" {
  BRANCH=main bash "$PUBLISH"
  before="$(git -C "$REMOTE" rev-parse gh-pages)"
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "publish failed: $output"
  contains "$output" "unchanged" || fail "expected an 'unchanged' notice: $output"
  [ "$(git -C "$REMOTE" rev-parse gh-pages)" = "$before" ] \
    || fail "an unchanged publish still moved the branch"
}

@test "a concurrent publish is rebased onto, not clobbered" {
  BRANCH=main bash "$PUBLISH"
  # Another branch's job lands between our fetch and our push. Its commit must
  # survive - clobbering it is the exact failure this retry exists to prevent.
  other="$TMP/other"
  git clone -q -b gh-pages "$REMOTE" "$other"
  git -C "$other" config user.email t@example.com
  git -C "$other" config user.name test
  mkdir -p "$other/badges/other"
  echo "<svg>other</svg>" > "$other/badges/other/unit.svg"
  git -C "$other" add -A
  git -C "$other" commit -qm "chore(ci): badges for other"
  # Our worktree is prepared against the now-stale tip, then the race lands.
  render_badges "$CONSUMER" 77%
  cd "$CONSUMER"
  source "$REPO_ROOT/scripts/lib/common.sh"
  source "$REPO_ROOT/scripts/ci/gh-pages-lib.sh"
  gh_pages_worktree "$RUNNER_TEMP/gh-pages"
  git -C "$other" push -q origin gh-pages
  mkdir -p "$RUNNER_TEMP/gh-pages/badges/main"
  cp "$CONSUMER/coverage/badge/coverage.svg" "$RUNNER_TEMP/gh-pages/badges/main/"
  git -C "$RUNNER_TEMP/gh-pages" add -A badges
  git -C "$RUNNER_TEMP/gh-pages" commit -qm "chore(ci): badges for main"
  run gh_pages_push "$RUNNER_TEMP/gh-pages"
  [ "$status" -eq 0 ] || fail "push never succeeded: $output"
  contains "$output" "rejected" || fail "expected the retry notice: $output"
  out="$(gh_pages_checkout)"
  [ -f "$out/badges/other/unit.svg" ] || fail "the concurrent publish was clobbered"
  contains "$(cat "$out/badges/main/coverage.svg")" "77%" || fail "our own badge did not land"
}

@test "a push that never succeeds fails loudly instead of reporting success" {
  BRANCH=main bash "$PUBLISH"
  cd "$CONSUMER"
  source "$REPO_ROOT/scripts/lib/common.sh"
  source "$REPO_ROOT/scripts/ci/gh-pages-lib.sh"
  gh_pages_worktree "$RUNNER_TEMP/gh-pages"
  echo x > "$RUNNER_TEMP/gh-pages/x.txt"
  git -C "$RUNNER_TEMP/gh-pages" add -A
  git -C "$RUNNER_TEMP/gh-pages" commit -qm "chore(ci): badges"
  rm -rf "$REMOTE"
  GH_PAGES_PUSH_ATTEMPTS=2 run gh_pages_push "$RUNNER_TEMP/gh-pages"
  [ "$status" -ne 0 ] || fail "a push to a vanished remote reported success"
  contains "$output" "could not push gh-pages in 2 attempts" || fail "unexpected error: $output"
}

@test "publish refuses a branch name that is not a safe path segment" {
  for bad in "../../etc" "a b" "" "/abs" "x/../y"; do
    BRANCH="$bad" run bash "$PUBLISH"
    [ "$status" -ne 0 ] || fail "publish accepted branch name '$bad'"
  done
  ! remote_has_gh_pages || fail "a rejected branch name still touched gh-pages"
}

@test "publish fails when the render script wrote nothing" {
  rm -rf "$CONSUMER/coverage/badge"
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -ne 0 ] || fail "publish succeeded with no badges: $output"
  contains "$output" "render script" || fail "unhelpful message: $output"
  mkdir -p "$CONSUMER/coverage/badge"
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -ne 0 ] || fail "publish succeeded with an empty badge directory"
}

@test "a skipped coverage badge leaves the published one alone" {
  BRANCH=main bash "$PUBLISH"
  # The render script writes no coverage.svg when Unit was skipped.
  rm "$CONSUMER/coverage/badge/coverage.svg"
  echo '<svg>unit2</svg>' > "$CONSUMER/coverage/badge/unit.svg"
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "publish failed: $output"
  out="$(gh_pages_checkout)"
  contains "$(cat "$out/badges/main/coverage.svg")" "100%" \
    || fail "the published coverage badge was blanked by a run that rendered none"
  contains "$(cat "$out/badges/main/unit.svg")" "unit2" || fail "the new unit badge did not land"
}

@test "cleanup with no gh-pages branch is a no-op, and creates none" {
  BRANCH=feat/gone run bash "$CLEANUP"
  [ "$status" -eq 0 ] || fail "cleanup failed: $output"
  contains "$output" "nothing to clean" || fail "unexpected output: $output"
  ! remote_has_gh_pages || fail "cleanup created a gh-pages branch"
}

@test "cleanup with no directory for this branch is a no-op" {
  BRANCH=main bash "$PUBLISH"
  before="$(git -C "$REMOTE" rev-parse gh-pages)"
  BRANCH=feat/never-published run bash "$CLEANUP"
  [ "$status" -eq 0 ] || fail "cleanup failed: $output"
  contains "$output" "nothing to clean" || fail "unexpected output: $output"
  [ "$(git -C "$REMOTE" rev-parse gh-pages)" = "$before" ]
}

@test "cleanup removes only the closed branch's directory" {
  BRANCH=main bash "$PUBLISH"
  BRANCH=feat/two bash "$PUBLISH"
  BRANCH=feat/two run bash "$CLEANUP"
  [ "$status" -eq 0 ] || fail "cleanup failed: $output"
  out="$(gh_pages_checkout)"
  [ ! -d "$out/badges/feat/two" ] || fail "the closed branch's badges are still there"
  [ -f "$out/badges/main/unit.svg" ] || fail "cleanup took another branch's badges"
  contains "$(git -C "$out" log -1 --pretty=%s)" "drop badges for closed branch feat/two" \
    || fail "unexpected commit subject: $(git -C "$out" log -1 --pretty=%s)"
}

@test "cleanup refuses an unsafe branch name" {
  BRANCH=main bash "$PUBLISH"
  before="$(git -C "$REMOTE" rev-parse gh-pages)"
  BRANCH="../main" run bash "$CLEANUP"
  [ "$status" -ne 0 ] || fail "cleanup accepted '../main'"
  [ "$(git -C "$REMOTE" rev-parse gh-pages)" = "$before" ]
}

@test "publishing twice in one job works (the worktree is reused, not stacked)" {
  BRANCH=main bash "$PUBLISH"
  render_badges "$CONSUMER" 88%
  BRANCH=main run bash "$PUBLISH"
  [ "$status" -eq 0 ] || fail "the second publish in the same job failed: $output"
  out="$(gh_pages_checkout)"
  contains "$(cat "$out/badges/main/coverage.svg")" "88%" || fail "the second publish did not land"
}
