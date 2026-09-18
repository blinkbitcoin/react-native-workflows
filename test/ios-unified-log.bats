#!/usr/bin/env bats
# ios-simulator.sh `record start|stop` also streams the simulator's unified log
# next to the video. It exists because a deep link that reached the app ~40s
# late could only be *inferred* from Maestro screenshots; SpringBoard's alert
# lifecycle and FrontBoard's UIOpenURLAction hand-off are what actually
# explain it, and they live in this log.
load test_helper

setup() {
  export WORKFLOWS_OUT="$BATS_TEST_TMPDIR/out"
  export GITHUB_ENV="$BATS_TEST_TMPDIR/ghenv"
  : > "$GITHUB_ENV"
  mkdir -p "$WORKFLOWS_OUT"
  export WORKFLOWS_SIM_UDID=SIM-UDID
  export WORKFLOWS_APP_ID=com.example.app
  export EXPO_CONFIG_JSON="$BATS_TEST_TMPDIR/expo.json"
  printf '{"name":"App","scheme":"myapp","ios":{"bundleIdentifier":"com.example.app"}}\n' > "$EXPO_CONFIG_JSON"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  CALLS="$BATS_TEST_TMPDIR/calls"
  export CALLS
  : > "$CALLS"
  # xcrun stub: records its arguments and, for the two long-running commands,
  # sleeps so the script has a real pid to signal.
  cat > "$bin/xcrun" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
case "\$*" in *recordVideo*|*"log stream"*) exec sleep 30 ;; esac
STUB
  chmod +x "$bin/xcrun"
  PATH="$bin:$PATH"
  export PATH
}

sim() { bash "$REPO_ROOT/scripts/e2e/ios-simulator.sh" "$@"; }

@test "record start streams the unified log beside the video, with its own pid file" {
  run sim record start
  [ "$status" -eq 0 ] || fail "status $status; output: $output"
  # Both xcrun calls are backgrounded, so the stub may not have logged its
  # arguments by the time the script returns: give it a moment.
  for _ in $(seq 1 50); do [ "$(grep -c . "$CALLS")" -ge 2 ] && break; sleep 0.1; done
  grep -q "recordVideo" "$CALLS" || fail "no recordVideo call: $(cat "$CALLS")"
  grep -q "spawn SIM-UDID log stream" "$CALLS" || fail "no log stream call: $(cat "$CALLS")"
  [ -f "$WORKFLOWS_OUT/ios-record.pid" ] || fail "no recording pid file"
  [ -f "$WORKFLOWS_OUT/ios-unified-log.pid" ] || fail "no unified-log pid file"
  kill "$(cat "$WORKFLOWS_OUT/ios-record.pid")" "$(cat "$WORKFLOWS_OUT/ios-unified-log.pid")" 2>/dev/null || true
}

@test "record stop ends both and removes both pid files" {
  sim record start >/dev/null
  rec="$(cat "$WORKFLOWS_OUT/ios-record.pid")"
  logp="$(cat "$WORKFLOWS_OUT/ios-unified-log.pid")"
  run sim record stop
  [ "$status" -eq 0 ] || fail "status $status; output: $output"
  contains "$output" "unified log stopped" || fail "output: $output"
  [ ! -f "$WORKFLOWS_OUT/ios-record.pid" ] || fail "recording pid file survived"
  [ ! -f "$WORKFLOWS_OUT/ios-unified-log.pid" ] || fail "unified-log pid file survived"
  sleep 1
  ! kill -0 "$rec" 2>/dev/null || fail "recording (pid $rec) still running"
  ! kill -0 "$logp" 2>/dev/null || fail "log stream (pid $logp) still running"
}

@test "the predicate names the app id and scheme and the SpringBoard alert categories" {
  run bash -c "source '$REPO_ROOT/scripts/lib/common.sh'; source '$REPO_ROOT/scripts/lib/e2e-env.sh'; workflows_ios_unified_log_predicate"
  [ "$status" -eq 0 ] || fail "status $status; output: $output"
  contains "$output" 'eventMessage CONTAINS "com.example.app"' || fail "no app id: $output"
  contains "$output" 'eventMessage CONTAINS "myapp://"' || fail "no scheme: $output"
  contains "$output" 'category == "AlertItems"' || fail "no alert category: $output"
  contains "$output" 'category == "SceneClient"' || fail "no scene-action category: $output"
}

# A stop with no recording in progress must stay a no-op, log stream included.
@test "record stop without a start is a no-op" {
  run sim record stop
  [ "$status" -eq 0 ] || fail "status $status; output: $output"
  contains "$output" "no recording in progress" || fail "output: $output"
}
