#!/usr/bin/env bats
load test_helper

setup() {
  consumer="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$consumer/node_modules/.bin"
  cat > "$consumer/package.json" <<'EOF'
{
  "name": "fixture-consumer",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "typecheck": "touch typecheck.marker"
  }
}
EOF
  cat > "$consumer/node_modules/.bin/knipfake" <<'EOF'
#!/usr/bin/env bash
touch knipfake.marker
EOF
  chmod +x "$consumer/node_modules/.bin/knipfake"
  export GITHUB_WORKSPACE="$consumer"
}

@test "runs an existing package.json script via pnpm run" {
  run bash "$REPO_ROOT/scripts/checks/run-script.sh" typecheck
  [ "$status" -eq 0 ]
  [ -f "$consumer/typecheck.marker" ]
}

@test "falls back to node_modules/.bin via pnpm exec when no matching script exists" {
  run bash "$REPO_ROOT/scripts/checks/run-script.sh" knipfake
  [ "$status" -eq 0 ]
  [ -f "$consumer/knipfake.marker" ]
}

@test "missing script and no binary dies with an ::error:: annotation" {
  run bash "$REPO_ROOT/scripts/checks/run-script.sh" nonexistent-thing
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"nonexistent-thing"* ]]
}
