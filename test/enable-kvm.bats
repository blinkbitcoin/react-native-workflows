#!/usr/bin/env bats
load test_helper

setup() {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/sudo" <<'EOF'
#!/usr/bin/env bash
echo "sudo must not be invoked off a Linux GitHub Actions runner" >&2
exit 99
EOF
  chmod +x "$fakebin/sudo"
  cat > "$fakebin/udevadm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fakebin/udevadm"
  export PATH="$fakebin:$PATH"
  unset GITHUB_ACTIONS RUNNER_OS RNW_FORCE_RUNNER_SCRIPTS
}

@test "skips with a notice and never calls sudo when GITHUB_ACTIONS is unset" {
  run bash "$REPO_ROOT/scripts/ci/enable-kvm.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "skips with a notice and never calls sudo when RUNNER_OS is not Linux" {
  GITHUB_ACTIONS=true RUNNER_OS=macOS run bash "$REPO_ROOT/scripts/ci/enable-kvm.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping"* ]]
}

@test "RNW_FORCE_RUNNER_SCRIPTS=1 bypasses the guard (and would hit the sudo stub)" {
  RNW_FORCE_RUNNER_SCRIPTS=1 run bash "$REPO_ROOT/scripts/ci/enable-kvm.sh"
  [ "$status" -eq 99 ]
  [[ "$output" == *"sudo must not be invoked"* ]]
}
