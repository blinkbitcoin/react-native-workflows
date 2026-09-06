#!/usr/bin/env bats
load test_helper

setup() {
  WORKFLOWS=()
  for f in "$REPO_ROOT"/.github/workflows/*.yml; do
    base="$(basename "$f")"
    case "$base" in
      self-*) continue ;;
    esac
    WORKFLOWS+=("$f")
  done
}

@test "at least two reusable workflows exist" {
  [ "${#WORKFLOWS[@]}" -ge 2 ]
}

@test "every workflow declares on.workflow_call" {
  for w in "${WORKFLOWS[@]}"; do
    has=$(yq -r 'has("on") and (.on | has("workflow_call"))' "$w")
    [ "$has" = "true" ]
  done
}

@test "every workflow has top-level permissions.contents == read" {
  for w in "${WORKFLOWS[@]}"; do
    perms=$(yq -r '.permissions.contents' "$w")
    [ "$perms" = "read" ]
  done
}

@test "no workflow sets a top-level concurrency" {
  for w in "${WORKFLOWS[@]}"; do
    has=$(yq -r 'has("concurrency")' "$w")
    [ "$has" = "false" ]
  done
}

@test "every job has timeout-minutes" {
  for w in "${WORKFLOWS[@]}"; do
    missing=$(yq -r '[.jobs[] | select(has("timeout-minutes") | not)] | length' "$w")
    [ "$missing" -eq 0 ]
  done
}

@test "every run: step is a single 'bash ...' line" {
  for w in "${WORKFLOWS[@]}"; do
    bad=$(yq -r '[.jobs[].steps[]? | select(has("run")) | .run | select(test("^bash ") | not)] | length' "$w")
    [ "$bad" -eq 0 ]
  done
}

@test "every job with a run: step checks out .rnw from the workflow's own repo/sha" {
  for w in "${WORKFLOWS[@]}"; do
    job_names=$(yq -r '.jobs | keys | .[]' "$w")
    for j in $job_names; do
      has_run=$(yq -r "[.jobs.\"$j\".steps[]? | select(has(\"run\"))] | length" "$w")
      if [ "$has_run" -gt 0 ]; then
        rnw_checkout=$(yq -r "[.jobs.\"$j\".steps[]? | select(.uses? == \"actions/checkout@v7\") | select(.with.path? == \".rnw\")] | length" "$w")
        [ "$rnw_checkout" -gt 0 ]
      fi
    done
  done
}
