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
  for w in checks unit e2e web pr-closed pr-title codeql \
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

# The single-source rule has exactly one line of code behind it: the BASE_SHA
# expression. Reverting it to a bare `github.event.pull_request.base.sha` leaves
# the classifier blind on a push, which is the defect this family fixed - and
# the caller's `paths-ignore`, which used to mask it, has been removed on
# purpose, so the regression would now be silent AND unmasked.
@test "checks.yml classifies pushes too: BASE_SHA names both base.sha and event.before" {
  command -v yq >/dev/null || skip "yq not installed"
  expr=$(yq -r '.jobs.changes.steps[] | select(.id == "classify") | .env.BASE_SHA // ""' \
    "$REPO_ROOT/.github/workflows/checks.yml")
  [ -n "$expr" ] || fail "no BASE_SHA env on checks.yml's classify step"
  grep -qF 'github.event.pull_request.base.sha' <<<"$expr" \
    || fail "BASE_SHA must use the PR base on a pull_request: $expr"
  grep -qF 'github.event.before' <<<"$expr" \
    || fail "BASE_SHA must fall back to github.event.before so a push is classified too: $expr"
  # The fallback has to be reached by branching on the event, not by relying on
  # base.sha being empty - relying on that is exactly what the pre-fix
  # expression did, and it classified nothing on a push.
  grep -qF "github.event_name == 'pull_request'" <<<"$expr" \
    || fail "BASE_SHA must branch on github.event_name: $expr"
}

# codeql.yml asks the same question checks.yml does, and "the same" has to mean
# character-for-character: two spellings of the base sha are two rules, and the
# second one drifts. Comparing the two expressions is cheaper than restating the
# right answer twice.
@test "codeql.yml's BASE_SHA expression is byte-identical to checks.yml's" {
  command -v yq >/dev/null || skip "yq not installed"
  read_base_sha() {
    yq -r '.jobs.changes.steps[] | select(.id == "classify") | .env.BASE_SHA // ""' \
      "$REPO_ROOT/.github/workflows/$1.yml"
  }
  checks=$(read_base_sha checks)
  codeql=$(read_base_sha codeql)
  [ -n "$codeql" ] || fail "no BASE_SHA env on codeql.yml's classify step"
  [ "$codeql" = "$checks" ] \
    || fail "codeql.yml classifies with '$codeql' but checks.yml uses '$checks'"
}

# The whole point of the changes job: a docs-only change analyses nothing, and
# a scheduled run (no base at all) analyses everything.
@test "codeql.yml's analyze job is gated on the classifier" {
  command -v yq >/dev/null || skip "yq not installed"
  f="$REPO_ROOT/.github/workflows/codeql.yml"
  cond=$(yq -r '.jobs.analyze.if' "$f")
  [[ "$cond" == *"needs.changes.outputs.docs-only != 'true'"* ]] \
    || fail "analyze's if does not gate on the classifier: $cond"
  needs=$(yq -r '.jobs.analyze.needs | join(",")' "$f")
  [ "$needs" = "changes" ] || fail "analyze needs '$needs', expected changes"
}

# The escalation is on the analyze job alone, and naming `permissions:` resets
# the unnamed scopes to none - so dropping contents: read would break the
# checkout rather than the upload. All three are asserted, and nothing more.
@test "codeql.yml escalates permissions only on the analyze job" {
  command -v yq >/dev/null || skip "yq not installed"
  f="$REPO_ROOT/.github/workflows/codeql.yml"
  [ "$(yq -r '.jobs.analyze.permissions.contents' "$f")" = "read" ] \
    || fail "analyze does not re-declare contents: read"
  [ "$(yq -r '.jobs.analyze.permissions.actions' "$f")" = "read" ] \
    || fail "analyze does not declare actions: read"
  [ "$(yq -r '.jobs.analyze.permissions."security-events"' "$f")" = "write" ] \
    || fail "analyze does not declare security-events: write"
  [ "$(yq -r '.jobs.analyze.permissions | keys | length' "$f")" -eq 3 ] \
    || fail "analyze asks for more than three scopes: $(yq -r '.jobs.analyze.permissions' "$f")"
  [ "$(yq -r '.jobs.changes | has("permissions")' "$f")" = "false" ] \
    || fail "the changes job escalates permissions; only analyze may"
}

# The head half of the same range. changed-class.bats covers what the script
# does when either end is absent from the consumer's checkout.
@test "checks.yml's classify step passes both ends of the range to the script" {
  command -v yq >/dev/null || skip "yq not installed"
  run yq -r '.jobs.changes.steps[] | select(.id == "classify") | .run' \
    "$REPO_ROOT/.github/workflows/checks.yml"
  [ "$status" -eq 0 ]
  grep -qF '"$BASE_SHA" "$HEAD_SHA"' <<<"$output" \
    || fail "classify must call changed-class.sh with BASE_SHA and HEAD_SHA: $output"
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

# The App Review contact and demo-account names are a cross-repo contract: the
# consumer's Fastfile reads them straight out of ENV, so a rename on either side
# silently stops populating the App Store review form - deliver and pilot simply
# receive fewer keys, with no error. The names are therefore not hard-coded here
# but read out of a committed copy of the template's shared.rb, and the two sets
# are compared in both directions.
#
# They are secrets rather than build-env/env-json values because a reviewer demo
# login is a real credential and both of those inputs are printed to the log.
TEMPLATE_LANES="$FIXTURES/consumer-min/fastlane/lanes/shared.rb"

@test "fastlane-lane's App Review secrets are exactly the names the template's lanes read" {
  [ -f "$TEMPLATE_LANES" ] || fail "no template lanes fixture at $TEMPLATE_LANES"
  wanted="$(grep -oE "ENV\['APP_REVIEW_[A-Z0-9_]*'\]" "$TEMPLATE_LANES" |
    sed "s/ENV\['//; s/'\]//" | sort -u)"
  [ "$(grep -c . <<<"$wanted")" -ge 7 ] \
    || fail "read only '$wanted' from $TEMPLATE_LANES - has the fixture changed shape?"
  declared="$(yq -r '.on.workflow_call.secrets | keys | .[]' "$REPO_ROOT/.github/workflows/fastlane-lane.yml" |
    grep '^APP_REVIEW_' | sort -u)"
  while read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" <<<"$declared" \
      || fail "the template's lanes read $name but fastlane-lane.yml does not declare it"
  done <<<"$wanted"
  while read -r name; do
    [ -n "$name" ] || continue
    grep -qxF "$name" <<<"$wanted" \
      || fail "fastlane-lane.yml declares $name but no lane in the template reads it"
  done <<<"$declared"
}

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

# A store listing is keyed on the full metadata locale name (en-US, de-DE,
# pt-BR); a bare language code matches no listing, so the default cannot be
# `en` however natural that reads.
@test "expo-prepare's notes-locales default is a store metadata locale" {
  f="$REPO_ROOT/.github/workflows/expo-prepare.yml"
  got=$(yq -r '.on.workflow_call.inputs."notes-locales".default' "$f")
  [ "$got" = "en-US" ] || fail "notes-locales defaults to '$got', expected en-US"
  grep -q '| `notes-locales` | `en-US` |' "$REPO_ROOT/docs/consumer-guide.md" \
    || fail "the consumer guide still documents a different notes-locales default"
}

# The digest step writes an enriched build-info.json into $RNW_OUTPUT_DIR; the
# in-job verify has to read *that* one, or artifacts.apkSha256 is never there
# and the lane's apk-sha check silently skips.
@test "expo-build-android's verify reads the build-info carrying the digests" {
  f="$REPO_ROOT/.github/workflows/expo-build-android.yml"
  got=$(yq -r '[.jobs[].steps[] | select(.name == "Fastlane android verify")][0].env.BUILD_INFO_FILE' "$f")
  [ "$got" = '${{ env.RNW_OUTPUT_DIR }}/build-info.json' ] \
    || fail "the android verify step reads BUILD_INFO_FILE '$got'"
  n=$(yq -r '[.jobs[].steps[]? | select((.run? // "") | test("release/artifact-hashes.sh"))] | length' "$f")
  [ "$n" -eq 1 ] || fail "expo-build-android does not run artifact-hashes.sh exactly once"
}

# $RNW is published by the setup composite action. A job that never runs setup
# expands `$RNW/scripts/…` to `/scripts/…` and exits 127 on every call - a
# workflow that cannot work at all, and one no unit test would ever reach.
@test "no run: step uses \$RNW in a job that never runs the setup action" {
  for w in "${WORKFLOWS[@]}"; do
    while read -r j; do
      [ -n "$j" ] || continue
      # This family's own composite action specifically - not actions/setup-node
      # or gradle/actions/setup-gradle, neither of which publishes $RNW.
      setup=$(yq -r "[.jobs.\"$j\".steps[]? | select((.uses // \"\") | test(\"rnw/.github/actions/setup\"))] | length" "$w")
      [ "$setup" -eq 0 ] || continue
      bad=$(yq -r "[.jobs.\"$j\".steps[]? | select((.run // \"\") | test(\"RNW/\")) | .name] | join(\", \")" "$w")
      [ -z "$bad" ] || fail "$(basename "$w") job '$j' never runs the setup action but uses \$RNW in: $bad"
    done <<<"$(yq -r '.jobs | keys | .[]' "$w")"
  done
}

# `merge-multiple: true` has no defined order, so two artifacts carrying
# `build-info.json` would make the release's record a coin toss. The per-platform
# record therefore ships under its own name and github-release folds it in
# explicitly, after both downloads and before the upload.
@test "the release's build-info precedence is explicit, not a merge-multiple race" {
  a="$REPO_ROOT/.github/workflows/expo-build-android.yml"
  paths=$(yq -r '[.jobs[].steps[]? | select(.uses? // "" | test("upload-artifact")) | .with.path] | join("\n")' "$a")
  not_contains "$paths" "/build-info.json" \
    || fail "expo-build-android uploads a bare build-info.json, which can collide: $paths"
  contains "$paths" "/build-info.android.json" \
    || fail "expo-build-android never uploads its per-platform build-info: $paths"
  g="$REPO_ROOT/.github/workflows/github-release.yml"
  names=$(yq -r '.jobs.release.steps[].name' "$g")
  # `yq` here is the Go implementation, whose jq subset has no index(); the step
  # order is read out of the numbered list instead.
  step_index() { printf '%s\n' "$names" | grep -nxF "$1" | head -1 | cut -d: -f1; }
  merge_i=$(step_index "Merge platform build-info")
  notes_i=$(step_index "Download notes")
  assets_i=$(step_index "Download assets")
  upload_i=$(step_index "Release assets")
  [ -n "$merge_i" ] || fail "github-release never merges the platform build-info: $names"
  [ "$notes_i" -lt "$assets_i" ] || fail "github-release stages assets before notes: $names"
  [ "$assets_i" -lt "$merge_i" ] || fail "the merge runs before the assets are staged: $names"
  [ "$merge_i" -lt "$upload_i" ] || fail "the merge runs after the upload: $names"
}

# fastlane-lane builds nothing: the binaries its lanes upload were downloaded
# into $RNW_ASSETS_DIR. The lanes read $RNW_OUTPUT_DIR, so the two have to be
# the same directory here - and only here; the build workflows keep
# RNW_OUTPUT_DIR as the directory the lane *writes* to.
@test "fastlane-lane points RNW_OUTPUT_DIR at the downloaded artifacts" {
  f="$REPO_ROOT/.github/workflows/fastlane-lane.yml"
  got=$(yq -r '[.jobs.lane.steps[] | select(.name == "Fastlane lane")][0].env.RNW_OUTPUT_DIR' "$f")
  [ "$got" = '${{ env.RNW_ASSETS_DIR }}' ] \
    || fail "fastlane-lane's lane step sets RNW_OUTPUT_DIR to '$got'"
  for w in expo-build-ios expo-build-android; do
    b="$REPO_ROOT/.github/workflows/$w.yml"
    n=$(yq -r '[.jobs[].steps[]? | select((.env.RNW_OUTPUT_DIR? // "") != "")] | length' "$b")
    [ "$n" -eq 0 ] || fail "$w.yml overrides RNW_OUTPUT_DIR, which is where its lane writes"
  done
}

# Job-level `permissions:` cannot be conditional, so expo-prepare asks for
# `actions: read` on every call and every caller has to grant it. Both scopes
# are asserted here because naming `permissions:` at all resets the unnamed
# ones to none: dropping `contents: read` would break the checkout instead.
@test "expo-prepare's job permissions are static contents+actions read" {
  f="$REPO_ROOT/.github/workflows/expo-prepare.yml"
  [ "$(yq -r '.jobs.prepare.permissions.contents' "$f")" = "read" ] \
    || fail "expo-prepare's prepare job does not declare contents: read"
  [ "$(yq -r '.jobs.prepare.permissions.actions' "$f")" = "read" ] \
    || fail "expo-prepare's prepare job does not declare actions: read"
  [ "$(yq -r '.jobs.prepare.permissions | keys | length' "$f")" -eq 2 ] \
    || fail "expo-prepare's prepare job asks for more than contents+actions: $(yq -r '.jobs.prepare.permissions' "$f")"
  # The consumer guide is where a caller learns it has to grant this.
  grep -q 'Every caller of `expo-prepare.yml` must grant `actions: read`' "$REPO_ROOT/docs/consumer-guide.md" \
    || fail "the consumer guide does not tell callers to grant actions: read"
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

# A job-level cap is a bound, not a diagnosis: when the 60-minute `android` job
# dies there is nothing in the log saying *which* of its steps hung. These are
# the steps that can hang on something outside our control (a CDN, a pod
# resolve, an emulator boot), so each carries its own bound. The list is named
# rather than derived: renaming a step would otherwise silently drop its
# timeout and this test would still pass.
#
# Deliberately absent: the Maestro suite steps (theirs comes from
# `suite-timeout-minutes` via step-timeout.sh) and download-artifact (it
# retries internally, and a step timeout would cut a legitimate retry short).
@test "e2e.yml's hang-prone steps each carry a step-level timeout-minutes" {
  f="$REPO_ROOT/.github/workflows/e2e.yml"
  for spec in \
    "Pod install:20" \
    "Build iOS app:45" \
    "Install Maestro:10" \
    "Wait for Metro:10" \
    "Bake AVD snapshot:20" \
    "Install Android emulator package:15"; do
    name="${spec%:*}"
    want="${spec##*:}"
    found=$(yq -r "[.jobs[].steps[]? | select(.name == \"$name\")] | length" "$f")
    [ "$found" -gt 0 ] || fail "e2e.yml has no step named '$name' - was it renamed?"
    # Every occurrence: 'Install Maestro' and 'Wait for Metro' appear in both
    # the ios and the android job.
    bad=$(yq -r "[.jobs[].steps[]? | select(.name == \"$name\") | select(.\"timeout-minutes\" != $want)] | length" "$f")
    [ "$bad" -eq 0 ] || fail "$bad of the $found '$name' steps lack timeout-minutes: $want"
  done
}

# Forensics on a *green* run are what later turns "it passed that time" into a
# diagnosis, and they cost ~50-100 MB per platform per run at the default
# 7-day retention. The lever for that cost is `retention-days`, not `if:` - an
# edit to `failure()` "to save storage" is the regression this pins.
@test "every forensics step runs under always(), not failure()" {
  select='[.jobs[].steps[]? | select(((.uses // "") | test("actions/forensics$")) or ((.run // "") | test("collect-forensics.sh")))]'
  total=0
  for w in "${WORKFLOWS[@]}"; do
    found=$(yq -r "$select | length" "$w")
    total=$((total + found))
    bad=$(yq -r "$select | map(select(.if != \"always()\")) | length" "$w")
    [ "$bad" -eq 0 ] || fail "$(basename "$w") has $bad forensics step(s) that are not 'if: always()'"
  done
  # e2e.yml: collect + upload on iOS, upload on Android. web.yml: one upload.
  # Without this the selector could stop matching and the loop would pass by
  # examining nothing.
  [ "$total" -ge 4 ] || fail "the forensics selector matched only $total steps - has the action moved?"
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
