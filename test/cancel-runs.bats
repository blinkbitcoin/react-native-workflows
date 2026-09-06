#!/usr/bin/env bats
load test_helper

# A fake `gh` double: `gh api --paginate 'repos/.../runs?...status=queued...' --jq ...`
# returns two runs, one of which the fake refuses to cancel (already finished);
# `status=in_progress` returns none. Verifies: (1) a single failed cancel does
# not abort the script under `set -e`, (2) a final count is printed.
setup() {
  fakebin="$BATS_TEST_TMPDIR/fakebin"
  mkdir -p "$fakebin"
  cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "api" ] && [ "$2" = "--paginate" ]; then
  case "$3" in
    *status=queued*) printf '111 build\n222 test\n' ;;
    *status=in_progress*) ;;
  esac
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "-X" ] && [ "$3" = "POST" ]; then
  case "$4" in
    *runs/111/cancel) exit 0 ;;
    *runs/222/cancel) exit 1 ;;
  esac
fi
echo "unexpected gh invocation: $*" >&2
exit 2
EOF
  chmod +x "$fakebin/gh"
  export PATH="$fakebin:$PATH"
  export GH_TOKEN=fake REPO=org/repo HEAD_SHA=deadbeef GITHUB_RUN_ID=999
}

@test "a single cancel failure doesn't abort the run, and a final count is printed" {
  run bash "$REPO_ROOT/scripts/ci/cancel-runs.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelling run 111"* ]] || fail "assertion failed; output: $output"
  [[ "$output" == *"cancelling run 222"* ]] || fail "assertion failed; output: $output"
  [[ "$output" == *"could not cancel run 222"* ]] || fail "assertion failed; output: $output"
  [[ "$output" == *"cancelled 1 run(s)"* ]] || fail "assertion failed; output: $output"
}
