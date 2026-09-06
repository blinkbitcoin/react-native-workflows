#!/usr/bin/env bats
load test_helper

setup() {
  consumer="$BATS_TEST_TMPDIR/consumer"
  mkdir -p "$consumer"
  cat > "$consumer/package.json" <<'EOF'
{
  "name": "fixture-consumer",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "test:e2e:web": "printf 'PLAYWRIGHT_SKIP_EXPORT=%s\\n' \"$PLAYWRIGHT_SKIP_EXPORT\""
  }
}
EOF
  export GITHUB_WORKSPACE="$consumer"
}

@test "runs the consumer's e2e script with PLAYWRIGHT_SKIP_EXPORT set" {
  E2E_SCRIPT='test:e2e:web' \
    run bash "$REPO_ROOT/scripts/web/playwright.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLAYWRIGHT_SKIP_EXPORT=1"* ]]
}

@test "honours a caller-provided PLAYWRIGHT_SKIP_EXPORT value" {
  E2E_SCRIPT='test:e2e:web' PLAYWRIGHT_SKIP_EXPORT=0 \
    run bash "$REPO_ROOT/scripts/web/playwright.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PLAYWRIGHT_SKIP_EXPORT=0"* ]]
}

@test "dies when E2E_SCRIPT is not set" {
  run bash "$REPO_ROOT/scripts/web/playwright.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"E2E_SCRIPT not set"* ]]
}
