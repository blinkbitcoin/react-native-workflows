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
    "build:web": "mkdir -p dist && printf '<html>%s</html>' \"$EXPO_PUBLIC_BASE_URL$1\" > dist/index.html"
  }
}
EOF
  export GITHUB_WORKSPACE="$consumer"
}

@test "exports the web build and asserts index.html landed" {
  EXPORT_SCRIPT='build:web' OUTPUT_DIR=dist \
    run bash "$REPO_ROOT/scripts/web/export.sh"
  [ "$status" -eq 0 ]
  [ -f "$consumer/dist/index.html" ]
}

@test "passes EXPORT_ARGS through word-split to the export script" {
  EXPORT_SCRIPT='build:web' OUTPUT_DIR=dist EXPORT_ARGS='--dev' \
    run bash "$REPO_ROOT/scripts/web/export.sh"
  [ "$status" -eq 0 ]
  [ -f "$consumer/dist/index.html" ]
}

@test "dies when the export script does not produce index.html" {
  cat > "$consumer/package.json" <<'EOF'
{
  "name": "fixture-consumer",
  "version": "0.0.0",
  "private": true,
  "scripts": {
    "build:web": "mkdir -p dist"
  }
}
EOF
  EXPORT_SCRIPT='build:web' OUTPUT_DIR=dist \
    run bash "$REPO_ROOT/scripts/web/export.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"* ]]
  [[ "$output" == *"dist/index.html"* ]]
}

@test "dies when EXPORT_SCRIPT is not set" {
  run bash "$REPO_ROOT/scripts/web/export.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"EXPORT_SCRIPT not set"* ]]
}
