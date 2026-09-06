# Consumer guide

How a React Native (Expo) app consumes the reusable workflows and scripts in
this repo.

## 60-second start

1. Add `.github/workflows/ci.yml` (below) to your app repo.
2. Make sure your `package.json` has the scripts listed in [Script
   contract](#script-contract) — everything is optional and defaulted; a
   missing script only fails the check that calls it.
3. Push. `checks` and `unit` run on every PR; `e2e` (Android by default) runs
   after them.
4. Add `web.yml`, `pr-closed.yml`, `pr-title.yml` if you want those too (all
   three below).

That's it — every job self-checks-out this repo into `.rnw/` and reaches its
scripts through `$RNW`; you never reference anything under `scripts/` or
`.github/actions/` directly.

## Versioning

Pre-1.0: this repo is versioned by
[release-please](https://github.com/googleapis/release-please) starting at
`0.1.0`, and the moving major tag is **`v0`** (moved to the tip of each
`0.x.y` release by `self-release.yml`'s `major-tag` job / `scripts/self/tag-major.sh`).
Pin callers to `@v0` (or a full tag, e.g. `@v0.3.1`, for maximum
reproducibility) until this repo reaches `1.0.0`, at which point `@v1` becomes
available and is the recommended pin going forward. `@v0` and `@v1` behave
identically in kind — both are moving tags re-pointed on release — the only
difference is which major line you're tracking.

## Consumer `ci.yml`

```yaml
name: ci
on:
  push:
    branches: [main]
    paths-ignore: [docs/**, "**.md"]
  pull_request:
    types: [opened, synchronize, reopened, labeled]
  workflow_dispatch:
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
jobs:
  checks:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/checks.yml@v0
  unit:
    needs: checks
    if: ${{ needs.checks.outputs.docs-only != 'true' }}
    uses: blinkbitcoin/react-native-workflows/.github/workflows/unit.yml@v0
  e2e:
    needs: checks
    if: ${{ needs.checks.outputs.docs-only != 'true' }}
    uses: blinkbitcoin/react-native-workflows/.github/workflows/e2e.yml@v0
    with:
      ios: ${{ vars.E2E_IOS == 'true' || contains(github.event.pull_request.labels.*.name, 'e2e:ios') }}
      macos-runner: ${{ vars.RNW_MACOS_RUNNER || 'macos-26' }}
```

Notes:

- **No push+pull_request double trigger.** `push` is scoped to `branches:
  [main]` only — a PR from a branch in the same repo would otherwise fire
  both `push` (on every commit) and `pull_request` (on open/sync), running
  the whole suite twice for the same commit. Fork PRs only ever fire
  `pull_request`, so this asymmetry is intentional, not a gap.
- `pull_request: types: [opened, synchronize, reopened, labeled]` — `labeled`
  is there so adding the `e2e:ios` label to an already-open PR triggers a new
  run that picks it up (a label change is not `synchronize`).
- `concurrency` is the **caller's** job, not this repo's — none of the
  reusable workflows set it (a called workflow's `concurrency` would fight the
  caller's). Cancel in-flight runs on every branch except `main` (a `main`
  push after a merge should never be cancelled by the next one).
- `docs-only` (from `checks.yml`'s `changes` job) lets `unit` and `e2e` skip
  entirely on a docs-only diff; wire it into any other downstream job you add.

## `web.yml`, `pr-closed.yml`, `pr-title.yml` callers

```yaml
# .github/workflows/web.yml — only add this if the app has a web target
name: web
on:
  push: { branches: [main] }
  pull_request: { types: [opened, synchronize, reopened] }
permissions:
  contents: read
concurrency:
  group: web-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
jobs:
  web:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/web.yml@v0
    with:
      deploy: ${{ github.ref_type == 'tag' }}
```

```yaml
# .github/workflows/pr-closed.yml
name: pr-closed
on:
  pull_request:
    types: [closed]
permissions:
  contents: read
  actions: write   # required: pr-closed.yml's cancel job needs this to cancel runs
jobs:
  pr-closed:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/pr-closed.yml@v0
```

```yaml
# .github/workflows/pr-title.yml
name: pr-title
on:
  pull_request:
    types: [opened, edited, synchronize]
permissions:
  contents: read
jobs:
  pr-title:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/pr-title.yml@v0
```

`pr-closed.yml` is the one workflow in this family with no `inputs:` at all
(`on.workflow_call: {}`) — it only calls the GitHub API with data from the
`github` context, so it never checks the consumer out.

## Secrets policy

Every workflow in this family that checks out a consumer accepts one optional
secret, `consumer-token` (declared as `secrets: consumer-token: required:
false`), and passes it to the consumer's `actions/checkout` step as `token: ${{
secrets.consumer-token || github.token }}`. For a **public** consumer
repository this is never needed — the default `github.token` has read access
and every example above omits `secrets:` entirely. It exists for
`self-smoke.yml`, whose target defaults to the public
`blinkbitcoin/react-native-mobile-template` but could point at a private
repository: in that case, add a repo secret (e.g. `SMOKE_TOKEN`, a PAT with
read access to the target repo) and pass it through:

```yaml
jobs:
  checks:
    uses: ./.github/workflows/checks.yml
    secrets:
      consumer-token: ${{ secrets.SMOKE_TOKEN }}
    with:
      repository: your-org/private-app
```

`secrets: inherit` is never used anywhere in this family (Part B's release
workflows follow the same rule for their own, larger secret sets) — every
secret a reusable workflow needs is declared and passed explicitly.

## Inputs, outputs and secrets per workflow

Every table below is read from the workflow's own `on.workflow_call` block —
`working-directory`, `linux-runner`, `macos-runner` and `native-cache-version`
are common to every workflow (present even when unused, "carried for
input-set consistency across the family," so all five files can share one
mental model).

### `checks.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository` | `''` (caller's own) | Consumer repository to check out |
| `ref` | `''` (let checkout resolve it) | Consumer ref (PR merge ref, branch, tag) |
| `working-directory` | `.` | Consumer directory relative to `GITHUB_WORKSPACE` |
| `linux-runner` | `ubuntu-latest` | Runner for every job in this workflow |
| `macos-runner` | `macos-26` | Unused here |
| `native-cache-version` | `v1` | Unused here |
| `typecheck` | `true` | Run `typecheck` |
| `lint` | `true` | Run `lint` |
| `format` | `true` | Run `format:check` |
| `knip` | `true` | Run `knip` |
| `spell` | `true` | Run `spell` |
| `i18n` | `false` | Run `i18n:extract`, then fail if it produced uncommitted changes |
| `graphql-codegen` | `false` | Run `codegen`, then fail if it produced uncommitted changes |
| `expo-doctor` | `true` | Run `expo-doctor` (via `pnpm exec` if a devDependency, else `pnpm dlx`) |
| `audit` | `true` | Run `pnpm audit --prod` at `audit-level` |
| `audit-level` | `high` | Minimum severity that fails the audit |
| `commitlint` | `true` | Lint the PR title (skipped for `dependabot[bot]`) |
| `commitlint-commits` | `false` | Also lint every commit's message in the PR |
| `actionlint` | `true` | Lint the consumer's `.github/workflows` |
| `shellcheck` | `true` | Lint the consumer's `scripts/` |
| `docs-only-detection` | `true` | Classify the PR as docs-only |
| `docs-globs` | `''` | Extra `\|`-joined POSIX ERE alternatives treated as docs |

Outputs: `docs-only` (`'true'` when every changed file matched the docs
globs; empty when detection is disabled). Secrets: `consumer-token` (optional).

### `unit.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | — |
| `coverage` | `true` | Run `coverage-script` and upload `coverage/`; otherwise run `test-script` |
| `test-script` | `test` | Script run when `coverage` is off |
| `coverage-script` | `test:coverage` | Script run when `coverage` is on |
| `scripts-test-script` | `test:scripts` | Script that tests `scripts/` itself; empty skips this step |
| `coverage-artifact-retention-days` | `30` | Retention for the uploaded `coverage/` artifact |

No outputs. Secrets: `consumer-token` (optional).

### `e2e.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory` | (as above) | — |
| `linux-runner` | `ubuntu-latest` | Runner for the Android jobs |
| `macos-runner` | `macos-26` | Runner for the iOS jobs |
| `native-cache-version` | `v1` | Bump to invalidate every native cache at once |
| `ios` | `false` | Run the iOS build + simulator suite (macOS runners bill at 10x) |
| `android` | `true` | Run the Android build + emulator suite |
| `xcode` | `''` | Xcode version to select (folded into the iOS cache key) |
| `android-api-level` | `34` | Emulator + system image API level |
| `maestro-version` | `2.10.0` | Maestro CLI version (kept equal to `scripts/lib/versions.sh`) |
| `maestro-flows` | `.maestro` | Flows directory, consumer-relative |
| `maestro-include-tags` / `maestro-exclude-tags` | `''` | Passed to Maestro when non-empty |
| `suite-timeout-minutes` | `10` | Per-attempt bound; the step's own timeout is this plus 5 |
| `dev-client` | `true` | Launch via the `expo-development-client` deep link, Metro `--dev-client` |
| `e2e-setup-script` / `e2e-teardown-script` | `''` | Consumer-relative hook scripts (setup: missing file is fatal; teardown: always runs) |
| `ios-artifact-name` | `ios-app` | Artifact name between `build-ios` and `ios` |
| `android-artifact-name` | `android-apk` | Artifact name between `build-android` and `android` |

Outputs: `ios-result`, `android-result` (`success`/`failure`/`cancelled`/`skipped`).
Secrets: `consumer-token` (optional).

### `web.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory` | (as above) | — |
| `linux-runner` | `ubuntu-latest` | Runner for every job |
| `macos-runner`, `native-cache-version` | (unused) | — |
| `playwright` | `true` | Run the Playwright suite against the export |
| `deploy` | `false` | Publish to GitHub Pages (pass `github.ref_type == 'tag'`) |
| `base-url` | `''` | Baked into the export via `EXPO_PUBLIC_BASE_URL` |
| `export-script` | `build:web` | Script that exports the web build |
| `export-args` | `''` | Extra flags appended to the export script |
| `output-dir` | `dist` | Consumer-relative export output directory |
| `e2e-script` | `test:e2e:web` | Script that runs the Playwright suite |
| `playwright-browsers` | `chromium` | Space-separated browsers for `playwright install` |

Outputs: `page-url` (empty unless `deploy` is true). Secrets: `consumer-token`
(optional).

### `pr-title.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | — |

No outputs. Secrets: `consumer-token` (optional). Lints `github.event.pull_request.title`
against Conventional Commits on every `edited`/`opened`/`synchronize` event.

### `pr-closed.yml`

`on.workflow_call: {}` — no inputs, outputs or secrets. The caller must grant
`permissions: actions: write` (on top of `contents: read`) for the cancel step.

## Script contract

Every toggle above calls `scripts/checks/run-script.sh NAME`, which does
`pnpm run NAME` when `package.json` has that script, else `pnpm exec NAME`
when `node_modules/.bin/NAME` exists, else fails with a message pointing back
to this doc. `i18n`, `graphql-codegen`, `expo-doctor`, `audit` and
`commitlint` have their own small wrapper scripts (also documented below) that
call a fixed name or shell out directly — their consumer-facing name is not
configurable.

Verified against `react-native-mobile-template`'s `package.json` (`pnpm run`
line for line, both repos read on the same date):

| Script name | Called by | Present in the template? |
| --- | --- | --- |
| `typecheck` | `checks.yml` (`typecheck`) | yes |
| `lint` | `checks.yml` (`lint`) | yes |
| `format:check` | `checks.yml` (`format`) | yes |
| `knip` | `checks.yml` (`knip`) | **no package.json script** — falls back to the `knip` binary in `node_modules/.bin` (present: `knip` is a devDependency), so the toggle still works via the binary path |
| `spell` | `checks.yml` (`spell`) | yes (`typos`) |
| `i18n:extract` | `scripts/checks/i18n.sh` (`i18n` toggle, off by default) | yes |
| `codegen` | `scripts/checks/codegen.sh` (`graphql-codegen` toggle, off by default) | yes |
| `expo-doctor` binary | `scripts/checks/expo-doctor.sh` (`expo-doctor` toggle) | n/a — `pnpm exec expo-doctor` (devDependency present) |
| `pnpm audit --prod` | `scripts/checks/audit.sh` (`audit` toggle) | n/a — not a package.json script, calls pnpm directly |
| commitlint binary | `scripts/checks/commitlint.sh` (`commitlint` toggle, `pr-title.yml`) | n/a — `pnpm exec commitlint` when `@commitlint/cli` is a devDependency (it is), else `npx` with a pinned fallback config |
| `test` | `unit.yml` (`test-script`, used when `coverage: false`) | yes |
| `test:coverage` | `unit.yml` (`coverage-script`, default path) | yes |
| `test:scripts` | `unit.yml` (`scripts-test-script`) | yes |
| `build:web` | `web.yml` (`export-script`) | yes |
| `test:e2e:web` | `web.yml` (`e2e-script`) | yes, **but see the Playwright/export contract below — the template's current script does not yet honor `PLAYWRIGHT_SKIP_EXPORT`** |

The template also ships `lint:fix`, `format`, `i18n:check`, `codegen:check`,
`deps:check`, `deps:audit`, `deps:licenses`, `check-bundle-secrets`,
`check-prebuild`, `test:e2e:ios`, `test:e2e:android` — none of those are
called by this family; they're local/consumer-only conveniences (`i18n.sh`
and `codegen.sh` implement their own "assert no diff" check rather than
calling the template's separate `*:check` scripts, so keep both pairs
consistent by hand if you rely on the local ones too).

## The Playwright / export contract

`web.yml`'s `build` job exports once (`export-script`) and uploads the result
as the `web-dist` artifact; the `playwright` job downloads that same artifact
into `output-dir` and runs `e2e-script` with `PLAYWRIGHT_SKIP_EXPORT=1` set in
its environment — **the point is to test the exact bytes that would be
deployed**, not a second, possibly-different export. This means the
consumer's `test:e2e:web` script must check that variable and skip its own
export when it's set:

```jsonc
// package.json — required shape for test:e2e:web
"test:e2e:web": "[ -n \"$PLAYWRIGHT_SKIP_EXPORT\" ] || pnpm build:web --dev; playwright test"
```

The template's current script (`pnpm build:web --dev && playwright test`)
does not yet branch on `PLAYWRIGHT_SKIP_EXPORT`, so today it silently
re-exports before every Playwright run in CI too — harmless (it produces the
same bytes deterministically today) but wasteful, and it stops testing "the
artifact that will be deployed" the day the export becomes non-deterministic
or `deploy: true` runs against a different `base-url` than the local export
would use. Fix it in the template's `package.json` when convenient.

## The E2E hooks contract

`e2e-setup-script` / `e2e-teardown-script` are **consumer-relative file
paths**, not package.json script names, run via `bash` by
`scripts/e2e/run-hook.sh`:

- Setup runs once, right before Metro starts waiting is done (both iOS and
  Android jobs, right after `metro-start.sh`/before Metro-wait); a
  **non-empty but missing path is fatal** (fails the job before the suite
  even attempts to run) — an empty string (`''`, the default) skips the step
  entirely.
- Teardown runs with `if: always()`, after the suite (pass or fail) and, on
  iOS, after the screen recording stops; on Android it runs inside
  `android-maestro.sh`'s own `trap ... EXIT` (recording stop → forensics →
  teardown), because the whole Android suite is one `script:` line for
  `ReactiveCircus/android-emulator-runner`.
- `self-smoke.yml` wires these to
  `scripts/e2e/ci-mock-api-up.sh` / `scripts/e2e/ci-mock-api-down.sh` —
  **paths the template repo is expected to ship** (its own mock GraphQL API
  server, started for the E2E suite and stopped after). Until the template
  ships them, `self-smoke.yml`'s `e2e` job fails at the setup step.

## iOS opt-in

iOS E2E defaults to `false` in `e2e.yml` because macOS GitHub-hosted runners
bill at 10x. Two independent ways to opt in per the `ci.yml` example above:

- Set the repo variable `E2E_IOS=true` to run iOS on every push/PR.
- Add the `e2e:ios` label to a PR to run it just for that PR (needs
  `pull_request: types: [..., labeled]` in the caller so the label itself
  triggers a run).

`macos-runner` reads the repo variable `RNW_MACOS_RUNNER` when set
(`vars.RNW_MACOS_RUNNER || 'macos-26'`), falling back to `macos-26` —
`RNW_MACOS_RUNNER` is a convention documented here and in `docs/runners.md`,
not an input any workflow defaults on its own.

## `.rnw/` ignore list for consumers

Every job self-checks-out this repo into `.rnw/` at `$GITHUB_WORKSPACE/.rnw`
(see `docs/cache-keys.md` and the `setup` action, which also adds `.rnw/` to
`.git/info/exclude` so it never shows up as untracked locally). A consumer's
own local tooling still needs to ignore it explicitly wherever it walks the
whole tree:

| Tool | Where |
| --- | --- |
| Biome | `biome.json` → `files.includes` (or the older `ignore`) with `!**/.rnw` |
| ESLint | `eslint.config.mjs` → the flat-config `ignores` array, `.rnw/**` |
| tsconfig | `tsconfig.json` → `exclude`, add `.rnw` |
| knip | `knip.json` → `ignore` (or `project`/`entry` globs that don't reach into it) |
| typos | `typos.toml` → `[files] extend-exclude`, add `.rnw/**` |
| git | `.gitignore` — not strictly required (`setup` uses `.git/info/exclude`
  instead, which is local-only and never committed), but harmless to add for
  clarity |

The template's `biome.json`, `eslint.config.mjs` and `tsconfig.json` already
carry this; `knip.json`, `typos.toml` and `.gitignore` do not yet (add them
alongside the workflow caller files).

## Gotchas encoded

Hard-won CI/E2E lessons (mostly from `blinkbitcoin/esign`), and exactly where
each one lives so a future edit doesn't quietly regress it.

| Lesson | Encoded in |
| --- | --- |
| A hung Maestro driver must never eat the job twice | `scripts/e2e/maestro-bound.sh` (`bounded_maestro`, exit `124`) + `ios-maestro.sh`/`android-maestro.sh` (retry only on a real failure, never on `124`) |
| The suite's own timeout must not race the step's `timeout-minutes` | `scripts/e2e/step-timeout.sh` (step timeout = `suite-timeout-minutes + 5`), consumed via `fromJSON(steps.timeout.outputs.minutes)` in `e2e.yml` |
| Killing Metro must kill its whole process group, not just the wrapper pid | `scripts/e2e/README.md` notes `kill -TERM -"$(cat "$RNW_OUT/metro.pid")"` (leading `-`); implemented in `metro-start.sh`/`metro-wait.sh`'s stop path |
| The first app launch must not race a cold Metro bundle | `scripts/e2e/metro-wait.sh` pre-warms `/.expo/.virtual-metro-entry.bundle?platform=...` before `app-launch.sh` runs |
| The native dependency hash must be computable before `pnpm install`, or a cache lookup blocks on an install | `scripts/ci/native-hash.sh` reads `pnpm-lock.yaml` directly via `yq` instead of `pnpm list` |
| `android-emulator-runner`'s `script:` can only run once per invocation and must be a single line | `test/workflow-shape.bats` ("every android-emulator-runner script: is a single 'bash ...' line"); `android-maestro.sh` does prepare→record→launch→suite→forensics itself for exactly this reason |
| The AVD snapshot must have dialogs suppressed or the suite hangs on a first-boot dialog | `scripts/e2e/android-emulator.sh snapshot-bake` (`hide_error_dialogs 1`, `anr_show_background 0`), cache key suffix `-hidedialogs` documents the content, not a read value |
| A crash-report scan must not pick up a stale crash from a previous job on the same runner | `scripts/e2e/collect-forensics.sh` filters iOS `DiagnosticReports` to files newer than `$RNW_RUN_START`, stamped once by `scripts/lib/e2e-env.sh` |
| `docs-only` classification must use merge-base semantics, not raw two-dot diff, so a target-branch advance doesn't retroactively flip a PR to non-docs-only | `scripts/ci/changed-class.sh` (falls back to two-dot only when `git merge-base` itself fails, with a warning) |
| `sudo`-based Linux-runner scripts (free disk, KVM) must no-op safely everywhere else (macOS, a laptop, self-hosted with different env) | `scripts/ci/free-disk.sh` / `scripts/ci/enable-kvm.sh` guard on `GITHUB_ACTIONS=true && RUNNER_OS=Linux`, overridable with `RNW_FORCE_RUNNER_SCRIPTS=1` |
| Forensics collection must never fail the job it's diagnosing | `scripts/e2e/collect-forensics.sh` (`set -uo pipefail`, no `-e`; explicit `exit 0`) |
| E2E must never run against a production app id/scheme | `scripts/e2e/README.md`: "`APP_VARIANT` must not be `production` for E2E" |
| A reusable workflow must check out *itself* at the calling job's ref, not the caller's, or `$RNW` scripts silently drift from the pinned version | Every job: `repository: ${{ job.workflow_repository }}`, `ref: ${{ job.workflow_sha }}` into `.rnw/`; enforced by `test/workflow-shape.bats` |
| A Playwright run against a web export should test the artifact that will actually deploy, not a fresh, possibly-different export | `web.yml`'s `playwright` job downloads the `build` job's `web-dist` artifact and sets `PLAYWRIGHT_SKIP_EXPORT=1` (see [above](#the-playwright--export-contract) for the consumer-side half of this contract) |
| Cancelling stale runs must not cancel the run doing the cancelling | `scripts/ci/cancel-runs.sh` excludes `$GITHUB_RUN_ID` from its own query |
