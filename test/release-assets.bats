#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# `gh` is stubbed with a script that records its argv and serves a release body
# out of a file, so all four modes are exercised - including the re-run of
# `append`, which is the only mode with a re-run story to get wrong.
load test_helper

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  ASSETS="$BATS_TEST_TMPDIR/assets"
  mkdir -p "$STUB" "$ASSETS"
  export RNW_TEST_LOG="$BATS_TEST_TMPDIR/gh.log"
  export RNW_TEST_BODY="$BATS_TEST_TMPDIR/body.md"
  export RNW_TEST_EXISTS="$BATS_TEST_TMPDIR/exists"
  : > "$RNW_TEST_LOG"
  printf 'Initial release notes.\n' > "$RNW_TEST_BODY"
  cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$RNW_TEST_LOG"
case "$1 $2" in
  "release view")
    case "$*" in
      *"--json url"*) printf 'https://example.test/releases/%s\n' "$3"; exit 0 ;;
      *"--json body"*) cat "$RNW_TEST_BODY"; exit 0 ;;
    esac
    [ -f "$RNW_TEST_EXISTS" ] || exit 1
    exit 0
    ;;
  "release create") : > "$RNW_TEST_EXISTS"; exit 0 ;;
  "release edit")
    # Mirror --notes-file into the stored body, so a second `append` sees the
    # body the first one wrote - which is the whole point of the re-run test.
    prev=""
    for a in "$@"; do
      [ "$prev" = "--notes-file" ] && cp "$a" "$RNW_TEST_BODY"
      prev="$a"
    done
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$STUB/gh"
  export PATH="$STUB:$PATH"
  export RNW_OUT="$BATS_TEST_TMPDIR/out" RNW_ASSETS_DIR="$ASSETS" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$RUNNER_TEMP"
  unset GITHUB_OUTPUT TITLE TARGET_SHA NOTES_FILE APPEND_TITLE
}

assets() {
  printf 'info\n' > "$ASSETS/build-info.json"
  printf 'ipa\n' > "$ASSETS/app.ipa"
  printf 'noise\n' > "$ASSETS/unrelated.txt"
}

release() { run bash "$REPO_ROOT/scripts/release/release-assets.sh" "$@"; }

@test "create-prerelease creates the release and uploads only the fixed asset set" {
  assets
  TAG=v1.2.3 TITLE='Release 1.2.3' TARGET_SHA=deadbeef release create-prerelease
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -q -- "release create v1.2.3 --prerelease .*--title Release 1.2.3.*--target deadbeef" "$RNW_TEST_LOG" \
    || fail "unexpected create argv: $(cat "$RNW_TEST_LOG")"
  upload="$(grep '^release upload' "$RNW_TEST_LOG")"
  contains "$upload" "build-info.json" || fail "build-info.json was not uploaded: $upload"
  contains "$upload" "app.ipa" || fail "app.ipa was not uploaded: $upload"
  contains "$upload" "SHA256SUMS" || fail "SHA256SUMS was not uploaded: $upload"
  not_contains "$upload" "unrelated.txt" || fail "a file outside the fixed set was uploaded: $upload"
  contains "$upload" "--clobber" || fail "upload is not idempotent (no --clobber): $upload"
}

@test "SHA256SUMS lists basenames and real digests" {
  assets
  TAG=v1.2.3 release create-prerelease
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ -f "$ASSETS/SHA256SUMS" ] || fail "no SHA256SUMS was written"
  grep -q ' build-info.json$' "$ASSETS/SHA256SUMS" || fail "no basename entry: $(cat "$ASSETS/SHA256SUMS")"
  ! grep -q '/' "$ASSETS/SHA256SUMS" || fail "SHA256SUMS contains a path, not just basenames"
  expected="$(cd "$ASSETS" && shasum -a 256 app.ipa | cut -d' ' -f1)"
  grep -q "^$expected  app.ipa$" "$ASSETS/SHA256SUMS" || fail "wrong digest for app.ipa"
}

@test "promote leaves the release out of latest, latest marks it" {
  : > "$RNW_TEST_EXISTS"
  TAG=v1.2.3 release promote
  [ "$status" -eq 0 ] || fail "promote exited $status: $output"
  grep -q -- "release edit v1.2.3 --prerelease=false --latest=false" "$RNW_TEST_LOG" \
    || fail "unexpected promote argv: $(cat "$RNW_TEST_LOG")"
  : > "$RNW_TEST_LOG"
  TAG=v1.2.3 release latest
  [ "$status" -eq 0 ] || fail "latest exited $status: $output"
  grep -q -- "release edit v1.2.3 --prerelease=false --latest$" "$RNW_TEST_LOG" \
    || fail "unexpected latest argv: $(cat "$RNW_TEST_LOG")"
}

@test "promote on a release that does not exist is fatal" {
  rm -f "$RNW_TEST_EXISTS"
  TAG=v9.9.9 release promote
  [ "$status" -ne 0 ] || fail "promoted a release that does not exist: $output"
  contains "$output" "does not exist" || fail "unexpected message: $output"
}

@test "append adds the section under its heading" {
  : > "$RNW_TEST_EXISTS"
  printf -- '- rolled out to 10%%\n' > "$BATS_TEST_TMPDIR/section.md"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$(cat "$RNW_TEST_BODY")" "Initial release notes." || fail "the existing body was dropped"
  contains "$(cat "$RNW_TEST_BODY")" "## Store rollout" || fail "no heading in: $(cat "$RNW_TEST_BODY")"
  contains "$(cat "$RNW_TEST_BODY")" "rolled out to 10%" || fail "no section body in: $(cat "$RNW_TEST_BODY")"
}

@test "append is idempotent - a re-run yields a byte-identical body" {
  : > "$RNW_TEST_EXISTS"
  printf -- '- rolled out to 10%%\n' > "$BATS_TEST_TMPDIR/section.md"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "first append exited $status: $output"
  first="$(cat "$RNW_TEST_BODY")"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "second append exited $status: $output"
  second="$(cat "$RNW_TEST_BODY")"
  [ "$first" = "$second" ] || fail "re-running append changed the body:
--- first ---
$first
--- second ---
$second"
  [ "$(grep -c '^## Store rollout$' "$RNW_TEST_BODY")" -eq 1 ] \
    || fail "the section is duplicated: $(cat "$RNW_TEST_BODY")"
}

@test "a re-run with different content replaces the section rather than stacking it" {
  : > "$RNW_TEST_EXISTS"
  printf -- '- rolled out to 10%%\n' > "$BATS_TEST_TMPDIR/section.md"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "first append exited $status: $output"
  printf -- '- rolled out to 100%%\n' > "$BATS_TEST_TMPDIR/section.md"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "second append exited $status: $output"
  body="$(cat "$RNW_TEST_BODY")"
  contains "$body" "rolled out to 100%" || fail "the new content is missing: $body"
  not_contains "$body" "rolled out to 10%\n" || fail "the stale content survived: $body"
  [ "$(grep -c '^## Store rollout$' "$RNW_TEST_BODY")" -eq 1 ] || fail "the section is duplicated: $body"
}

# The regression U1 was: the strip ran from the heading to the next `## `, so a
# notes file that itself starts with a heading terminated the strip early and its
# tail stacked on every re-run. That is the *default* shape - notes.sh's fallback
# writes `## <version> (<build>)`, and a release-please body starts with
# `## [x.y.z](...)`.
@test "append is idempotent when the notes file itself starts with a ## heading" {
  : > "$RNW_TEST_EXISTS"
  cat > "$BATS_TEST_TMPDIR/section.md" <<'EOF'
## [1.2.3](https://example.test/compare/v1.2.2...v1.2.3) (2026-09-06)

### Features

- a feature

### Bug Fixes

- a fix
EOF
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Release notes' release append
  [ "$status" -eq 0 ] || fail "first append exited $status: $output"
  first="$(cat "$RNW_TEST_BODY")"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Release notes' release append
  [ "$status" -eq 0 ] || fail "second append exited $status: $output"
  second="$(cat "$RNW_TEST_BODY")"
  [ "$first" = "$second" ] || fail "re-running append changed the body:
--- first ($(printf '%s' "$first" | wc -l | tr -d ' ') lines) ---
$first
--- second ($(printf '%s' "$second" | wc -l | tr -d ' ') lines) ---
$second"
  [ "$(grep -c '^- a feature$' "$RNW_TEST_BODY")" -eq 1 ] \
    || fail "the notes body is duplicated: $(cat "$RNW_TEST_BODY")"
  [ "$(grep -c '^### Bug Fixes$' "$RNW_TEST_BODY")" -eq 1 ] \
    || fail "a subsection survived the strip: $(cat "$RNW_TEST_BODY")"
}

@test "append migrates a body written before the markers existed, without stacking" {
  : > "$RNW_TEST_EXISTS"
  # Exactly what the pre-marker version of this script produced.
  cat > "$RNW_TEST_BODY" <<'EOF'
Initial release notes.

## Store rollout

- rolled out to 10%
EOF
  printf -- '- rolled out to 100%%\n' > "$BATS_TEST_TMPDIR/section.md"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "migration append exited $status: $output"
  [ "$(grep -c '^## Store rollout$' "$RNW_TEST_BODY")" -eq 1 ] \
    || fail "the legacy section was not replaced: $(cat "$RNW_TEST_BODY")"
  not_contains "$(cat "$RNW_TEST_BODY")" "rolled out to 10%
" || fail "the legacy content survived: $(cat "$RNW_TEST_BODY")"
  grep -qxF '<!-- rnw:append:Store rollout -->' "$RNW_TEST_BODY" \
    || fail "the migrated body carries no marker: $(cat "$RNW_TEST_BODY")"
  first="$(cat "$RNW_TEST_BODY")"
  TAG=v1.2.3 NOTES_FILE="$BATS_TEST_TMPDIR/section.md" APPEND_TITLE='Store rollout' release append
  [ "$status" -eq 0 ] || fail "second append exited $status: $output"
  [ "$first" = "$(cat "$RNW_TEST_BODY")" ] || fail "the run after migration was not idempotent"
}

@test "append without a notes file is fatal" {
  : > "$RNW_TEST_EXISTS"
  TAG=v1.2.3 release append
  [ "$status" -ne 0 ] || fail "appended nothing successfully: $output"
  contains "$output" "NOTES_FILE" || fail "unexpected message: $output"
}

@test "an unknown mode is fatal" {
  TAG=v1.2.3 release publish-everything
  [ "$status" -ne 0 ] || fail "accepted an unknown mode: $output"
  contains "$output" "unknown mode" || fail "unexpected message: $output"
}

@test "no assets in the directory is not an error" {
  : > "$RNW_TEST_EXISTS"
  TAG=v1.2.3 release latest
  [ "$status" -eq 0 ] || fail "exited $status with an empty assets dir: $output"
  contains "$output" "no release assets found" || fail "unexpected message: $output"
  ! grep -q '^release upload' "$RNW_TEST_LOG" || fail "uploaded with nothing to upload"
}
