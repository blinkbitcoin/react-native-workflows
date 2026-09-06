#!/usr/bin/env bats
# android-emulator.sh is device-bound, so only the pure plumbing is asserted
# here: which ports `prepare` reverses into the emulator. `adb` is stubbed and
# every invocation logged.
load test_helper

setup() {
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR/consumer"
  export WORKING_DIRECTORY=.
  export RNW_OUT="$BATS_TEST_TMPDIR/out"
  mkdir -p "$GITHUB_WORKSPACE" "$RNW_OUT"
  apk="$BATS_TEST_TMPDIR/app-debug.apk"
  : > "$apk"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ADB_LOG="$BATS_TEST_TMPDIR/adb.log"
  export ADB_LOG
  cat > "$bin/adb" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ADB_LOG"
STUB
  chmod +x "$bin/adb"
  PATH="$bin:$PATH"
  export PATH
  : > "$ADB_LOG"
}

@test "prepare reverses the Metro port and the default mock-API port 4000" {
  run bash "$REPO_ROOT/scripts/e2e/android-emulator.sh" prepare "$apk"
  [ "$status" -eq 0 ]
  grep -qx "reverse tcp:8081 tcp:8081" "$ADB_LOG"
  grep -qx "reverse tcp:4000 tcp:4000" "$ADB_LOG"
}

@test "RNW_MOCK_API_PORT overrides the reversed mock-API port" {
  RNW_MOCK_API_PORT=5001 run bash "$REPO_ROOT/scripts/e2e/android-emulator.sh" prepare "$apk"
  [ "$status" -eq 0 ]
  grep -qx "reverse tcp:5001 tcp:5001" "$ADB_LOG"
  ! grep -qx "reverse tcp:4000 tcp:4000" "$ADB_LOG"
}

@test "an empty RNW_MOCK_API_PORT reverses only Metro" {
  RNW_MOCK_API_PORT= run bash "$REPO_ROOT/scripts/e2e/android-emulator.sh" prepare "$apk"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^reverse ' "$ADB_LOG")" -eq 1 ]
  grep -qx "reverse tcp:8081 tcp:8081" "$ADB_LOG"
}
