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

# Named explicitly rather than left to the glob: a workflow accidentally
# deleted or renamed would otherwise just shrink WORKFLOWS and every other
# assertion here would still pass.
@test "every reusable workflow this family publishes is present" {
  for w in checks unit e2e web pr-closed pr-title \
    expo-prepare expo-build-ios expo-build-android \
    fastlane-lane github-release expo-ota-publish; do
    [ -f "$REPO_ROOT/.github/workflows/$w.yml" ] || {
      echo "missing .github/workflows/$w.yml" >&2
      return 1
    }
  done
}

@test "every declared secret is optional (required: false)" {
  for w in "${WORKFLOWS[@]}"; do
    # A required secret in a reusable workflow makes every caller declare it,
    # even the ones that never reach the job needing it.
    bad=$(yq -r '[(.on.workflow_call.secrets // {}) | to_entries[] | select(.value.required != false)] | length' "$w")
    [ "$bad" -eq 0 ]
  done
}

@test "no workflow puts an empty string in the AND slot of the ternary idiom" {
  for w in "${WORKFLOWS[@]}"; do
    # GitHub's && yields its first falsy operand, so `cond && '' || X` is X on
    # both branches. The non-empty value must sit in the && slot.
    ! grep -qE "&&[[:space:]]*''[[:space:]]*\|\|" "$w"
  done
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

@test "every android-emulator-runner script: is a single 'bash ...' line" {
  for w in "${WORKFLOWS[@]}"; do
    bad=$(yq -r '[.jobs[].steps[]? | select((.uses? // "") | test("android-emulator-runner")) | (.with.script // "") | select((test("^bash ") | not) or ((split("\n") | length) > 1))] | length' "$w")
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

@test "the .rnw checkout uses job.workflow_repository and job.workflow_sha (not github.* or any other form) and sets persist-credentials: false" {
  for w in "${WORKFLOWS[@]}"; do
    job_names=$(yq -r '.jobs | keys | .[]' "$w")
    for j in $job_names; do
      rnw_step_count=$(yq -r "[.jobs.\"$j\".steps[]? | select(.uses? == \"actions/checkout@v7\") | select(.with.path? == \".rnw\")] | length" "$w")
      if [ "$rnw_step_count" -gt 0 ]; then
        repo=$(yq -r "[.jobs.\"$j\".steps[]? | select(.uses? == \"actions/checkout@v7\") | select(.with.path? == \".rnw\")][0].with.repository" "$w")
        ref=$(yq -r "[.jobs.\"$j\".steps[]? | select(.uses? == \"actions/checkout@v7\") | select(.with.path? == \".rnw\")][0].with.ref" "$w")
        # persist-credentials: false is what keeps this repo's checkout token out
        # of the consumer workspace; it is as load-bearing as the ref pinning.
        persist=$(yq -r "[.jobs.\"$j\".steps[]? | select(.uses? == \"actions/checkout@v7\") | select(.with.path? == \".rnw\")][0].with.\"persist-credentials\"" "$w")
        [ "$repo" = '${{ job.workflow_repository }}' ]
        [ "$ref" = '${{ job.workflow_sha }}' ]
        [ "$persist" = "false" ]
      fi
    done
  done
}

# The self-* workflows are excluded from WORKFLOWS above (they are not reusable),
# but two of their expressions are subtle enough to deserve pinning down.

@test "self-smoke's e2e toggles branch on github.event_name so the schedule run is not a no-op" {
  f="$REPO_ROOT/.github/workflows/self-smoke.yml"
  ios=$(yq -r '.jobs.e2e.with.ios' "$f")
  android=$(yq -r '.jobs.e2e.with.android' "$f")
  # `inputs` is null on a schedule trigger, so a bare inputs.* comparison
  # evaluates false for both platforms and the weekly smoke runs no E2E at all.
  [[ "$ios" == *"github.event_name"* ]]
  [[ "$android" == *"github.event_name"* ]]
  [[ "$ios" != *"inputs.ios == true"* ]]
  [[ "$android" != *"inputs.android != false"* ]]
}

@test "self-release's major-tag job compares release_created to the string 'true'" {
  f="$REPO_ROOT/.github/workflows/self-release.yml"
  cond=$(yq -r '.jobs."major-tag".if' "$f")
  # Job outputs are strings; the literal "false" is truthy in a bare expression.
  [[ "$cond" == *"release_created == 'true'"* ]]
}
