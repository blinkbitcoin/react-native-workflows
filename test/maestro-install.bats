#!/usr/bin/env bats
load test_helper

# The regression these cover: maestro prints a first-run analytics notice
# before its version, so comparing the whole `--version` output against the
# pin failed on every fresh runner ("expected 2.10.0, got Anonymous analytics
# enabled...") while passing on any machine where maestro had run once.

setup() {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  export PATH="$fakebin:/usr/bin:/bin"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.maestro/bin"
  MAESTRO_PIN="$(bash -c 'source "$REPO_ROOT/scripts/lib/versions.sh"; echo "$MAESTRO_VERSION"')"
  # curl must never run: a test that reaches the network is not a unit test.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$fakebin/curl"
  chmod +x "$fakebin/curl"
}

# Plants a maestro whose --version prints $1.
plant_maestro() {
  printf '#!/usr/bin/env bash\ncat <<%s\n%s\n%s\n' 'EOF' "$1" 'EOF' > "$HOME/.maestro/bin/maestro"
  chmod +x "$HOME/.maestro/bin/maestro"
}

@test "a plain version string is accepted" {
  plant_maestro "2.10.0"
  run bash "$REPO_ROOT/scripts/ci/maestro-install.sh"
  [ "$status" -eq 0 ] || fail "expected success, got $status: $output"
}

@test "the analytics notice before the version does not break the check" {
  plant_maestro "Anonymous analytics enabled. To opt out, set MAESTRO_CLI_NO_ANALYTICS environment variable to any value before running Maestro.
2.10.0"
  run bash "$REPO_ROOT/scripts/ci/maestro-install.sh"
  [ "$status" -eq 0 ] || fail "the banner should not be read as the version: $output"
}

# A wrong version is not a mismatch error - it triggers a reinstall, and the
# mismatch message is only reached if that reinstall then produces the wrong
# version too. With curl stubbed to fail, the reinstall is what we observe.
@test "a genuinely wrong version is never accepted" {
  plant_maestro "2.9.0"
  run bash "$REPO_ROOT/scripts/ci/maestro-install.sh"
  [ "$status" -ne 0 ] || fail "2.9.0 must not pass as $MAESTRO_PIN: $output"
  [[ "$output" == *"install failed"* ]] || fail "expected the reinstall path: $output"
}

@test "a reinstall that lands the wrong version reports the mismatch" {
  # The install line pipes curl's stdout into bash, so this stub is an
  # "installer" that plants the wrong version - the case only the final check
  # can catch.
  cat > "$fakebin/curl" <<'STUB'
#!/usr/bin/env bash
echo 'mkdir -p "$HOME/.maestro/bin"'
echo 'printf "#!/usr/bin/env bash\necho 2.9.0\n" > "$HOME/.maestro/bin/maestro"'
echo 'chmod +x "$HOME/.maestro/bin/maestro"'
STUB
  chmod +x "$fakebin/curl"
  plant_maestro "2.9.0"
  run bash "$REPO_ROOT/scripts/ci/maestro-install.sh"
  [ "$status" -ne 0 ] || fail "expected failure: $output"
  [[ "$output" == *"version mismatch"* ]] || fail "expected a version mismatch message: $output"
}

@test "analytics are turned off rather than merely parsed around" {
  grep -q 'MAESTRO_CLI_NO_ANALYTICS=1' "$REPO_ROOT/scripts/ci/maestro-install.sh" ||
    fail "the script should opt out of telemetry, not just tolerate the notice"
}
