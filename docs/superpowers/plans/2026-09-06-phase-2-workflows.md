# Phase 2: `react-native-workflows` CI/E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the `react-native-workflows` repo (reusable `workflow_call` workflows, composite actions and shell scripts for Expo prebuild apps, with bats tests and self-CI) and wire the mobile template to consume it, so a consumer repo gets checks, unit tests, iOS/Android Maestro E2E and web export/deploy from ~20 lines of YAML.

**Architecture:** Every reusable workflow checks out the consumer, then checks out this repo at `${{ job.workflow_sha }}` into `.rnw/` and runs local-path composite actions and `bash "$RNW/scripts/..."` steps. No inline shell in workflows. All shell is bash strict mode, shellcheck-clean, unit-tested with bats where pure. Caches: the built `.app`/`.apk` keyed on a native-input hash, Pods, pnpm store, Maestro, system image, AVD snapshot, Playwright. Emulator/simulator lessons from esign are encoded as named scripts.

**Tech Stack:** GitHub Actions (checkout v7, cache v6, upload/download-artifact v7/v8, jdx/mise-action v4, ruby/setup-ruby v1, gradle/actions v6, ReactiveCircus/android-emulator-runner v2, configure/upload/deploy-pages v6/v5/v5, release-please-action v5), bash, yq 4, bats 1.14, shellcheck 0.11, actionlint 1.7.12, Maestro CLI 2.10.0, xcodebuild/simctl, adb.

**Spec:** `docs/superpowers/specs/2026-09-06-react-native-template-family-design.md` — Part A (workflows repo) and Part B's "web" job; Phase 2 section. Consumer facts: `/Users/jonas/Dev/blink/react-native-mobile-template` (Phase 1 complete): pnpm scripts `typecheck lint format:check knip spell i18n:check codegen:check test test:coverage test:scripts build:web test:e2e:web deps:check deps:audit deps:licenses check-prebuild`; `.mise.toml` pins node 24 / pnpm 12 / java temurin-17 / ruby 3.3; Maestro flows in `.maestro/` (config with `includeTags: [smoke]`, `executionOrder.flowsOrder`); mock API `pnpm mock-api` on :4000; dev-client app id `com.example.rnmt.dev`, scheme `rnmt`; web export `pnpm build:web --dev`; `docs/web-files.txt`.

## Global Constraints

- Repo root `/Users/jonas/Dev/blink/react-native-workflows` (git-inited on `main`, contains `docs/`, `.gitignore` with `.superpowers/`). Consumer checkout for local runs: `/Users/jonas/Dev/blink/react-native-mobile-template` (never commit to it in this phase except Task 10).
- No inline shell in workflows: every `run:` is a single `bash "$RNW/scripts/<dir>/<name>.sh" [args]` line (or `bash scripts/...` inside this repo's own self-workflows). Exception: none.
- Every script: `#!/usr/bin/env bash`, `set -euo pipefail`, `source "$(dirname "$0")/../lib/common.sh"` where helpers are needed, shellcheck-clean (`shellcheck -x`), runnable from any cwd (scripts resolve the consumer root from `$GITHUB_WORKSPACE` or `$PWD`).
- Every reusable workflow: `on: workflow_call` only; top-level `permissions: contents: read`; NO `concurrency:` (callers own it); inputs `repository`, `ref`, `working-directory` (`.`), `linux-runner` (`ubuntu-latest`), `macos-runner` (`macos-26`), `native-cache-version` (`v1`); every job has `timeout-minutes`.
- Pinned action versions: `actions/checkout@v7`, `actions/cache@v6` (+ `/restore`, `/save`), `actions/upload-artifact@v7`, `actions/download-artifact@v8`, `jdx/mise-action@v4`, `ruby/setup-ruby@v1`, `gradle/actions/setup-gradle@v6`, `ReactiveCircus/android-emulator-runner@v2`, `actions/configure-pages@v6`, `actions/upload-pages-artifact@v5`, `actions/deploy-pages@v5`, `googleapis/release-please-action@v5`.
- Versions in `scripts/lib/versions.sh` are the single source: `MAESTRO_VERSION=2.10.0`, `ANDROID_API_LEVEL=34` (AOSP `default` x86_64 image, proven), `ACTIONLINT_VERSION=1.7.12`, `SHELLCHECK_VERSION=0.11.0`, `YQ_VERSION=4.53.6`. `scripts/self/check-versions.sh` fails when a workflow default disagrees.
- Emulator: `target: default`, `arch: x86_64`, cores unset (2), `-no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none`; AVD snapshot bakes `hide_error_dialogs 1` and `anr_show_background 0`; `MAESTRO_DRIVER_STARTUP_TIMEOUT` 300000 Android / 600000 iOS; three nested timeouts (script `timeout` < step `timeout-minutes` < job).
- Commit messages: Conventional Commits, scope enum for this repo `workflows, actions, scripts, e2e, ci, release, docs, deps`; end with `Claude-Session: https://claude.ai/code/session_01SpyYZEnJaLFih75JB4EQAW`.
- Never run `expo run:ios`/`run:android` in scripts; build with `xcodebuild`/`gradlew` and install with `simctl`/`adb`. When a task runs simulators locally, poll logs with bounded sleeps; never wait on a Metro process to exit; kill started processes.

---

## File Structure

```
.github/workflows/  checks.yml unit.yml e2e.yml web.yml pr-closed.yml pr-title.yml self-ci.yml self-smoke.yml self-release.yml
.github/actions/    setup/action.yml native-key/action.yml maestro/action.yml forensics/action.yml free-disk/action.yml
.github/            dependabot.yml release.yml
scripts/lib/        common.sh versions.sh expo-config.sh
scripts/ci/         changed-class.sh free-disk.sh enable-kvm.sh native-hash.sh cancel-runs.sh lint-ci.sh artifact-summary.sh tool-version.sh maestro-install.sh pnpm-store-path.sh
scripts/checks/     run-script.sh (generic: runs a consumer package.json script if present, else fails with ::error) codegen.sh i18n.sh audit.sh expo-doctor.sh commitlint.sh
scripts/native/     prebuild.sh pods.sh ios-build.sh ios-pack.sh android-build.sh
scripts/e2e/        metro-start.sh metro-wait.sh ios-simulator.sh android-emulator.sh app-launch.sh maestro-bound.sh ios-maestro.sh android-maestro.sh collect-forensics.sh
scripts/web/        export.sh playwright-version.sh playwright.sh
scripts/self/       tag-major.sh check-versions.sh
test/               *.bats + fixtures/ (pnpm-lock.yaml excerpt, .mise.toml, changed-files lists, app.config output JSON)
docs/               consumer-guide.md cache-keys.md forensics.md runners.md
.mise.toml .shellcheckrc Makefile release-please-config.json .release-please-manifest.json CHANGELOG.md README.md LICENSE
```

Responsibilities: `scripts/lib` = shared helpers only; `scripts/ci` = runner plumbing; `scripts/checks` = thin wrappers over consumer scripts; `scripts/native` = prebuild + builds; `scripts/e2e` = device drivers + Maestro; `scripts/web` = export/test; composite actions = multi-step setup reused by every job; workflows = orchestration only.

---

### Task 1: Repo skeleton, lib, Makefile, bats harness, self-CI

**Files:** `.mise.toml`, `.shellcheckrc`, `Makefile`, `scripts/lib/common.sh`, `scripts/lib/versions.sh`, `scripts/self/check-versions.sh`, `test/common.bats`, `test/test_helper.bash`, `.github/workflows/self-ci.yml`, `LICENSE` (MIT), `README.md` (stub)

**Interfaces produced:** `common.sh` functions `log`, `die`, `group`/`endgroup`, `gh_output KEY VALUE`, `gh_env KEY VALUE`, `consumer_root` (echoes `${GITHUB_WORKSPACE:-$PWD}/${WORKING_DIRECTORY:-.}` normalised), `require_cmd NAME...`; `versions.sh` exports the pinned versions; `make check` = shellcheck + actionlint + bats.

- [ ] **Step 1: Tooling files**

`.mise.toml`:
```toml
[tools]
shellcheck = "0.11.0"
actionlint = "1.7.12"
bats = "1.14.0"
yq = "4.53.6"
node = "24"
```
`.shellcheckrc`: `external-sources=true` and `source-path=SCRIPTDIR`.

`Makefile`:
```makefile
.DEFAULT_GOAL := help
SHELL := /bin/bash
shellcheck: ## shellcheck every script (bash strict)
	shellcheck -x scripts/*/*.sh
actionlint: ## Lint workflows and composite actions
	actionlint -color
test: ## bats unit tests for the pure scripts
	bats test/
check-versions: ## Fail when workflow defaults disagree with scripts/lib/versions.sh
	bash scripts/self/check-versions.sh
check: shellcheck actionlint test check-versions ## Everything self-ci runs
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
.PHONY: shellcheck actionlint test check-versions check help
```

- [ ] **Step 2: Failing bats test**

`test/test_helper.bash`:
```bash
# shellcheck shell=bash
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export REPO_ROOT
FIXTURES="$REPO_ROOT/test/fixtures"
export FIXTURES
```
`test/common.bats`:
```bash
#!/usr/bin/env bats
load test_helper
setup() { source "$REPO_ROOT/scripts/lib/common.sh"; }
@test "gh_output appends key=value to GITHUB_OUTPUT" {
  GITHUB_OUTPUT="$BATS_TEST_TMPDIR/out"; export GITHUB_OUTPUT
  gh_output hash abc123
  run cat "$GITHUB_OUTPUT"; [ "$output" = "hash=abc123" ]
}
@test "gh_output prints to stdout when GITHUB_OUTPUT is unset" {
  unset GITHUB_OUTPUT
  run gh_output hash abc123; [ "$output" = "hash=abc123" ]
}
@test "die exits 1 with an ::error annotation" {
  run die "boom"; [ "$status" -eq 1 ]; [[ "$output" == *"::error::boom"* ]]
}
@test "consumer_root honours WORKING_DIRECTORY" {
  GITHUB_WORKSPACE="$BATS_TEST_TMPDIR"; WORKING_DIRECTORY=app; export GITHUB_WORKSPACE WORKING_DIRECTORY
  mkdir -p "$BATS_TEST_TMPDIR/app"
  run consumer_root; [ "$output" = "$BATS_TEST_TMPDIR/app" ]
}
```
Run: `mise exec -- bats test/` → FAIL (common.sh missing).

- [ ] **Step 3: Implement `scripts/lib/common.sh` and `versions.sh`**

```bash
#!/usr/bin/env bash
# Shared helpers for every script in this repo. Source it; do not execute.
# shellcheck shell=bash
log() { printf '%s\n' "$*" >&2; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }
group() { printf '::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
gh_output() { if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; else printf '%s=%s\n' "$1" "$2"; fi; }
gh_env() { if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; fi; export "$1=$2"; }
consumer_root() { local base="${GITHUB_WORKSPACE:-$PWD}"; local wd="${WORKING_DIRECTORY:-.}"; cd "$base/$wd" && pwd -P; }
require_cmd() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done; }
```
`scripts/lib/versions.sh`:
```bash
#!/usr/bin/env bash
# Single source of pinned tool versions. Workflow defaults must match (scripts/self/check-versions.sh).
# shellcheck shell=bash
export MAESTRO_VERSION="2.10.0"
export ANDROID_API_LEVEL="34"
export ACTIONLINT_VERSION="1.7.12"
export SHELLCHECK_VERSION="0.11.0"
export YQ_VERSION="4.53.6"
```
`scripts/self/check-versions.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source scripts/lib/versions.sh
fail=0
grep -q "default: '$MAESTRO_VERSION'" .github/workflows/e2e.yml 2>/dev/null || { echo "::error::e2e.yml maestro-version default != $MAESTRO_VERSION"; fail=1; }
grep -q "default: $ANDROID_API_LEVEL" .github/workflows/e2e.yml 2>/dev/null || { echo "::error::e2e.yml android-api-level default != $ANDROID_API_LEVEL"; fail=1; }
grep -q "shellcheck = \"$SHELLCHECK_VERSION\"" .mise.toml || { echo "::error::.mise.toml shellcheck != $SHELLCHECK_VERSION"; fail=1; }
grep -q "actionlint = \"$ACTIONLINT_VERSION\"" .mise.toml || { echo "::error::.mise.toml actionlint != $ACTIONLINT_VERSION"; fail=1; }
exit $fail
```
(Until `e2e.yml` exists in Task 7, the two e2e greps fail: make them conditional on the file existing — `[ -f .github/workflows/e2e.yml ] && ...` — and remove the guard in Task 7.)

- [ ] **Step 4: Run tests** → `mise exec -- bats test/` 4 pass; `make shellcheck` clean.

- [ ] **Step 5: `self-ci.yml`**

```yaml
name: Self CI
on:
  push: { branches: [main] }
  pull_request:
permissions: { contents: read }
concurrency: { group: self-ci-${{ github.ref }}, cancel-in-progress: ${{ github.ref != 'refs/heads/main' }} }
jobs:
  check:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: jdx/mise-action@v4
      - run: make check
  pr-title:
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v7
      - uses: jdx/mise-action@v4
      - env: { PR_TITLE: "${{ github.event.pull_request.title }}" }
        run: bash scripts/checks/commitlint.sh
```
(`scripts/checks/commitlint.sh` is written in Task 3; until then `make actionlint` must still pass — actionlint does not check script existence.)

- [ ] **Step 6: `make check` green (bats + shellcheck + actionlint + check-versions); commit** `chore(scripts): repo skeleton with lib, bats harness and self-ci`.

---

### Task 2: Pure scripts with bats tests (hashing, classification, tool versions, expo config)

**Files:** `scripts/ci/native-hash.sh`, `scripts/ci/changed-class.sh`, `scripts/ci/tool-version.sh`, `scripts/lib/expo-config.sh`, `scripts/web/playwright-version.sh`, `scripts/ci/pnpm-store-path.sh`, tests `test/native-hash.bats`, `test/changed-class.bats`, `test/tool-version.bats`, `test/playwright-version.bats`, fixtures under `test/fixtures/` (copy `pnpm-lock.yaml` and `.mise.toml` from the template checkout into `test/fixtures/consumer/`, plus `test/fixtures/expo-config.json` = output of `pnpm expo config --json --type public` run in the template).

**Interfaces produced:** `native-hash.sh [consumer-root]` → 16-hex-char hash on stdout; `changed-class.sh BASE_SHA HEAD_SHA` → `docs-only=true|false` via `gh_output`; `tool-version.sh TOOL [file]` → version string from `.mise.toml`; `expo-config.sh KEY` → `name|slug|scheme|ios.bundleIdentifier|android.package|ios.scheme-name` from `expo config --json`; `playwright-version.sh [lockfile]` → version; `pnpm-store-path.sh` → path.

- [ ] **Step 1: Failing bats tests** (write all four files; representative cases):

`test/native-hash.bats`:
```bash
#!/usr/bin/env bats
load test_helper
@test "hash is 16 hex chars and stable" {
  run bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$FIXTURES/consumer"; [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9a-f]{16}$ ]]
  first="$output"; run bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$FIXTURES/consumer"; [ "$output" = "$first" ]
}
@test "hash changes when a native dep version changes but not for a jest bump" {
  cp -R "$FIXTURES/consumer" "$BATS_TEST_TMPDIR/c"
  base=$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")
  sed -i.bak 's/^\(  jest:\)$/\1/' "$BATS_TEST_TMPDIR/c/pnpm-lock.yaml"   # no-op edit keeps hash
  [ "$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")" = "$base" ]
  echo "# native input" >> "$BATS_TEST_TMPDIR/c/app.config.ts"
  [ "$(bash "$REPO_ROOT/scripts/ci/native-hash.sh" "$BATS_TEST_TMPDIR/c")" != "$base" ]
}
```
`test/changed-class.bats`: create a temp git repo with commits touching `docs/x.md` only → `docs-only=true`; then `src/a.ts` → `false`; `README.md` + `docs/` → `true`; `.github/workflows/ci.yml` → `false`.
`test/tool-version.bats`: `tool-version.sh node "$FIXTURES/consumer/.mise.toml"` → `24`; `ruby` → `3.3`; unknown tool → exit 1 with `::error`.
`test/playwright-version.bats`: on the fixture lockfile → matches `^[0-9]+\.[0-9]+\.[0-9]+$` (the template pins 1.62.1).

- [ ] **Step 2: Implement**

`scripts/ci/native-hash.sh` (port of `/Users/jonas/Dev/esign/scripts/native-deps-hash.sh` to pnpm):
```bash
#!/usr/bin/env bash
# Hash of every input the native (Xcode/Gradle) build consumes in an Expo prebuild app:
# the lockfile-resolved versions of runtime deps + native-adjacent dev deps, plus the
# config/plugin/module/patch files. A jest/eslint bump does not change it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root="${1:-$(consumer_root)}"
require_cmd yq shasum
lock="$root/pnpm-lock.yaml"; [ -f "$lock" ] || die "no pnpm-lock.yaml in $root"
deps=$(yq -r '.importers["."].dependencies // {} | to_entries[] | "\(.key)@\(.value.version)"' "$lock")
devs=$(yq -r '.importers["."].devDependencies // {} | to_entries[] | select(.key | test("^(expo|@expo/|react-native|@react-native|@react-native-community|@config-plugins/|patch-package)")) | "\(.key)@\(.value.version)"' "$lock")
files=$(cd "$root" && find . -maxdepth 1 \( -name 'app.config.*' -o -name 'app.json' -o -name 'Gemfile.lock' -o -name '.mise.toml' -o -name 'google-services.json' -o -name 'GoogleService-Info.plist' \) -type f | sort)
dirs=$(cd "$root" && for d in plugins modules patches; do [ -d "$d" ] && find "$d" -type f | sort; done || true)
{
  printf '%s\n' "$deps" "$devs"
  for f in $files $dirs; do printf '%s ' "$f"; shasum -a 256 "$root/$f" | cut -c1-64; done
  printf 'extra=%s\n' "${NATIVE_EXTRA_GLOBS:-}"
} | shasum -a 256 | cut -c1-16
```
`scripts/ci/changed-class.sh` (port of esign `changed-class.sh`): `git diff --name-only BASE HEAD`; docs-only iff every path matches `^docs/|\.md$|^LICENSE$|^\.github/ISSUE_TEMPLATE/|^\.github/PULL_REQUEST_TEMPLATE` (override via `DOCS_GLOBS` env, space-separated extended regexes); emits `gh_output docs-only true|false`; non-PR events (no BASE) → `false`.
`scripts/ci/tool-version.sh`: `awk -F'"' -v t="$1" '$0 ~ "^"t" *= *\"" {print $2; exit}' "$file"`; no match → `die`.
`scripts/lib/expo-config.sh`: runs `pnpm exec expo config --json --type public` in `consumer_root` once, caches to `${RUNNER_TEMP:-/tmp}/expo-config.json`, extracts keys with `yq -r`; `ios.scheme-name` = `name` with `[^A-Za-z0-9]` stripped (Expo's Xcode scheme name; validate against `ios/*.xcworkspace` in Task 4).
`scripts/web/playwright-version.sh`: `yq -r '.importers["."].devDependencies["@playwright/test"].version' lockfile | sed 's/(.*//'`.
`scripts/ci/pnpm-store-path.sh`: `cd "$(consumer_root)" && pnpm store path`.

- [ ] **Step 3: bats green; shellcheck clean; commit** `feat(scripts): native hash, change classification and version readers with bats`.

---

### Task 3: Runner plumbing and check wrappers

**Files:** `scripts/ci/free-disk.sh`, `scripts/ci/enable-kvm.sh`, `scripts/ci/cancel-runs.sh`, `scripts/ci/lint-ci.sh`, `scripts/ci/maestro-install.sh`, `scripts/ci/artifact-summary.sh`, `scripts/checks/run-script.sh`, `scripts/checks/codegen.sh`, `scripts/checks/i18n.sh`, `scripts/checks/audit.sh`, `scripts/checks/expo-doctor.sh`, `scripts/checks/commitlint.sh`, `test/run-script.bats`, `test/artifact-summary.bats`

**Interfaces produced:** `run-script.sh NAME` runs `pnpm run NAME` in the consumer root or dies with `::error::consumer package.json has no "NAME" script (contract: see docs/consumer-guide.md)`; `codegen.sh` = `run-script.sh codegen` then `git diff --exit-code -- <paths from CODEGEN_PATHS env, default src/graphql/generated>`; `i18n.sh` analogous with `i18n:extract` and `src/i18n/locales`; `audit.sh` = `pnpm audit --audit-level "${AUDIT_LEVEL:-high}" --prod`; `expo-doctor.sh` = `pnpm exec expo-doctor` if in devDeps else `pnpm dlx expo-doctor@latest`; `commitlint.sh` lints `$PR_TITLE` via `pnpm exec commitlint` if the consumer has commitlint, else `npx --yes @commitlint/cli@21 --config <default conventional config written to $RUNNER_TEMP>`; `artifact-summary.sh TITLE URL [junit.xml]` writes a markdown block to `$GITHUB_STEP_SUMMARY`.

- [ ] **Step 1: Failing tests** — `run-script.bats`: fixture package.json with `typecheck` script → runs it (use a script that touches a file); missing script → exit 1 with `::error::`. `artifact-summary.bats`: with a junit fixture (3 tests, 1 failure) the summary contains `2 passed, 1 failed` and the URL.
- [ ] **Step 2: Implement.** Port `free-disk.sh` (esign: removes `/usr/share/dotnet`, `/usr/local/lib/android/sdk/ndk` older, `/opt/ghc`, `/usr/local/.ghcup`, docker images; prints `df -h /` before/after), `enable-kvm.sh` (udev rule `KERNEL=="kvm", GROUP="kvm", MODE="0666"` + `udevadm control --reload-rules && udevadm trigger --name-match=kvm`; exports `ANDROID_SDK_DIR=${ANDROID_HOME:-$ANDROID_SDK_ROOT}` via `gh_env`), `cancel-runs.sh` (gh api: list runs for `HEAD_SHA` with status queued|in_progress, cancel all except `$GITHUB_RUN_ID`; env `GH_TOKEN`, `REPO`, `HEAD_SHA`), `lint-ci.sh` (in consumer root: `mise x actionlint@$ACTIONLINT_VERSION -- actionlint -color` if `.github/workflows` exists; `mise x shellcheck@$SHELLCHECK_VERSION -- shellcheck -x` over `scripts/**/*.sh` excluding `.rnw`), `maestro-install.sh` (download `https://github.com/mobile-dev-inc/maestro/releases/download/cli-${MAESTRO_VERSION}/maestro.zip` to `~/.maestro` unless `~/.maestro/bin/maestro --version` already equals the version; `echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"`).
- [ ] **Step 3: bats + shellcheck green; commit** `feat(scripts): runner plumbing and consumer check wrappers`.

---

### Task 4: Native build and E2E device scripts (ported from esign, adapted to Expo prebuild), proven locally on iOS

**Files:** `scripts/native/prebuild.sh`, `pods.sh`, `ios-build.sh`, `ios-pack.sh`, `android-build.sh`; `scripts/e2e/metro-start.sh`, `metro-wait.sh`, `ios-simulator.sh`, `android-emulator.sh`, `app-launch.sh`, `maestro-bound.sh`, `ios-maestro.sh`, `android-maestro.sh`, `collect-forensics.sh`; `test/maestro-bound.bats`

**Interfaces produced (env contract, all optional with defaults):** `RNW_PLATFORM`, `RNW_XCODE` (Xcode version → `sudo xcode-select -s /Applications/Xcode_$RNW_XCODE.app` when set), `RNW_APP_ID` (default from `expo-config.sh ios.bundleIdentifier` / `android.package` + `.dev` when `APP_VARIANT` unset — the template's dev variant), `RNW_DEV_CLIENT` (`true`), `RNW_MAESTRO_FLOWS` (`.maestro`), `RNW_MAESTRO_INCLUDE_TAGS`/`EXCLUDE_TAGS`, `RNW_SUITE_TIMEOUT_MINUTES` (10), `RNW_METRO_PORT` (8081), `RNW_OUT` (`${RUNNER_TEMP:-/tmp}/rnw`), `RNW_E2E_SETUP_SCRIPT`/`RNW_E2E_TEARDOWN_SCRIPT` (consumer-relative paths). Outputs: `ios-pack.sh` → `$RNW_OUT/<scheme>.app.tar`; `android-build.sh` → `android/app/build/outputs/apk/debug/app-debug.apk`; `ios-simulator.sh pick` → `gh_output udid`.

- [ ] **Step 1: bats for `maestro-bound.sh`**: sourcing exposes `bounded_maestro SECONDS CMD...`; a command sleeping longer than the bound exits 124; a fast command's exit code is propagated; `timeout`/`gtimeout` detection (macOS needs coreutils: script falls back to a bash `( cmd & )` + `sleep` watchdog when neither exists).
- [ ] **Step 2: Implement (ports)** — read each esign source first:
  - `prebuild.sh PLATFORM`: `cd consumer_root; CI=1 EXPO_NO_GIT_STATUS=1 pnpm exec expo prebuild --platform "$1" --clean --no-install`.
  - `pods.sh`: `cd ios && COCOAPODS_DISABLE_STATS=1 bundle exec pod install` if `Gemfile` exists in consumer root, else `pod install`; prints `Podfile.lock` first 5 lines.
  - `ios-build.sh` (port `esign/scripts/e2e/ios-build.sh`): scheme = `expo-config.sh ios.scheme-name` validated against `ls ios/*.xcworkspace`; `xcodebuild -workspace ios/<scheme>.xcworkspace -scheme <scheme> -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/build CODE_SIGNING_ALLOWED=NO build | xcbeautify || tee` (use `xcbeautify` if present else `xcpretty` else raw); asserts the `.app` exists.
  - `ios-pack.sh`: `tar -C ios/build/Build/Products/Debug-iphonesimulator -cf "$RNW_OUT/<scheme>.app.tar" <scheme>.app`.
  - `android-build.sh`: `cd android && ./gradlew :app:assembleDebug -PreactNativeArchitectures=x86_64 --no-daemon --build-cache`.
  - `metro-start.sh` (port): `cd consumer_root; CI=1 nohup pnpm exec expo start --port "$RNW_METRO_PORT" > "$RNW_OUT/metro.log" 2>&1 &`; writes the PID to `$RNW_OUT/metro.pid`.
  - `metro-wait.sh PLATFORM` (port, Expo entry): poll `http://localhost:$PORT/status` for `packager-status:running` (≤180s), then GET `/.expo/.virtual-metro-entry.bundle?platform=$PLATFORM&dev=true&hot=false&lazy=true&transform.engine=hermes` to prewarm (≤300s).
  - `ios-simulator.sh pick|wait|install TAR|record start|stop|shutdown` (port `esign/scripts/e2e/ios-simulator.sh`): `pick` = first available iPhone from `xcrun simctl list -j devices available` (prefer names matching `iPhone 1[5-9]|iPhone 2`), boot it, `gh_output udid`; `wait` = `simctl bootstatus -b`; `install` = untar to `$RNW_OUT` then `simctl install`; `record start` = `simctl io UDID recordVideo --codec h264 $RNW_OUT/ios.mp4 &` (pid file), `stop` = SIGINT the pid and wait.
  - `android-emulator.sh snapshot-bake|prepare|record start|stop`: `snapshot-bake` = `adb shell settings put global hide_error_dialogs 1; adb shell settings put global anr_show_background 0; adb shell settings put global window_animation_scale 0 (and transition/animator)`; `prepare` = `adb install -r APK`, `adb reverse tcp:$RNW_METRO_PORT tcp:$RNW_METRO_PORT`, `adb reverse tcp:4000 tcp:4000`, `adb logcat -G 64M`, `adb logcat -c`, re-assert the two settings; `record` = looped `adb shell screenrecord` 3-minute chunks pulled to `$RNW_OUT/android-N.mp4`.
  - `app-launch.sh PLATFORM`: iOS: `simctl launch UDID APP_ID` or, with `RNW_DEV_CLIENT=true`, `simctl openurl UDID "<scheme>://expo-development-client/?url=http%3A%2F%2Flocalhost%3A$PORT"` (scheme from `expo-config.sh scheme`); Android: `adb shell am start -n APP_ID/.MainActivity` or `am start -a android.intent.action.VIEW -d "<scheme>://expo-development-client/?url=http%3A%2F%2F10.0.2.2%3A$PORT"`. Then wait until `$RNW_OUT/metro.log` shows a bundle request (≤120s).
  - `maestro-bound.sh` (verbatim port of esign's, plus the fallback watchdog).
  - `ios-maestro.sh` / `android-maestro.sh`: source `maestro-bound.sh`; `export MAESTRO_DRIVER_STARTUP_TIMEOUT=600000|300000`; run `RNW_E2E_SETUP_SCRIPT` if set; `bounded_maestro $((RNW_SUITE_TIMEOUT_MINUTES*60)) maestro test "$RNW_MAESTRO_FLOWS" --config "$RNW_MAESTRO_FLOWS/config.yaml" -e APP_ID="$RNW_APP_ID" --debug-output "$RNW_OUT/maestro" --flatten-debug-output --format junit --output "$RNW_OUT/maestro/junit.xml" [--include-tags ...]`; one retry on non-124 failure (iOS skips retry after 124); `android-maestro.sh` is the single-line entry for `android-emulator-runner`'s `script:` and internally calls `android-emulator.sh prepare`, `record start`, `app-launch.sh android`, the bounded run, `collect-forensics.sh android`.
  - `collect-forensics.sh PLATFORM`: iOS: copy `~/Library/Logs/DiagnosticReports/*` newer than the run start, `metro.log`, video; Android: `adb logcat -d > logcat.txt`, `adb logcat -d -b crash`, grep `ReactNativeJS|AndroidRuntime|FATAL|lowmemorykiller|has died` into a `::group::`; both: tar nothing, just leave files in `$RNW_OUT/forensics/`.
- [ ] **Step 3: Local iOS proof on this Mac.** With `GITHUB_WORKSPACE=/Users/jonas/Dev/blink/react-native-mobile-template RNW_OUT=$(mktemp -d)`: `prebuild.sh ios` → `pods.sh` → `ios-build.sh` → `ios-pack.sh` (the template's `ios/` is gitignored; delete it afterwards) → `ios-simulator.sh pick` → `metro-start.sh` → run the template's mock API (`pnpm mock-api` in background) → `ios-simulator.sh wait` → `install` → `metro-wait.sh ios` → `app-launch.sh ios` → `ios-maestro.sh` → expect 6/6 passed junit → `collect-forensics.sh ios` → kill Metro and mock API. Record the outputs in the report. (Android: only if `emulator -list-avds` is non-empty; else state skipped.)
- [ ] **Step 4: shellcheck + bats green; commit** `feat(e2e): native build and device scripts for Expo prebuild apps`.

---

### Task 5: Composite actions

**Files:** `.github/actions/setup/action.yml`, `native-key/action.yml`, `maestro/action.yml`, `forensics/action.yml`, `free-disk/action.yml`

**Interfaces produced:**
- `setup`: inputs `working-directory` (`.`), `install` (`true`), `ruby` (`false`). Steps: `jdx/mise-action@v4` with `working_directory` = consumer, `cache: true`; `ruby/setup-ruby@v1` (when `ruby`) with `ruby-version: ${{ steps.rb.outputs.v }}` from `tool-version.sh ruby` and `bundler-cache: true`, `working-directory`; pnpm store cache (`actions/cache@v6`, path from `pnpm-store-path.sh`, key `pnpm-${{ runner.os }}-${{ hashFiles('**/pnpm-lock.yaml') }}`, restore-keys prefix); `pnpm install --frozen-lockfile` (when `install`); exports `RNW=$GITHUB_WORKSPACE/.rnw` via `gh_env`; appends `.rnw/` to `.git/info/exclude`.
- `native-key`: inputs `working-directory`, `native-cache-version`, `xcode`, `native-extra-globs`; outputs `hash`, `ios-key`, `android-key`, `pods-key` (formulas from the spec's cache-keys table). Runs `native-hash.sh` (needs yq: `mise x yq@$YQ_VERSION`; run BEFORE `setup` so no install is needed on a cache hit).
- `maestro`: input `version`; cache `~/.maestro` key `maestro-${{ runner.os }}-<version>`; runs `maestro-install.sh`.
- `forensics`: inputs `name`, `path` (`$RNW_OUT/forensics`), `junit` (optional path), `retention-days` (7); `actions/upload-artifact@v7` with `if-no-files-found: ignore`, then `artifact-summary.sh "$name" "${{ steps.up.outputs.artifact-url }}" "$junit"`.
- `free-disk`: runs `free-disk.sh`.

- [ ] **Step 1: Write the five actions; `actionlint` validates composite actions too.** Each `run:` is one `bash "$RNW/scripts/..."` line except inside `setup` before `RNW` exists (use `bash "$GITHUB_ACTION_PATH/../../../scripts/..."`).
- [ ] **Step 2: `make check` green; commit** `feat(actions): setup, native-key, maestro, forensics and free-disk composite actions`.

---

### Task 6: `checks.yml` and `unit.yml`

**Files:** `.github/workflows/checks.yml`, `.github/workflows/unit.yml`, `test/workflow-shape.bats` (yq assertions: every workflow has `on.workflow_call`, top-level `permissions.contents == read`, no `concurrency`, every job has `timeout-minutes`, every `run:` line starts with `bash `)

**Interfaces produced:** per the spec Part A: `checks.yml` inputs (bool) `typecheck lint format i18n graphql-codegen expo-doctor audit commitlint commitlint-commits actionlint shellcheck docs-only-detection` (+ `audit-level`, `docs-globs`) and output `docs-only`; jobs `changes` (fetch-depth 0; `changed-class.sh` with `${{ github.event.pull_request.base.sha }}` / `${{ github.sha }}`), `code` (setup, then one step per toggle: `bash "$RNW/scripts/checks/run-script.sh" typecheck` etc.), `commits` (PR only, not dependabot). `unit.yml` inputs `coverage` (true), `test-script` (`test`), `scripts-test-script` (`test:scripts`, empty = skip); job `unit` runs both, uploads `coverage/` (30 d).

- [ ] **Step 1: Failing `workflow-shape.bats`** (assertions above over `.github/workflows/*.yml` excluding `self-*`).
- [ ] **Step 2: Write both workflows** (every step's `run:` a single `bash "$RNW/scripts/..."` line; the three standard checkout/rnw/setup steps first; `.rnw` checkout: `repository: ${{ job.workflow_repository }}`, `ref: ${{ job.workflow_sha }}`, `path: .rnw`, `persist-credentials: false`).
- [ ] **Step 3: bats + actionlint green; commit** `feat(workflows): reusable checks and unit workflows`.

---

### Task 7: `e2e.yml`

**Files:** `.github/workflows/e2e.yml`; update `scripts/self/check-versions.sh` (remove the file-exists guards); `docs/cache-keys.md`

**Interfaces produced:** inputs per spec (`ios` false, `android` true, `xcode`, `android-api-level` 34, `maestro-version` 2.10.0, `maestro-flows`, include/exclude tags, `suite-timeout-minutes` 10, `dev-client` true, `e2e-setup-script`, `e2e-teardown-script`, artifact names); outputs `ios-result`, `android-result`; jobs `build-ios`, `ios`, `build-android`, `android` exactly as the spec's Part A describes, with the emulator-runner settings from Global Constraints, `native-key` → `actions/cache/restore@v6` (exact key) → build on miss → `actions/cache/save@v6` → artifact (tar for iOS, APK with `compression-level: 0`), device jobs downloading the artifact, the AVD/system-image caches, one-line emulator `script:` entries, `always()` forensics.

- [ ] **Step 1: Write the workflow.** Step timeouts: iOS maestro step `timeout-minutes: ${{ inputs.suite-timeout-minutes + 5 }}` is not valid YAML arithmetic — use `fromJSON(inputs.suite-timeout-minutes) + 5` inside `${{ }}`; jobs 60.
- [ ] **Step 2: `docs/cache-keys.md`** table from the spec (produced by `native-key`).
- [ ] **Step 3: `make check` green (workflow-shape bats includes e2e); commit** `feat(workflows): reusable e2e workflow with cached native builds and forensics`.

---

### Task 8: `web.yml`, `pr-closed.yml`, `pr-title.yml`, web scripts

**Files:** `.github/workflows/web.yml`, `pr-closed.yml`, `pr-title.yml`, `scripts/web/export.sh`, `scripts/web/playwright.sh`

**Interfaces produced:** `web.yml` inputs `playwright` (true), `deploy` (false), `base-url` (''), `export-script` (`build:web`), `export-args` (`--dev` allowed for smoke; default ''), `output-dir` (`dist`), `e2e-script` (`test:e2e:web`); outputs `page-url`; jobs `build` (setup; `export.sh` runs `pnpm run $EXPORT_SCRIPT -- $EXPORT_ARGS` with `EXPO_PUBLIC_BASE_URL`; uploads `web-dist` and, when `deploy`, `actions/upload-pages-artifact@v5`), `playwright` (download dist; cache browsers keyed on `playwright-version.sh`; `pnpm exec playwright install chromium --with-deps`; `playwright.sh` runs the consumer's Playwright against `dist` — the template's `test:e2e:web` re-exports first, so `playwright.sh` runs `pnpm exec playwright test` directly with `PLAYWRIGHT_SKIP_EXPORT=1`, and the consumer-guide documents that contract), `deploy` (pages perms, environment `github-pages`). `pr-closed.yml` (`cancel-runs.sh`), `pr-title.yml` (`commitlint.sh`).

- [ ] Write scripts + workflows; bats shape test passes; `make check` green; commit `feat(workflows): web export/playwright/pages, pr-closed and pr-title workflows`.

---

### Task 9: Self-smoke, self-release, docs, dependabot, README

**Files:** `.github/workflows/self-smoke.yml`, `self-release.yml`, `scripts/self/tag-major.sh`, `release-please-config.json`, `.release-please-manifest.json`, `CHANGELOG.md` (seed), `.github/dependabot.yml`, `.github/release.yml`, `docs/consumer-guide.md`, `docs/forensics.md`, `docs/runners.md`, `README.md`

- `self-smoke.yml`: `workflow_dispatch` (inputs `repository` default `blinkbitcoin/react-native-mobile-template`, `ref` default `main`, `ios` false) + weekly cron; jobs call `./.github/workflows/checks.yml`, `./unit.yml`, `./e2e.yml` (android true) with `repository`/`ref` inputs; `secrets: inherit` is not needed (public consumer) — document the PAT path for private consumers.
- `self-release.yml`: release-please (`release-type: simple`, `package-name: react-native-workflows`) on push to main; job `major-tag` on `release: published` runs `tag-major.sh` (`git tag -f vN <sha>`; `git push -f origin vN`; also `vN.M`), permissions `contents: write`.
- `docs/consumer-guide.md`: the consumer `ci.yml` example (spec §Consumer), the package.json script contract table, inputs tables per workflow, secrets policy, `.rnw` ignore list for consumers, the Playwright/export contract, the "no push+pull_request double trigger" note.
- `docs/forensics.md`: what each artifact contains and how to read Maestro debug output. `docs/runners.md`: macos-26 billing note, `RNW_MACOS_RUNNER` var, self-hosted labels.
- `README.md`: 60-second consumer start.
- [ ] `make check` green; commit `docs(docs): consumer guide, forensics, runners; self-smoke and release-please` (split into `ci(ci): ...` + `docs(docs): ...` if commitlint objects).

---

### Task 10: Wire the template as the first consumer

**Files (in `/Users/jonas/Dev/blink/react-native-mobile-template`, branch `phase-2-ci` from `main`):** `.github/workflows/ci.yml`, `web.yml`, `pr-closed.yml`, `pr-title.yml`; add `.rnw/` to `biome.json` `files.includes` negation, `eslint.config.mjs` `globalIgnores`, `tsconfig.json` `exclude`, `knip.json` `ignore`, `typos.toml` `extend-exclude`, `.gitignore`; `docs/ci.md` (how CI maps to make targets, how to opt in iOS with the `e2e:ios` label / `E2E_IOS` var, forensics); Makefile `check-ci` already runs actionlint when workflows exist.

- `ci.yml` exactly the spec's consumer example (`checks` → `unit` → `e2e` with `ios` gated by `vars.E2E_IOS`/label and `macos-runner: ${{ vars.RNW_MACOS_RUNNER || 'macos-26' }}`, `dev-client: true`, `e2e-setup-script: scripts/e2e/ci-mock-api-up.sh`, `e2e-teardown-script: scripts/e2e/ci-mock-api-down.sh` — create these two small scripts in the template: start `pnpm mock-api` in the background with a pid file and wait via `wait-for-mock-api.sh`; teardown kills the pid); `web.yml` calls `web.yml@v1` with `export-args: --dev`, `deploy: ${{ github.event_name == 'release' }}` on `release: published` + PR; `pr-closed.yml`, `pr-title.yml` thin callers.
- [ ] `make check` (incl. `check-ci` → actionlint on the new workflows) green in the template; `pnpm knip` clean; `make unit` green; commit on the template branch `ci(ci): consume react-native-workflows for checks, unit, e2e and web` and merge `phase-2-ci` into `main` (fast-forward) only after the review of this task.

---

### Task 11: Phase 2 acceptance

- [ ] Workflows repo: `make check` (shellcheck, actionlint, bats, check-versions) green; every workflow has the standard three-step preamble; `docs/consumer-guide.md` script-contract table matches the template's `package.json` scripts (assert with a small bats test that reads the template's package.json fixture).
- [ ] Local consumer-contract dry run: from the template checkout, run the scripts the `checks.yml` `code` job would run, in order, with `RNW=/Users/jonas/Dev/blink/react-native-workflows`: `run-script.sh typecheck`, `lint`, `format:check`, `knip`, `spell`; `i18n.sh`; `codegen.sh`; `expo-doctor.sh`; `audit.sh`; `lint-ci.sh` — all exit 0.
- [ ] Local E2E chain re-run (iOS; Android if an emulator exists) using the Task 4 scripts against the template `main` (after Task 10 merge) — 6/6 Maestro, junit produced, forensics dir populated, no leftover processes.
- [ ] Tag the workflows repo `v0.1.0` and `v1` locally (`tag-major.sh` dry run mode `--local`), write the "after push" checklist into `README.md` (create GitHub repo, push, run self-smoke, set `E2E_IOS`).
- [ ] Commit `docs(docs): phase 2 acceptance notes` and tag `phase-2-complete` in the workflows repo.

## Self-review notes
- Spec coverage (Part A + Phase 2): tree (T1–T9), self-checkout mechanism (T5/T6), common inputs (T6–T8), checks/unit (T6), e2e with all esign lessons (T4/T7), web (T8), pr-closed/pr-title (T8), self-ci/smoke/release (T1/T9), cache keys (T5/T7 docs), consumer ci.yml (T10), gotchas table (docs T9). Release workflows (`expo-prepare`, `expo-build-*`, `fastlane-lane`, `github-release`, `expo-ota-publish`) are Phase 3.
- Interface consistency: `RNW` env exported by `setup` and used by every `run:`; `native-key` outputs used by `e2e.yml`; `RNW_*` env contract shared by scripts and documented in the consumer guide; `docs-only` output name used by the template `ci.yml`.
- Judgement calls the implementer may adjust against real tools: `expo config --json` key names for the Xcode scheme; `simctl recordVideo` flag names on the installed Xcode; `yq` expression syntax for pnpm-lock importers; actionlint's handling of `${{ job.workflow_sha }}` (supported since 1.7.x).
