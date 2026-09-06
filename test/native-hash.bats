#!/usr/bin/env bats
load test_helper
@test "hash is 16 hex chars and stable" {
  run bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$FIXTURES/consumer"; [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9a-f]{16}$ ]] || fail "assertion failed; output: $output"
  first="$output"; run bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$FIXTURES/consumer"; [ "$output" = "$first" ]
}
@test "hash changes when a native dep version changes but not for a jest bump" {
  cp -R "$FIXTURES/consumer" "$BATS_TEST_TMPDIR/c"
  base=$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")
  sed -i.bak "258s/\^30\.5\.1/^30.5.2/" "$BATS_TEST_TMPDIR/c/pnpm-lock.yaml"   # jest specifier bump keeps hash
  [ "$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")" = "$base" ]
  sed -i.bak "129s/57\.0\.20(f4e16336c3bbb067508522a18420e9a2)/57.0.21(f4e16336c3bbb067508522a18420e9a2)/" "$BATS_TEST_TMPDIR/c/pnpm-lock.yaml"   # expo version bump changes hash
  [ "$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")" != "$base" ]
}
@test "NATIVE_EXTRA_GLOBS folds in the contents of the matched files, not just the pattern" {
  cp -R "$FIXTURES/consumer" "$BATS_TEST_TMPDIR/c"
  mkdir -p "$BATS_TEST_TMPDIR/c/fastlane"
  printf 'lane :one\n' > "$BATS_TEST_TMPDIR/c/fastlane/Fastfile.rb"
  base=$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")
  with_glob=$(NATIVE_EXTRA_GLOBS='fastlane/*.rb' bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")
  [ "$with_glob" != "$base" ]
  printf 'lane :two\n' > "$BATS_TEST_TMPDIR/c/fastlane/Fastfile.rb"
  changed=$(NATIVE_EXTRA_GLOBS='fastlane/*.rb' bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")
  [ "$changed" != "$with_glob" ]
}
@test "NATIVE_EXTRA_GLOBS matching nothing is not an error" {
  run env NATIVE_EXTRA_GLOBS='nowhere/*.rb other/*' bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$FIXTURES/consumer"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{16}$ ]] || fail "assertion failed; output: $output"
}
