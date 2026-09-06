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
    #
    # YAML comments are stripped first: the workflows explain this very pitfall
    # in prose, and matching that prose is a false positive. It *was* one - and
    # invisible, because a bare `! cmd` is exempt from errexit too, so this
    # assertion could not fail anything until it was given a `|| fail`.
    ! grep -vE '^[[:space:]]*#' "$w" | grep -qE "&&[[:space:]]*''[[:space:]]*\|\|" \
      || fail "$(basename "$w") puts an empty string in the && slot of the ternary idiom"
  done
}

lane_step_count() {
  yq -r '[.jobs[].steps[]? | select((.run? // "") | test("release/fastlane.sh"))] | length' "$1"
}

@test "every step that runs fastlane.sh receives the five Fastfile contract variables" {
  # The consumer's Fastfile runs require_env! over these in before_all, for
  # every lane on both platforms, and rejects values that are empty after
  # strip - so the iOS build must still pass ANDROID_PACKAGE, and vice versa.
  for w in "${WORKFLOWS[@]}"; do
    job_names=$(yq -r '.jobs | keys | .[]' "$w")
    for j in $job_names; do
      n=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run? // \"\") | test(\"release/fastlane.sh\"))] | length" "$w")
      if [ "$n" -gt 0 ]; then
        job_env=$(yq -r "(.jobs.\"$j\".env // {}) | keys | .[]" "$w")
        i=0
        while [ "$i" -lt "$n" ]; do
          step_env=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run? // \"\") | test(\"release/fastlane.sh\"))][$i] | (.env // {}) | keys | .[]" "$w")
          for v in APP_VERSION APP_BUILD_NUMBER IOS_BUNDLE_ID IOS_SCHEME ANDROID_PACKAGE; do
            printf '%s\n%s\n' "$job_env" "$step_env" | grep -qxF "$v" \
              || fail "$(basename "$w"): job '$j' fastlane step #$i receives neither a job-level nor a step-level $v"
          done
          i=$((i + 1))
        done
      fi
    done
  done
}

@test "every credential secret a lane workflow declares reaches EVERY fastlane step's env" {
  # This is exactly what C1 was: ASC_KEY_P8_BASE64 was decoded to a 0600 file
  # but never put in the lane's environment, and the lane reads the base64
  # itself with ENV.fetch - so every store lane would have raised KeyError.
  #
  # Per step, not per workflow: a union across all fastlane steps would pass
  # when the secret is on `verify` but missing from `build`, which is the same
  # bug made half as often. If a secret ever legitimately belongs to only one
  # step, add it to an explicit allowlist here rather than flattening again.
  for w in "${WORKFLOWS[@]}"; do
    job_names=$(yq -r '.jobs | keys | .[]' "$w")
    for j in $job_names; do
      n=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run? // \"\") | test(\"release/fastlane.sh\"))] | length" "$w")
      if [ "$n" -gt 0 ]; then
        declared=$(yq -r '(.on.workflow_call.secrets // {}) | keys | .[]' "$w")
        job_env=$(yq -r "(.jobs.\"$j\".env // {}) | keys | .[]" "$w")
        i=0
        while [ "$i" -lt "$n" ]; do
          step_name=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run? // \"\") | test(\"release/fastlane.sh\"))][$i].name // \"step $i\"" "$w")
          step_env=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run? // \"\") | test(\"release/fastlane.sh\"))][$i] | (.env // {}) | keys | .[]" "$w")
          for s in $declared; do
            case "$s" in
              consumer-token) continue ;;
            esac
            printf '%s\n%s\n' "$job_env" "$step_env" | grep -qxF "$s" \
              || fail "$(basename "$w"): secret $s is declared but never reaches the [$step_name] step env"
          done
          i=$((i + 1))
        done
      fi
    done
  done
}

# Named explicitly, not just covered by the generic per-step rule above: these
# seven are the only lane inputs that are secrets *because of what they are*
# rather than because they authenticate anything, so it is easy to "simplify"
# them into env-json - which is printed to the log.
@test "fastlane-lane declares the App Review contact and demo-account secrets" {
  f="$REPO_ROOT/.github/workflows/fastlane-lane.yml"
  declared=$(yq -r '.on.workflow_call.secrets | keys | .[]' "$f")
  for s in APP_REVIEW_CONTACT_EMAIL APP_REVIEW_CONTACT_FIRST_NAME \
    APP_REVIEW_CONTACT_LAST_NAME APP_REVIEW_CONTACT_PHONE \
    APP_REVIEW_DEMO_USER APP_REVIEW_DEMO_PASSWORD APP_REVIEW_NOTES; do
    grep -qxF "$s" <<<"$declared" || fail "fastlane-lane.yml does not declare the secret $s"
  done
}

# Callers have no other way to get a non-secret value (OTA_ENABLED,
# EXPO_UPDATES_URL, EXPO_PUBLIC_*, ANDROID_UPLOAD_CERT_SHA256, ...) into
# prebuild, the lanes or the notes generator, so every workflow that runs one of
# those must accept build-env.
@test "every workflow that runs prebuild, a lane or the notes generator accepts build-env" {
  for w in expo-prepare expo-build-ios expo-build-android fastlane-lane; do
    f="$REPO_ROOT/.github/workflows/$w.yml"
    have=$(yq -r '.on.workflow_call.inputs | has("build-env")' "$f")
    [ "$have" = "true" ] || fail "$w.yml does not declare a build-env input"
    default=$(yq -r '.on.workflow_call.inputs."build-env".default' "$f")
    [ "$default" = "{}" ] || fail "$w.yml's build-env default is '$default', expected {}"
    steps=$(yq -r '[.jobs[].steps[]? | select((.run? // "") | test("release/build-env.sh"))] | length' "$f")
    [ "$steps" -ge 1 ] || fail "$w.yml declares build-env but never publishes it"
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
  [[ "$ios" == *"github.event_name"* ]] || fail "ios toggle does not branch on github.event_name: $ios"
  [[ "$android" == *"github.event_name"* ]] || fail "android toggle does not branch on github.event_name: $android"
  [[ "$ios" != *"inputs.ios == true"* ]] || fail "ios toggle is a bare inputs comparison again: $ios"
  [[ "$android" != *"inputs.android != false"* ]] || fail "android toggle is a bare inputs comparison again: $android"
}

@test "self-release's major-tag job compares release_created to the string 'true'" {
  f="$REPO_ROOT/.github/workflows/self-release.yml"
  cond=$(yq -r '.jobs."major-tag".if' "$f")
  # Job outputs are strings; the literal "false" is truthy in a bare expression.
  [[ "$cond" == *"release_created == 'true'"* ]] || fail "major-tag if does not compare to the string true: $cond"
}
