#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# The property under test is precedence. A release job stages several artifacts
# into one directory with `merge-multiple: true`, whose order is undefined, so
# the digests and the record they belong to must be reconciled by this script
# rather than by whichever download happened to land last.
load test_helper

setup() {
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR" WORKING_DIRECTORY=.
  export RNW_OUT="$BATS_TEST_TMPDIR/out" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  export RNW_ASSETS_DIR="$BATS_TEST_TMPDIR/assets"
  mkdir -p "$RUNNER_TEMP" "$RNW_ASSETS_DIR"
  unset GITHUB_ENV GITHUB_OUTPUT
  BASE="$RNW_ASSETS_DIR/build-info.json"
}

merge() { run bash "$REPO_ROOT/scripts/release/merge-build-info.sh" "$@"; }
field() { node -e 'const i=require(process.argv[1]);const p=process.argv[2].split(".");let v=i;for(const k of p)v=v?.[k];console.log(v===undefined?"undefined":String(v))' "$BASE" "$1"; }

@test "the platform digests land on the release's record" {
  printf '{"sha":"abc","stage":"beta","artifacts":{}}\n' > "$BASE"
  printf '{"sha":"abc","stage":"internal","artifacts":{"apkSha256":"aaa","aabSha256":"bbb"}}\n' \
    > "$RNW_ASSETS_DIR/build-info.android.json"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field artifacts.apkSha256)" = "aaa" ] || fail "no apk digest: $(cat "$BASE")"
  [ "$(field artifacts.aabSha256)" = "bbb" ] || fail "no aab digest: $(cat "$BASE")"
}

# A platform copy is a snapshot of the record taken mid-job; letting it write
# back anything but `artifacts` is exactly the N1 bug in a new place.
@test "only artifacts is taken from the platform copy" {
  printf '{"sha":"this-run","stage":"beta","version":"1.2.3","artifacts":{}}\n' > "$BASE"
  printf '{"sha":"stale","stage":"internal","version":"0.0.1","artifacts":{"apkSha256":"aaa"}}\n' \
    > "$RNW_ASSETS_DIR/build-info.android.json"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field sha)" = "this-run" ] || fail "a stale sha was written back: $(cat "$BASE")"
  [ "$(field stage)" = "beta" ] || fail "a stale stage was written back: $(cat "$BASE")"
  [ "$(field version)" = "1.2.3" ] || fail "a stale version was written back: $(cat "$BASE")"
  [ "$(field artifacts.apkSha256)" = "aaa" ] || fail "the digest was not merged: $(cat "$BASE")"
}

@test "an existing artifacts entry survives a merge that does not mention it" {
  printf '{"sha":"abc","artifacts":{"dsymSha256":"ddd"}}\n' > "$BASE"
  printf '{"artifacts":{"apkSha256":"aaa"}}\n' > "$RNW_ASSETS_DIR/build-info.android.json"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field artifacts.dsymSha256)" = "ddd" ] || fail "an existing entry was dropped: $(cat "$BASE")"
  [ "$(field artifacts.apkSha256)" = "aaa" ] || fail "the new entry is missing: $(cat "$BASE")"
}

@test "several platform copies all contribute" {
  printf '{"sha":"abc","artifacts":{}}\n' > "$BASE"
  printf '{"artifacts":{"apkSha256":"aaa"}}\n' > "$RNW_ASSETS_DIR/build-info.android.json"
  printf '{"artifacts":{"ipaSha256":"iii"}}\n' > "$RNW_ASSETS_DIR/build-info.ios.json"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(field artifacts.apkSha256)" = "aaa" ] || fail "android's digest is missing: $(cat "$BASE")"
  [ "$(field artifacts.ipaSha256)" = "iii" ] || fail "ios's digest is missing: $(cat "$BASE")"
}

@test "with no base record the platform copy becomes one" {
  printf '{"sha":"abc","artifacts":{"apkSha256":"aaa"}}\n' > "$RNW_ASSETS_DIR/build-info.android.json"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ -f "$BASE" ] || fail "no build-info.json was produced"
  [ "$(field artifacts.apkSha256)" = "aaa" ] || fail "wrong content: $(cat "$BASE")"
}

@test "no platform copy is a no-op, not an error" {
  printf '{"sha":"abc","artifacts":{}}\n' > "$BASE"
  before="$(cat "$BASE")"
  merge
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ "$(cat "$BASE")" = "$before" ] || fail "rewrote the record with nothing to merge"
  contains "$output" "nothing to merge" || fail "unexpected message: $output"
}

@test "a missing directory is a no-op, not an error" {
  merge "$BATS_TEST_TMPDIR/nowhere"
  [ "$status" -eq 0 ] || fail "exited $status on a missing directory: $output"
}
