#!/usr/bin/env bats
load test_helper

# collect-forensics.sh selects iOS crash reports newer than $WORKFLOWS_OUT/run-start,
# the stamp e2e-env.sh drops once per run. The fixture is a fake $HOME whose
# DiagnosticReports folder holds one report from before the run and one from
# during it.
setup() {
  export WORKFLOWS_OUT="$BATS_TEST_TMPDIR/out"
  export HOME="$BATS_TEST_TMPDIR/home"
  reports="$HOME/Library/Logs/DiagnosticReports"
  mkdir -p "$WORKFLOWS_OUT" "$reports"

  printf 'old\n' > "$reports/before-the-run.ips"
  touch -t 202001010000 "$reports/before-the-run.ips"
  : > "$WORKFLOWS_OUT/run-start"
  touch -t 202101010000 "$WORKFLOWS_OUT/run-start"
  printf 'new\n' > "$reports/during-the-run.ips"
  touch -t 202201010000 "$reports/during-the-run.ips"
}

@test "copies only the crash reports newer than the run-start stamp" {
  run bash "$REPO_ROOT/scripts/e2e/collect-forensics.sh" ios
  [ "$status" -eq 0 ]
  [ -f "$WORKFLOWS_OUT/forensics/during-the-run.ips" ]
  [ ! -f "$WORKFLOWS_OUT/forensics/before-the-run.ips" ]
  [[ "$output" == *"iOS crash reports: 1"* ]] || fail "assertion failed; output: $output"
}

@test "falls back to the hour window when this process stamps the run itself" {
  rm -f "$WORKFLOWS_OUT/run-start"
  # Both fixture reports are years old, so an -mmin -60 window matches neither -
  # what is under test is that the script does not instead select against a
  # stamp it just created (which would also match neither, but for the wrong
  # reason). A fresh report proves the window is the branch in use.
  printf 'fresh\n' > "$reports/just-now.ips"
  run bash "$REPO_ROOT/scripts/e2e/collect-forensics.sh" ios
  [ "$status" -eq 0 ]
  [ -f "$WORKFLOWS_OUT/forensics/just-now.ips" ]
  [ ! -f "$WORKFLOWS_OUT/forensics/before-the-run.ips" ]
}

@test "copies the Maestro debug output and junit.xml into forensics/" {
  mkdir -p "$WORKFLOWS_OUT/maestro"
  printf '<testsuites tests="1" failures="0"/>\n' > "$WORKFLOWS_OUT/maestro/junit.xml"
  printf 'png\n' > "$WORKFLOWS_OUT/maestro/Login-3-tapOn.png"
  run bash "$REPO_ROOT/scripts/e2e/collect-forensics.sh" ios
  [ "$status" -eq 0 ]
  [ -f "$WORKFLOWS_OUT/forensics/maestro/junit.xml" ]
  [ -f "$WORKFLOWS_OUT/forensics/maestro/Login-3-tapOn.png" ]
}

@test "still exits 0 when there is no maestro/ directory at all" {
  run bash "$REPO_ROOT/scripts/e2e/collect-forensics.sh" ios
  [ "$status" -eq 0 ]
  [ ! -e "$WORKFLOWS_OUT/forensics/maestro" ]
}

@test "always exits 0, even for an unknown platform" {
  run bash "$REPO_ROOT/scripts/e2e/collect-forensics.sh" solaris
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown platform"* ]] || fail "assertion failed; output: $output"
}
