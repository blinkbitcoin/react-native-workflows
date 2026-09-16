#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# The four OTA scripts in one file because they are one pipeline: baseline ->
# (gate, covered by fingerprint-gate.bats) -> export -> publish -> smoke, and
# the property that matters most spans two of them - what publish uploads has to
# be what export produced and the gate vetted.
load test_helper

setup() {
  STUB="$BATS_TEST_TMPDIR/bin"
  ROOT="$BATS_TEST_TMPDIR/app"
  mkdir -p "$STUB" "$ROOT"
  export WORKFLOWS_TEST_LOG="$BATS_TEST_TMPDIR/cmd.log"
  : > "$WORKFLOWS_TEST_LOG"
  export PATH="$STUB:$PATH"
  export GITHUB_WORKSPACE="$BATS_TEST_TMPDIR" WORKING_DIRECTORY=app
  export WORKFLOWS_OUT="$BATS_TEST_TMPDIR/out" RUNNER_TEMP="$BATS_TEST_TMPDIR/tmp"
  export WORKFLOWS_OTA_DIR="$BATS_TEST_TMPDIR/ota" WORKFLOWS_ASSETS_DIR="$BATS_TEST_TMPDIR/assets"
  mkdir -p "$RUNNER_TEMP"
  unset GITHUB_ENV OTA_ENABLED OTA_CLI_VERSION OTA_PUBLISH_TOKEN OTA_MANIFEST_URL \
    OTA_RUNTIME_VERSION OTA_SMOKE_PLATFORM
}

# --- baseline.sh ------------------------------------------------------------
# The baseline must come from a *release asset*: download-artifact can only see
# the current run, so a same-run artifact would compare the commit against
# itself and the gate would pass unconditionally.

stub_gh() {
  cat > "$STUB/gh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORKFLOWS_TEST_LOG"
prev=""; out=""
for a in "$@"; do [ "$prev" = "--output" ] && out="$a"; prev="$a"; done
[ -f "$WORKFLOWS_TEST_ASSET_MISSING" ] && exit 1
[ -n "$out" ] || exit 1
printf '%s' "$WORKFLOWS_TEST_ASSET_BODY" > "$out"
exit 0
SH
  chmod +x "$STUB/gh"
  export WORKFLOWS_TEST_ASSET_MISSING="$BATS_TEST_TMPDIR/asset-missing"
  export WORKFLOWS_TEST_ASSET_BODY='{"sha":"abc","fingerprint":{"ios":"fp"}}'
}

baseline() { run bash "$REPO_ROOT/scripts/ota/baseline.sh" "$@"; }

@test "baseline downloads build-info.json from the channel's release" {
  stub_gh
  baseline v1.2.3
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  grep -q '^release download v1.2.3 --pattern build-info.json' "$WORKFLOWS_TEST_LOG" \
    || fail "unexpected gh argv: $(cat "$WORKFLOWS_TEST_LOG")"
  [ -s "$WORKFLOWS_ASSETS_DIR/build-info.json" ] || fail "no baseline was written"
}

@test "baseline without a tag is fatal, and says which input is missing" {
  stub_gh
  baseline
  [ "$status" -ne 0 ] || fail "accepted an empty tag: $output"
  contains "$output" "baseline-tag" || fail "unexpected message: $output"
}

@test "a release with no build-info.json asset is fatal, never a silent pass" {
  stub_gh
  : > "$WORKFLOWS_TEST_ASSET_MISSING"
  baseline v1.2.3
  [ "$status" -ne 0 ] || fail "accepted a release with no baseline asset: $output"
  contains "$output" "could not download build-info.json" || fail "unexpected message: $output"
}

@test "an empty build-info.json asset is fatal" {
  stub_gh
  WORKFLOWS_TEST_ASSET_BODY='' baseline v1.2.3
  [ "$status" -ne 0 ] || fail "accepted an empty baseline: $output"
  contains "$output" "no fingerprint baseline" || fail "unexpected message: $output"
}

@test "a stale baseline from an earlier run is removed before the download" {
  stub_gh
  mkdir -p "$WORKFLOWS_ASSETS_DIR"
  printf 'stale\n' > "$WORKFLOWS_ASSETS_DIR/build-info.json"
  : > "$WORKFLOWS_TEST_ASSET_MISSING"
  baseline v1.2.3
  [ "$status" -ne 0 ] || fail "the stale file was accepted as a baseline: $output"
  [ ! -f "$WORKFLOWS_ASSETS_DIR/build-info.json" ] || fail "the stale baseline survived a failed download"
}

# --- export.sh --------------------------------------------------------------

stub_npx() {
  cat > "$STUB/npx" <<'SH'
#!/usr/bin/env bash
printf 'npx %s\n' "$*" >> "$WORKFLOWS_TEST_LOG"
printf 'EXPO_TOKEN=%s\n' "${EXPO_TOKEN-}" >> "$WORKFLOWS_TEST_LOG"
prev=""; out=""
for a in "$@"; do [ "$prev" = "--output-dir" ] && out="$a"; prev="$a"; done
if [ -n "$out" ] && [ "${WORKFLOWS_TEST_EXPORT_EMPTY:-}" != "true" ]; then
  mkdir -p "$out"
  printf '{}\n' > "$out/metadata.json"
  printf 'bundle\n' > "$out/index.js"
  [ "${WORKFLOWS_TEST_NO_METADATA:-}" = "true" ] && rm -f "$out/metadata.json"
fi
exit "${WORKFLOWS_TEST_NPX_STATUS:-0}"
SH
  chmod +x "$STUB/npx"
}

export_ota() { run bash "$REPO_ROOT/scripts/ota/export.sh"; }

@test "export writes source maps into WORKFLOWS_OTA_DIR" {
  stub_npx
  export_ota
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  argv="$(grep '^npx expo export' "$WORKFLOWS_TEST_LOG")"
  contains "$argv" "--source-maps" || fail "the source maps are not exported: $argv"
  contains "$argv" "--platform all" || fail "not both platforms: $argv"
  contains "$argv" "--output-dir $WORKFLOWS_OTA_DIR" || fail "wrong output dir: $argv"
  [ -f "$WORKFLOWS_OTA_DIR/metadata.json" ] || fail "no export landed"
}

@test "export clears a previous export rather than mixing two" {
  stub_npx
  mkdir -p "$WORKFLOWS_OTA_DIR"
  printf 'old\n' > "$WORKFLOWS_OTA_DIR/stale.js"
  export_ota
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -f "$WORKFLOWS_OTA_DIR/stale.js" ] || fail "a file from the previous export survived"
}

# `mkdir -p` above the export makes `[ -d ]` an assertion that cannot fail, so
# the content is what gets asserted.
@test "an export that produces nothing is fatal" {
  stub_npx
  WORKFLOWS_TEST_EXPORT_EMPTY=true export_ota
  [ "$status" -ne 0 ] || fail "accepted an empty export: $output"
  contains "$output" "produced no output" || fail "unexpected message: $output"
}

@test "an export without metadata.json is fatal" {
  stub_npx
  WORKFLOWS_TEST_NO_METADATA=true export_ota
  [ "$status" -ne 0 ] || fail "accepted an export with no metadata.json: $output"
  contains "$output" "no metadata.json" || fail "unexpected message: $output"
}

@test "a failing expo export is fatal" {
  stub_npx
  WORKFLOWS_TEST_NPX_STATUS=1 export_ota
  [ "$status" -ne 0 ] || fail "a failed export was ignored: $output"
}

# --- publish.sh -------------------------------------------------------------

publish() { run bash "$REPO_ROOT/scripts/ota/publish.sh" "$@"; }
seed_export() { mkdir -p "$WORKFLOWS_OTA_DIR"; printf '{}\n' > "$WORKFLOWS_OTA_DIR/metadata.json"; }

# I4: the export the gate vetted is what gets published, and the token the
# workflow passes in is actually handed to the CLI.
@test "publish uploads the export in WORKFLOWS_OTA_DIR, with the token" {
  stub_npx
  seed_export
  OTA_ENABLED=true OTA_CLI_VERSION=1.2.3 OTA_PUBLISH_TOKEN=tok-123 publish beta 25
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  argv="$(grep '^npx eoas' "$WORKFLOWS_TEST_LOG")"
  contains "$argv" "eoas@1.2.3 publish" || fail "the CLI is not pinned: $argv"
  contains "$argv" "--branch beta" || fail "wrong channel: $argv"
  contains "$argv" "--rollout-percentage 25" || fail "wrong rollout: $argv"
  contains "$argv" "--input-dir $WORKFLOWS_OTA_DIR" || fail "the vetted export is not what gets published: $argv"
  contains "$argv" "--skip-bundler" || fail "--input-dir without --skip-bundler re-exports: $argv"
  contains "$argv" "--non-interactive" || fail "not non-interactive: $argv"
  grep -qx 'EXPO_TOKEN=tok-123' "$WORKFLOWS_TEST_LOG" || fail "OTA_PUBLISH_TOKEN never reached the CLI: $(cat "$WORKFLOWS_TEST_LOG")"
}

@test "publish without a token still runs, and says so" {
  stub_npx
  seed_export
  OTA_ENABLED=true OTA_CLI_VERSION=1.2.3 publish beta 0
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  contains "$output" "OTA_PUBLISH_TOKEN is not set" || fail "unexpected message: $output"
  grep -qx 'EXPO_TOKEN=' "$WORKFLOWS_TEST_LOG" || fail "an empty token was invented: $(cat "$WORKFLOWS_TEST_LOG")"
}

@test "publish is a no-op unless OTA_ENABLED is exactly true" {
  stub_npx
  seed_export
  OTA_CLI_VERSION=1.2.3 publish beta 0
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  ! grep -q '^npx eoas' "$WORKFLOWS_TEST_LOG" || fail "published with OTA_ENABLED unset"
  OTA_ENABLED=yes OTA_CLI_VERSION=1.2.3 publish beta 0
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  ! grep -q '^npx eoas' "$WORKFLOWS_TEST_LOG" || fail "published with OTA_ENABLED=yes"
}

# Never publish from an unpinned CLI: the update format can change between runs.
@test "publish without a pinned CLI version is fatal" {
  stub_npx
  seed_export
  OTA_ENABLED=true publish beta 0
  [ "$status" -ne 0 ] || fail "published from an unpinned CLI: $output"
  contains "$output" "OTA_CLI_VERSION" || fail "unexpected message: $output"
}

@test "a rollout that is not an integer percentage is fatal" {
  stub_npx
  seed_export
  for r in 10.5 abc -1 101 ''; do
    OTA_ENABLED=true OTA_CLI_VERSION=1.2.3 publish beta "$r"
    [ "$status" -ne 0 ] || fail "accepted the rollout '$r': $output"
  done
  ! grep -q '^npx eoas' "$WORKFLOWS_TEST_LOG" || fail "published despite a bad rollout"
}

@test "publish without an export is fatal, and names the script that makes one" {
  stub_npx
  OTA_ENABLED=true OTA_CLI_VERSION=1.2.3 publish beta 0
  [ "$status" -ne 0 ] || fail "published with no export: $output"
  contains "$output" "export.sh" || fail "unexpected message: $output"
  mkdir -p "$WORKFLOWS_OTA_DIR"
  OTA_ENABLED=true OTA_CLI_VERSION=1.2.3 publish beta 0
  [ "$status" -ne 0 ] || fail "published with an empty export directory: $output"
}

# --- smoke.sh ---------------------------------------------------------------

stub_curl() {
  cat > "$STUB/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$WORKFLOWS_TEST_LOG"
prev=""; out=""
for a in "$@"; do [ "$prev" = "-o" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf '%s' "${WORKFLOWS_TEST_MANIFEST-manifest bytes}" > "$out"
[ "${WORKFLOWS_TEST_CURL_FAIL:-}" = "true" ] && exit 7
printf '%s' "${WORKFLOWS_TEST_CODE:-200}"
exit 0
SH
  chmod +x "$STUB/curl"
}

smoke() { run bash "$REPO_ROOT/scripts/ota/smoke.sh" "$@"; }

@test "smoke fetches the manifest with the headers a client sends" {
  stub_curl
  OTA_MANIFEST_URL=https://u.example.test/manifest OTA_RUNTIME_VERSION=1.0.0 smoke beta
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  argv="$(grep '^curl ' "$WORKFLOWS_TEST_LOG")"
  contains "$argv" "expo-channel-name: beta" || fail "no channel header: $argv"
  contains "$argv" "expo-platform: ios" || fail "no platform header: $argv"
  contains "$argv" "expo-runtime-version: 1.0.0" || fail "no runtime header: $argv"
  contains "$argv" "https://u.example.test/manifest" || fail "wrong url: $argv"
}

@test "an unset runtime version contributes no header at all" {
  stub_curl
  OTA_MANIFEST_URL=https://u.example.test/manifest smoke beta
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  not_contains "$(grep '^curl ' "$WORKFLOWS_TEST_LOG")" "expo-runtime-version" \
    || fail "an empty runtime version became a header"
}

@test "an empty manifest url skips the check instead of failing" {
  stub_curl
  smoke beta
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -s "$WORKFLOWS_TEST_LOG" ] || fail "called curl anyway: $(cat "$WORKFLOWS_TEST_LOG")"
}

# A publish that "succeeded" but serves nothing looks exactly like a working one
# until a user opens the app.
@test "a non-200 manifest is fatal" {
  stub_curl
  WORKFLOWS_TEST_CODE=404 OTA_MANIFEST_URL=https://u.example.test/manifest smoke beta
  [ "$status" -ne 0 ] || fail "accepted HTTP 404: $output"
  contains "$output" "returned HTTP 404" || fail "unexpected message: $output"
}

@test "an empty 200 manifest is fatal" {
  stub_curl
  WORKFLOWS_TEST_MANIFEST='' OTA_MANIFEST_URL=https://u.example.test/manifest smoke beta
  [ "$status" -ne 0 ] || fail "accepted an empty manifest: $output"
  contains "$output" "came back empty" || fail "unexpected message: $output"
}

@test "a failed request is fatal" {
  stub_curl
  WORKFLOWS_TEST_CURL_FAIL=true OTA_MANIFEST_URL=https://u.example.test/manifest smoke beta
  [ "$status" -ne 0 ] || fail "a failed request was ignored: $output"
  contains "$output" "failed" || fail "unexpected message: $output"
}

@test "the smoke body does not survive the run" {
  stub_curl
  OTA_MANIFEST_URL=https://u.example.test/manifest smoke beta
  [ "$status" -eq 0 ] || fail "exited $status: $output"
  [ ! -f "$RUNNER_TEMP/workflows-ota-manifest" ] || fail "left the manifest body behind"
}
