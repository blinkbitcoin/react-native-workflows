#!/usr/bin/env bats
load test_helper

setup() {
  ACTIONS=("$REPO_ROOT"/.github/actions/*/action.yml)
}

@test "at least the five composite actions exist" {
  count=0
  for a in "${ACTIONS[@]}"; do [ -f "$a" ] && count=$((count + 1)); done
  [ "$count" -ge 5 ]
}

@test "every action declares runs.using: composite" {
  for a in "${ACTIONS[@]}"; do
    using=$(yq -r '.runs.using' "$a")
    [ "$using" = "composite" ]
  done
}

@test "every step has a name" {
  for a in "${ACTIONS[@]}"; do
    missing=$(yq -r '[.runs.steps[] | select(has("name") | not)] | length' "$a")
    [ "$missing" -eq 0 ]
  done
}

@test "every run: step starts with 'bash '" {
  for a in "${ACTIONS[@]}"; do
    bad=$(yq -r '[.runs.steps[] | select(has("run")) | .run | select(test("^bash ") | not)] | length' "$a")
    [ "$bad" -eq 0 ]
  done
}

@test "every input has a description and a default" {
  for a in "${ACTIONS[@]}"; do
    bad=$(yq -r '[(.inputs // {}) | to_entries[] | select((.value.description // "") == "" or (.value | has("default") | not))] | length' "$a")
    [ "$bad" -eq 0 ]
  done
}
