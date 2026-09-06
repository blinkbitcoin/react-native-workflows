#!/usr/bin/env bats
load test_helper

setup() {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  # A PATH without any coreutils timeout, so the pure-bash watchdog is the
  # branch under test unless a stub is planted explicitly.
  export PATH="$fakebin:/usr/bin:/bin"
  export RNW_OUT="$BATS_TEST_TMPDIR/out"
  mkdir -p "$RNW_OUT"
}

plant_timeout_stub() {
  cat > "$fakebin/timeout" <<'EOF'
#!/bin/bash
echo "STUB TIMEOUT: $*"
exit 124
EOF
  chmod +x "$fakebin/timeout"
}

@test "sourcing exposes bounded_maestro" {
  run bash -c ". '$REPO_ROOT/scripts/e2e/maestro-bound.sh'; declare -F bounded_maestro"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bounded_maestro"* ]]
}

@test "a fast command's exit code is propagated" {
  run bash -c ". '$REPO_ROOT/scripts/e2e/maestro-bound.sh'; bounded_maestro 30 bash -c 'exit 7'"
  [ "$status" -eq 7 ]
}

@test "a fast command's success is propagated" {
  run bash -c ". '$REPO_ROOT/scripts/e2e/maestro-bound.sh'; bounded_maestro 30 bash -c 'echo hi'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hi"* ]]
}

@test "a slow command exits 124 via the pure-bash watchdog" {
  run bash -c ". '$REPO_ROOT/scripts/e2e/maestro-bound.sh'; bounded_maestro 1 sleep 30"
  [ "$status" -eq 124 ]
  [[ "$output" == *"::error::"* ]]
}

@test "coreutils timeout is used when available" {
  plant_timeout_stub
  run bash -c ". '$REPO_ROOT/scripts/e2e/maestro-bound.sh'; bounded_maestro 5 sleep 30"
  [ "$status" -eq 124 ]
  [[ "$output" == *"STUB TIMEOUT"* ]]
  [[ "$output" == *"-k 30s 5s"* ]]
}
