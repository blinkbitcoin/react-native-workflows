#!/usr/bin/env bats
load test_helper

setup() {
  EXPO_CONFIG_JSON="$FIXTURES/expo-config.json"
  export EXPO_CONFIG_JSON
}

@test "extracts name" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" name
  [ "$status" -eq 0 ]
  [ "$output" = "RN Mobile Template (dev)" ]
}

@test "extracts slug" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" slug
  [ "$status" -eq 0 ]
  [ "$output" = "react-native-mobile-template" ]
}

@test "extracts scheme" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" scheme
  [ "$status" -eq 0 ]
  [ "$output" = "rnmt" ]
}

@test "extracts ios.bundleIdentifier" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" ios.bundleIdentifier
  [ "$status" -eq 0 ]
  [ "$output" = "com.example.rnmt.dev" ]
}

@test "extracts android.package" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" android.package
  [ "$status" -eq 0 ]
  [ "$output" = "com.example.rnmt.dev" ]
}

@test "derives ios.scheme-name by stripping non-alphanumerics from name" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" ios.scheme-name
  [ "$status" -eq 0 ]
  [ "$output" = "RNMobileTemplatedev" ]
}

@test "unknown key exits 1 with an ::error annotation" {
  run bash "$REPO_ROOT/scripts/lib/expo-config.sh" nonexistent.key
  [ "$status" -eq 1 ]
  [[ "$output" == *"::error::"* ]] || fail "assertion failed; output: $output"
}
