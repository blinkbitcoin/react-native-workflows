#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# A real temp git repo, not a stubbed `git`: what is being tested is exactly
# what git says a tag resolves to, and a stub that answers "a sha" would pass
# whatever this script did with it.
load test_helper

setup() {
  ROOT="$BATS_TEST_TMPDIR/app"
  mkdir -p "$ROOT"
  git -C "$ROOT" init -q -b main
  git -C "$ROOT" config user.email t@example.test
  git -C "$ROOT" config user.name t
  printf 'a\n' > "$ROOT/a.txt"
  git -C "$ROOT" add -A
  git -C "$ROOT" commit -qm first
  git -C "$ROOT" tag v1.2.3
  printf 'b\n' >> "$ROOT/a.txt"
  git -C "$ROOT" commit -qam second
  TAG_SHA="$(git -C "$ROOT" rev-parse v1.2.3^{commit})"
  HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR" WORKING_DIRECTORY=app
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out" GITHUB_ENV="$BATS_TEST_TMPDIR/env"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_ENV"
  unset GITHUB_SHA
}

target_sha() { run bash "$REPO_ROOT/scripts/release/target-sha.sh" "$@"; }

# The whole reason this script exists: on a `release: published` event
# github.sha is the default branch's tip, which is already ahead of the tag.
@test "a tag resolves to the tag's commit, not to HEAD" {
  GITHUB_SHA="$HEAD_SHA" target_sha v1.2.3
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "sha=$TAG_SHA" "$GITHUB_OUTPUT" || fail "wrong sha output: $(cat "$GITHUB_OUTPUT")"
  grep -qx "RNW_SHA=$TAG_SHA" "$GITHUB_ENV" || fail "wrong RNW_SHA: $(cat "$GITHUB_ENV")"
  [ "$TAG_SHA" != "$HEAD_SHA" ] || fail "the fixture does not actually distinguish tag from HEAD"
}

@test "an annotated tag resolves to the commit it points at" {
  git -C "$ROOT" tag -a v2.0.0 -m release
  annotated="$(git -C "$ROOT" rev-parse v2.0.0^{commit})"
  target_sha v2.0.0
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "sha=$annotated" "$GITHUB_OUTPUT" || fail "the tag object's own sha leaked through: $(cat "$GITHUB_OUTPUT")"
}

@test "no tag falls back to GITHUB_SHA" {
  GITHUB_SHA=cafecafe target_sha ''
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "sha=cafecafe" "$GITHUB_OUTPUT" || fail "did not use GITHUB_SHA: $(cat "$GITHUB_OUTPUT")"
  contains "$output" "no release tag" || fail "unexpected message: $output"
}

@test "no tag and no GITHUB_SHA falls back to HEAD" {
  target_sha
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "sha=$HEAD_SHA" "$GITHUB_OUTPUT" || fail "did not use HEAD: $(cat "$GITHUB_OUTPUT")"
}

# The fetch fallback: no remote to fetch from, so it fails silently and the
# script dies with a message naming what the caller has to do.
@test "a tag that does not resolve is fatal, after trying to fetch it" {
  target_sha v9.9.9
  [ "$status" -ne 0 ] || fail "accepted an unknown tag: $output"
  contains "$output" "does not resolve to a commit" || fail "unexpected message: $output"
  [ ! -s "$GITHUB_OUTPUT" ] || fail "published a sha anyway: $(cat "$GITHUB_OUTPUT")"
}

@test "a tag missing locally is fetched from origin" {
  # A second clone that deliberately lacks the tag, with the first as origin.
  clone="$BATS_TEST_TMPDIR/clone"
  git clone -q --no-tags "$ROOT" "$clone"
  ! git -C "$clone" rev-parse --verify --quiet v1.2.3^{commit} >/dev/null \
    || fail "the fixture clone already has the tag, so the fetch path is not exercised"
  WORKING_DIRECTORY=clone target_sha v1.2.3
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -qx "sha=$TAG_SHA" "$GITHUB_OUTPUT" || fail "the tag was not fetched: $output"
}
