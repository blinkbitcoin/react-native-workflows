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
      # iOS is opt-in (macOS runners bill at 10x): set the repo variable
      # E2E_IOS=true for every run, or label a single PR `e2e:ios` (the
      # `labeled` trigger above is what makes the label alone start a run).
      ios: ${{ vars.E2E_IOS == 'true' || contains(github.event.pull_request.labels.*.name, 'e2e:ios') }}
      macos-runner: ${{ vars.RNW_MACOS_RUNNER || 'macos-26' }}
      dev-client: true
      e2e-setup-script: scripts/e2e/ci-mock-api-up.sh
      e2e-teardown-script: scripts/e2e/ci-mock-api-down.sh
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
  pull_request:
    types: [opened, synchronize, reopened]
  release:
    types: [published]
permissions:
  contents: read
concurrency:
  group: web-${{ github.ref }}
  cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}
jobs:
  web:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/web.yml@v0
    permissions:
      contents: read
      # The called workflow's `deploy` job needs these; a called job can only
      # narrow the caller's token, never widen it, so they are granted here.
      pages: write
      id-token: write
    with:
      # PRs export a dev build (fast smoke); a published release exports the
      # production bundle that actually gets deployed to Pages.
      # The non-empty value MUST sit in the `&&` slot: GitHub's `&&` yields the
      # first falsy operand and `||` the first truthy one, so
      # `cond && '' || '--dev'` evaluates to '--dev' on BOTH branches (the empty
      # string is falsy) and would quietly deploy a dev bundle.
      export-args: ${{ github.event_name != 'release' && '--dev' || '' }}
      deploy: ${{ github.event_name == 'release' }}
```

Notes on the `web.yml` caller:

- **The deploy trigger is `release: published`, not a tag push.**
  `github.ref_type == 'tag'` is not a usable signal here: a `pull_request`- or
  `push`-triggered run never sets it to `tag`, and a bare tag push carries no
  release notes; keying on `github.event_name == 'release'` makes "what gets
  deployed" exactly "what was published".
- **The GitHub-expression pitfall.** In GitHub expressions `&&` yields its
  first falsy operand and `||` its first truthy one, and the empty string
  `''` is falsy — so the ternary idiom `cond && A || B` only works when `A`
  is truthy. `github.event_name != 'release' && '' || '--dev'` returns
  `'--dev'` on *both* branches. Always put the non-empty value in the `&&`
  slot and the empty one in the `||` slot, as above.
- **`permissions` on the job, not just the workflow.** A called workflow's
  jobs can only narrow the caller's token, never widen it, so `pages: write`
  and `id-token: write` (needed by `web.yml`'s `deploy` job) must be granted
  on the calling job. `contents: read` is repeated there because naming
  `permissions:` at all resets the unnamed scopes to `none`.

```yaml
# .github/workflows/pr-closed.yml
name: pr-closed
on:
  pull_request:
    types: [closed]
permissions:
  contents: read
  actions: write # required: pr-closed.yml's cancel job needs this to cancel runs
jobs:
  pr-closed:
    uses: blinkbitcoin/react-native-workflows/.github/workflows/pr-closed.yml@v0
```

```yaml
# .github/workflows/pr-title.yml
name: pr-title
on:
  pull_request:
    types: [edited]
permissions:
  contents: read
jobs:
  pr-title:
    # `edited` also fires for a body-only edit; only re-lint when the title
    # itself changed (`opened`/`synchronize` are already covered by ci.yml's
    # checks.yml `commitlint` toggle, which lints the same PR title).
    if: github.event.changes.title != null
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
| `release-checks` | `false` | Install Ruby (`ruby/setup-ruby@v1`, `bundler-cache: true`) and run the consumer's `check:release` script — the Fastfile/Gemfile and release-config validation behind the template's `make check-release`. Off by default because a repo with no release setup has no such script |
| `docs-only-detection` | `true` | Classify the PR as docs-only |
| `docs-globs` | `''` | Extra `\|`-joined POSIX ERE alternatives **added to** the built-in docs pattern (`^docs/\|\.md$\|^LICENSE$\|^\.github/ISSUE_TEMPLATE/\|^\.github/PULL_REQUEST_TEMPLATE`), not a replacement for it |

Outputs: `docs-only` (`'true'` when every changed file matched the docs
globs; empty when detection is disabled). Secrets: `consumer-token` (optional).

### `unit.yml`

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | — |
| `coverage` | `true` | Run `coverage-script` and upload `coverage/`; otherwise run `test-script` |
| `test-script` | `test` | Script run when `coverage` is off |
| `coverage-script` | `test:coverage` | Script run when `coverage` is on. Passing `coverage: true` with an **empty** `coverage-script` silently falls back to `test-script` (`${{ inputs.coverage && inputs.coverage-script \|\| inputs.test-script }}`) and then uploads an empty `coverage/`; leave the default or set a real script name |
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
| `native-extra-globs` | `''` | Space-separated consumer-relative shell globs whose file contents join the native dependency hash (see [`docs/cache-keys.md`](cache-keys.md)) |
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
| `deploy` | `false` | Publish to GitHub Pages (pass `github.event_name == 'release'` from a `release: published` caller; the calling job must grant `pages: write` + `id-token: write`) |
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

No outputs. Secrets: `consumer-token` (optional). Lints
`github.event.pull_request.title` against Conventional Commits on whatever
`pull_request` event the caller wires it to. `checks.yml`'s `commitlint`
toggle already lints the same title on `opened`/`synchronize`, so the caller
above only adds `edited` (guarded by `github.event.changes.title != null`, since
`edited` also fires for a body-only edit).

### `pr-closed.yml`

`on.workflow_call: {}` — no inputs, outputs or secrets. The caller must grant
`permissions: actions: write` (on top of `contents: read`) for the cancel step.

## Release workflows

Six more reusable workflows cover the release path: version/notes preparation,
signed store builds, arbitrary fastlane lanes, the GitHub release, and OTA
publishing. They are strictly opt-in — nothing in `ci.yml` calls them — and
they follow every rule the workflows above do: `permissions: contents: read` at
the top, no `concurrency` (the caller owns it), self-checkout into `.rnw/`,
every `run:` a single `bash "$RNW/scripts/..."` line, and **every secret
declared `required: false`** so a caller only passes the ones its stage needs.

The pipeline they compose into:

```
expo-prepare ──► expo-build-ios     ──┐
             └─► expo-build-android ──┴─► github-release ──► fastlane-lane (store upload/promote)
                                                          └─► expo-ota-publish
```

`expo-prepare` is the only job that decides *what* the release is; every later
job is handed `version` / `build-number` and the `release-meta` artifact rather
than recomputing them, so a re-run of a single stage can never disagree with
the stage before it.

### `expo-prepare.yml`

Resolves the version and build number, computes both native fingerprints,
writes `build-info.json` and the store notes, and uploads them as the
`release-meta` artifact.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | The consumer checkout uses `fetch-depth: 0` — version resolution reads `v*` tags and counts first-parent commits, and both are empty in a shallow clone |
| `build-number-offset` | `1000` | Added to the first-parent commit count. Raise it, never lower it: App Store Connect and Play both permanently reject a build number that goes backwards |
| `notes-locales` | `en` | Locales handed to the consumer's `scripts/release/notes.mjs` |
| `stage` | `internal` | Written to `build-info.json`'s `stage` |
| `release-body-file` | `''` | Consumer-relative file holding a release body; switches note generation to `--from-body` |
| `release-tag` | `''` | Existing release tag whose **body** becomes the store notes, fetched with `gh release view`. It also becomes the checked-out ref and the gated/stamped commit — see [Preparing from a release tag](#preparing-from-a-release-tag) |
| `build-env` | `{}` | Non-secret build environment — see [`build-env`](#build-env) |
| `require-green-workflow` | `''` | Workflow file name (e.g. `release-internal.yml`) that must have concluded `success` for the **resolved target sha** (the `release-tag` commit when `release-tag` is set, else `github.sha`) before preparing. Empty disables the gate. The gate step runs **before** `Setup` (so a red upstream fails before anything is installed), which means it uses the `gh` and `yq` from the runner image — true of GitHub-hosted `ubuntu-latest`, not necessarily of a self-hosted `linux-runner` |
| `release-meta-artifact` | `release-meta` | Artifact name for `build-info.json`, `store-notes.json`, `notes-store.txt`, `notes.md` |

Outputs: `version`, `build-number`, `fp-ios`, `fp-android`, `sha` (the commit
the release was prepared from). Secrets: `consumer-token`, `ANTHROPIC_API_KEY`
and `OPENAI_API_KEY` (all optional — the two API keys are only needed when the
consumer's `notes.mjs` drafts store notes with an LLM; the provider, model and
base URL are non-secret and belong in `build-env`).

> **Every caller of `expo-prepare.yml` must grant `actions: read` on the calling
> job**, on top of `contents: read`:
>
> ```yaml
>   prepare:
>     uses: blinkbitcoin/react-native-workflows/.github/workflows/expo-prepare.yml@v0
>     permissions:
>       contents: read
>       actions: read
> ```
>
> The `prepare` job declares `actions: read` (for `gh run list` in the
> `require-green-workflow` gate) and job-level `permissions:` **cannot be
> conditional** — the request is made on every call, whether or not
> `require-green-workflow` is set. A caller that grants only `contents: read`
> fails validation with *"is requesting 'actions: read', but is only allowed
> 'actions: none'"* before a single step runs.

### `expo-build-ios.yml`

Prebuild → pods → `fastlane ios build` → `fastlane ios verify`, on
`macos-runner`.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | `macos-runner` is the one that matters here |
| `native-extra-globs` | `''` | Extra globs folded into the native dependency hash (see [`docs/cache-keys.md`](cache-keys.md)) |
| `xcode` | `''` | Sets `DEVELOPER_DIR` to `/Applications/Xcode_<v>.app/Contents/Developer` and is folded into the Pods cache key |
| `environment` | `''` | GitHub Environment gating the build (secrets + approvals); empty means none |
| `version` / `build-number` | **required** | `APP_VERSION` / `APP_BUILD_NUMBER`; wire them to `expo-prepare`'s outputs |
| `stage` | `internal` | Passed through as `RNW_STAGE` |
| `ios-bundle-id` / `ios-scheme` / `android-package` | **required** | `IOS_BUNDLE_ID` / `IOS_SCHEME` / `ANDROID_PACKAGE`. All three are required **on the iOS build too** — see [The five Fastfile contract variables](#the-five-fastfile-contract-variables) |
| `verify` | `true` | Run the `ios verify` lane after `build` |
| `release-meta-artifact` | `release-meta` | Artifact downloaded for `build-info.json` and the store notes |
| `ipa-artifact` / `dsym-artifact` | `ios-ipa` / `ios-dsym` | Upload names |
| `build-env` | `{}` | Non-secret build environment, published before prebuild — see [`build-env`](#build-env) |

No outputs. Secrets (all optional): `consumer-token`, `MATCH_PASSWORD`,
`MATCH_GIT_URL`, `MATCH_GIT_BASIC_AUTHORIZATION`, `ASC_KEY_ID`,
`ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`.

### `expo-build-android.yml`

Prebuild → `fastlane android build` → `fastlane android verify`, on
`linux-runner`.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | — |
| `environment` | `''` | GitHub Environment gating the build |
| `version` / `build-number` | **required** | `APP_VERSION` / `APP_BUILD_NUMBER` |
| `stage` | `internal` | `RNW_STAGE` |
| `android-package` / `ios-bundle-id` / `ios-scheme` | **required** | `ANDROID_PACKAGE` / `IOS_BUNDLE_ID` / `IOS_SCHEME`. The two iOS ids are required **on the Android build too** — see [The five Fastfile contract variables](#the-five-fastfile-contract-variables) |
| `verify` | `true` | Run the `android verify` lane after `build` |
| `release-meta-artifact` | `release-meta` | Artifact downloaded for `build-info.json` and the store notes |
| `aab-artifact` / `apk-artifact` / `mapping-artifact` | `android-aab` / `android-apk` / `android-mapping` | Upload names |
| `mapping-path` | `android/app/build/outputs/mapping/**/mapping.txt` | Consumer-relative glob for the mapping file. Override it when the consumer uses a non-default variant output directory — the upload is `if-no-files-found: warn`, so a wrong path yields a green build and permanently unreadable Play crash reports |
| `bundletool-version` | `1.17.2` | bundletool release downloaded before the lane runs (the `android build` lane derives the universal APK from the .aab with it, and no runner image ships it). Kept equal to `scripts/lib/versions.sh` by `scripts/self/check-versions.sh` |
| `bundletool-sha256` | `''` | Expected sha256 of the jar; empty skips verification. Google publishes no checksum file alongside the release, so pinning the bytes is opt-in |
| `build-env` | `{}` | Non-secret build environment, published before prebuild — see [`build-env`](#build-env). Put `ANDROID_UPLOAD_CERT_SHA256` here: the `android verify` lane forwards it to `verify-android.sh` as `--cert-sha256`, which turns "the aab is signed" into "the aab is signed by the expected key" |

No outputs. Secrets (all optional): `consumer-token`,
`ANDROID_UPLOAD_KEYSTORE_BASE64`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`,
`ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD`,
`PLAY_SERVICE_ACCOUNT_JSON`. The apk and the mapping file upload with
`if: !cancelled()` — without the mapping, every Play crash report for that
build is permanently unreadable, so it must survive a failed `verify`.

### `fastlane-lane.yml`

One lane, one job. This is what every post-build store action goes through:
uploads, promotions, staged rollouts, halts.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | `linux-runner`/`macos-runner` are carried for consistency; `runner` is what selects this job's runner |
| `platform` | (required) | `ios` or `android` |
| `lane` | (required) | `ios build\|verify\|upload_internal\|promote_beta\|release_production\|phased\|upload_symbols`, `android build\|verify\|upload_internal\|promote_beta\|release_production\|rollout\|halt` |
| `lane-args` | `''` | Space-separated fastlane `key:value` arguments (e.g. `percentage:0.1`) |
| `runner` | `ubuntu-latest` | An iOS lane that touches Xcode needs a macOS runner; a store-API-only lane does not |
| `environment` | `''` | GitHub Environment gating the lane (this is where a production approval belongs) |
| `env-json` | `{}` | Flat JSON object published into the lane's environment. **Configuration only** — the values are printed to the log; credentials belong in `secrets:` |
| `artifacts` | `''` | Artifact name or glob pattern downloaded (merged) into `$RNW_ASSETS_DIR` before the lane runs |
| `version` / `build-number` | **required** | `APP_VERSION` / `APP_BUILD_NUMBER` |
| `ios-bundle-id` / `ios-scheme` / `android-package` | **required** | All three on every lane, both platforms — see [The five Fastfile contract variables](#the-five-fastfile-contract-variables) |
| `ruby` | `true` | Install Ruby (leave on unless the consumer has no Gemfile) |
| `timeout-minutes` | `45` | Raise it for a lane that waits on App Store Connect processing |
| `build-env` | `{}` | Non-secret build environment — see [`build-env`](#build-env) |

No outputs. Secrets (all optional): `consumer-token`, the full iOS + Android
credential set listed under the two build workflows, and the App Review set —
`APP_REVIEW_EMAIL`, `APP_REVIEW_FIRST_NAME`,
`APP_REVIEW_LAST_NAME`, `APP_REVIEW_PHONE`,
`APP_REVIEW_DEMO_USER`, `APP_REVIEW_DEMO_PASSWORD`, `APP_REVIEW_NOTES`. Those
seven are **secrets, not `build-env` or `env-json` values**: a reviewer demo
login is a real credential, and both of those inputs are printed to the log.

Their names are a cross-repo contract — the consumer's `fastlane/lanes/shared.rb`
reads them straight out of `ENV` — so a rename on either side silently stops
populating the App Store review form: `deliver` and `pilot` just receive fewer
keys, with no error. `test/workflow-shape.bats` therefore derives the expected
names from a committed copy of the template's `shared.rb`
(`test/fixtures/consumer-min/fastlane/lanes/shared.rb`) and compares the two sets
in both directions, so a rename on either side fails here instead of in a store
submission.

### `github-release.yml`

Creates or moves a GitHub release and attaches the fixed asset set.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | This workflow never checks the consumer out, so only `repository` and `linux-runner` do anything |
| `mode` | (required) | `create-prerelease`, `promote`, `latest` or `append` |
| `tag` | (required) | Release tag to create or move |
| `sha` | `''` | Commit the tag points at. **Creation only**: once the tag exists GitHub ignores a release's target commit, so a re-run after a force-push updates the release but leaves the tag where it was |
| `title` | `''` | Release title; empty keeps GitHub's default (the tag) |
| `notes-artifact` | `release-meta` | Artifact carrying the notes file |
| `notes-file` | `notes.md` | File inside that artifact used as the body (or, in `append` mode, as the appended section) |
| `assets-artifacts` | `''` | Artifact name or glob pattern whose files are attached |
| `append-title` | `Update` | Heading for the section added in `append` mode |
| `from-tag` | `''` | `promote` only: pre-release tag (e.g. `v1.2.3-build.42`) whose assets are downloaded and re-uploaded to `tag`, so the promoted release ships **the exact binaries that were tested** rather than a rebuild. `SHA256SUMS` is regenerated over the merged set |
| `delete-source` | `false` | `promote` only: delete the `from-tag` pre-release **and its tag** (`gh release delete --cleanup-tag`) — after the upload succeeded, never before, so a failed upload cannot leave the binaries nowhere. A re-run whose source is already gone continues instead of failing |

Outputs: `url`. Secrets: `RELEASE_TAGGER_APP_ID`,
`RELEASE_TAGGER_APP_PRIVATE_KEY` (both optional). When they are set the job
mints a GitHub App token with `actions/create-github-app-token@v2`; otherwise
it uses the caller's `GITHUB_TOKEN`. **That choice is not cosmetic**: a release
created with `GITHUB_TOKEN` does not trigger other workflows, so a downstream
`release: published` caller (e.g. `web.yml`'s Pages deploy) never fires. The
job declares `permissions: contents: write`, which the calling job must grant.

Assets attached in every mode, when present in the downloaded directory:
`build-info.json`, `store-notes.json`, `notes-store.txt`, `notes.md`, `*.ipa`,
`*.aab`, `*.apk`, `*.dSYM.zip`, `dsyms.zip`, `mapping.txt`, plus a freshly
computed `SHA256SUMS`. The list is fixed on purpose — a release whose asset set
varies run to run cannot be verified by a downstream script.

### `expo-ota-publish.yml`

Fingerprint gate → `expo export` → publish → manifest smoke check.

| Input | Default | Meaning |
| --- | --- | --- |
| `repository`, `ref`, `working-directory`, `linux-runner`, `macos-runner`, `native-cache-version` | (as above) | `ref` is the commit whose JS becomes the update |
| `ota-enabled` | `false` | Master switch; `false` skips the whole job. OTA is opt-in per consumer because an update reaches every installed app immediately and cannot be recalled |
| `channel` | (required) | Update channel/branch (`internal`, `beta`, `production`, …) |
| `rollout` | `0` | Rollout percentage 0–100 |
| `environment` | `''` | GitHub Environment gating the publish |
| `ota-cli-version` | `''` | Exact `eoas` version. Never leave this empty in a real caller: `scripts/ota/publish.sh` refuses to run unpinned |
| `baseline-tag` | `''` | **Required whenever `ota-enabled` is true.** Release tag whose `build-info.json` asset is the fingerprint baseline for this channel — see [The OTA fingerprint gate](#the-ota-fingerprint-gate) |
| `manifest-url` | `''` | Manifest URL fetched after publishing as a smoke check; empty skips it |
| `runtime-version` | `''` | Sent as the `expo-runtime-version` header in that check |

No outputs. Secrets: `consumer-token`, `OTA_PUBLISH_TOKEN` (both optional).

What is published is the export `scripts/ota/export.sh` wrote to `$RNW_OTA_DIR`
— the bytes the fingerprint gate vetted — not an export the CLI performs for
itself after the gate has run. That export is also uploaded as the
`ota-export-<channel>` artifact (90 days, `!cancelled()`), **source maps
included**: an OTA update is the one build whose crash reports cannot be
symbolicated from a store-side dSYM or mapping file, so those maps are the only
way to read a stack trace from it and they die with the runner otherwise.

> **Unverified against the CLI.** `scripts/ota/publish.sh` calls
> `npx eoas@$OTA_CLI_VERSION publish --branch CHANNEL --rollout-percentage N
> --input-dir $RNW_OTA_DIR --skip-bundler --non-interactive`, with
> `OTA_PUBLISH_TOKEN` exported to the CLI as `EXPO_TOKEN`. The flags and that
> variable name come from the OTA runbook (`--input-dir` only takes effect with
> `--skip-bundler`, as in `eas-cli`) and could not be checked against the CLI
> offline. Confirm all of it against `npx eoas@<pinned version> publish --help`
> the first time `ota-cli-version` is pinned in a real environment, and fix the
> script and this note together. A wrong token name fails as an auth error, not
> as a flag error.

### `build-env`

`expo-prepare.yml`, `expo-build-ios.yml`, `expo-build-android.yml` and
`fastlane-lane.yml` take a `build-env` input: a flat JSON object of **non-secret**
environment variables, published to `$GITHUB_ENV` before prebuild, the lanes and
the consumer scripts run. It is the only way a caller can get a value into those
places — nothing else in the family forwards arbitrary environment.

```yaml
    with:
      build-env: >-
        {"OTA_ENABLED":"true",
         "EXPO_UPDATES_URL":"https://updates.example.com/api/manifest",
         "EXPO_PUBLIC_API_URL":"https://api.example.com",
         "ANDROID_UPLOAD_CERT_SHA256":"AA:BB:...",
         "STORE_NOTES_INCLUDE_CHANGELOG":"true",
         "RELEASE_NOTES_LLM_PROVIDER":"anthropic",
         "RELEASE_NOTES_LLM_MODEL":"claude-sonnet-4-5"}
```

Rules, enforced by `scripts/lib/build-env.sh`:

- Keys must match `^[A-Z][A-Z0-9_]*$`; values must be scalars (a JSON boolean or
  number is coerced to its string form).
- **A key that reads as a credential is refused**, not published: anything
  ending in `_KEY`, `_TOKEN`, `_PASSWORD`, `_PASSPHRASE`, `_SECRET`,
  `_CREDENTIAL(S)`, plus a short list of known credential names. `build-env` is a
  workflow *input*: GitHub does not mask it, it appears in the run's parameters,
  and anyone who can see the run can read it. Refusing loudly is the difference
  between noticing immediately and leaking quietly.
- **A key owned by the family or by the runner is refused**: anything matching
  `RNW_*`, `GITHUB_*`, `RUNNER_*`, `ACTIONS_*`, `LD_*`, `DYLD_*`, plus `PATH`,
  `HOME` and `NODE_OPTIONS`. `build-env` is published *before* the fingerprint
  step, so `{"RNW_FP_IOS":"…"}` would hand the OTA fingerprint gate a
  caller-supplied constant to compare its baseline against, and
  `RNW_ASSETS_DIR` / `RNW_RELEASE_META_DIR` would repoint the artifact paths
  mid-job. Use the dedicated input instead.
- **A value may contain anything, newlines included.** Values reach
  `$GITHUB_ENV` through the heredoc delimiter form (`KEY<<__rnw_eof_…`), never
  as a bare `KEY=value` line — a value carrying a newline would otherwise write
  a second line that the runner reads as *another* variable (`PATH=/evil` on the
  second line of an innocent-looking repo variable), in a job that also holds
  signing credentials.
- Only key names are logged, never values.

The same rules apply to `fastlane-lane.yml`'s `env-json` input
(`scripts/release/env-json.sh`), except that its keys may be lower-case.

So `RELEASE_NOTES_LLM_PROVIDER` / `RELEASE_NOTES_LLM_MODEL` /
`OPENAI_BASE_URL` / `STORE_NOTES_INCLUDE_CHANGELOG` go in `build-env`, while
`ANTHROPIC_API_KEY` / `OPENAI_API_KEY` are declared secrets on `expo-prepare.yml`.

### Preparing from a release tag

`expo-prepare.yml`'s `release-tag` changes three things together, and they only
make sense together:

1. **The checkout ref** becomes the tag (`ref: ${{ inputs.release-tag || inputs.ref }}`).
2. **The gated and stamped commit** becomes that tag's commit, resolved by
   `scripts/release/target-sha.sh` (`git rev-parse "$TAG^{commit}"`, fetching the
   tag if the clone lacks it) and exposed as the `sha` output. `require-green-workflow`
   polls for *that* commit's run, and `build-info.json` records it.
   `github.sha` is the wrong value here: on a `release: published` event it is
   the default branch's tip when the event fired, which may already be ahead of
   the tag — so gating on it checks the wrong commit's CI and stamps the binary
   with a commit it was not built from.
3. **The store notes** come from that release's body (`gh release view TAG --json body`,
   written to `$RNW_OUT/release-body.md`), passed to the consumer's `notes.mjs`
   as `--from-body <file> --body-section`. An empty body is fatal rather than a
   silent fall back to commit subjects: the caller asked for this release's
   notes, and shipping a git log to the stores instead would look like success.

### Promoting a pre-release's assets

`github-release.yml`'s `promote` with `from-tag` downloads every asset of the
pre-release and re-uploads it to the target tag (`--clobber`), regenerating
`SHA256SUMS` over the merged set. The point is that the promoted release ships
**the same bytes that were tested**, not a rebuild from the same source — a
rebuild is a different binary, with a different signature and a different
fingerprint, and the OTA gate downstream compares fingerprints.

**This run's files win.** The carried-forward assets are staged in a scratch
directory and copied in only where this run has no file of that name. Both
sides carry `build-info.json`, `store-notes.json`, `notes-store.txt` and
`notes.md`, and the source is by definition an earlier stage: promoting `vX.Y.Z`
from `vX.Y.Z-build.N` must keep the beta run's `"stage"` and its
release-body-derived notes, not the internal run's — the more so because the
same `build-info.json` becomes the OTA gate's fingerprint baseline downstream.

**A `from-tag` that carries none of the fixed asset set is fatal**, before
anything is uploaded, before the release leaves pre-release and before
`delete-source` can delete anything. That is what a `from-tag` pointing at a
release which never received its binaries looks like — most often because
`build-number-offset` changed between stages, so the computed pre-release tag
names a release that does not exist or is empty. The old behaviour was a
silently empty promoted release plus a deleted source.

`delete-source: true` then removes the pre-release and its tag, but only after
the upload succeeded: deleting first would leave no copy of the binaries
anywhere if the upload then failed. Re-running a promote whose source is already
gone logs that and continues, so a retried job is not blocked by its own first
attempt.

### `type: number` inputs and repo variables

`build-number-offset` (`expo-prepare.yml`) and `rollout`
(`expo-ota-publish.yml`) are `type: number`. A repository variable is always a
*string*, and an **unset** one is the empty string, which is not a number — so
`with: rollout: ${{ vars.OTA_ROLLOUT }}` fails the workflow with a type error on
any repo that has not set the variable. Wrap it:

```yaml
    with:
      build-number-offset: ${{ fromJSON(vars.RNW_BUILD_NUMBER_OFFSET || '1000') }}
      rollout: ${{ fromJSON(vars.OTA_ROLLOUT || '0') }}
```

`||` yields the first truthy operand, so an unset (empty, falsy) variable falls
through to the quoted literal, and `fromJSON` turns whichever string won into a
number.

### The five Fastfile contract variables

The consumer's `Fastfile` asserts, in `before_all`, for **every lane on both
platforms**:

```ruby
require_env!(%w[APP_VERSION APP_BUILD_NUMBER IOS_BUNDLE_ID IOS_SCHEME ANDROID_PACKAGE])
```

and it rejects a value that is empty after `strip`. So the iOS build must pass
`ANDROID_PACKAGE` and the Android build must pass `IOS_BUNDLE_ID` /
`IOS_SCHEME`, however odd that reads: a lane that never touches the other
platform still fails in `before_all` before its body runs. That is why all five
are **required inputs** on `expo-build-ios.yml`, `expo-build-android.yml` and
`fastlane-lane.yml` — an empty default would look like "the Fastfile will work
it out" and fail on the first real run instead.
`test/workflow-shape.bats` asserts that every step calling `fastlane.sh`
receives all five, from the job env or its own.

Paths handed to a lane are made absolute by `scripts/release/fastlane.sh` before
`bundle exec` — `RNW_OUTPUT_DIR`, `BUILD_INFO_FILE`, `RELEASE_NOTES_STORE_FILE`,
`STORE_NOTES_JSON`, `ANDROID_UPLOAD_KEYSTORE_PATH`,
`PLAY_SERVICE_ACCOUNT_JSON_PATH`, `ASC_KEY_P8_PATH`, `BUNDLETOOL_JAR`. fastlane
runs a lane with its working directory set to `fastlane/`, not the project root,
so a relative path silently resolves one directory too deep.

Credentials reach the lane as **both** forms: `decode-secrets.sh` writes the
file and exports its path, *and* the base64 secret itself is put in the lane
step's environment. The template's `shared.rb` reads
`ENV.fetch('ASC_KEY_P8_BASE64')` with `is_key_content_base64: true`, so passing
only the decoded path would raise `KeyError` on the first App Store Connect
lane. `test/workflow-shape.bats` asserts that every secret a lane workflow
declares reaches a `fastlane.sh` step's `env:`.

### The OTA fingerprint gate

`scripts/ota/fingerprint-gate.sh` compares the fingerprint of the commit being
published against `fingerprint.ios` / `fingerprint.android` in the channel's
baseline `build-info.json`, per platform, and **dies on any mismatch**. This is the most
important guard in the release path: an update whose JS expects a native module
the installed binary does not have does not fail loudly — it crashes on launch,
for every user on the channel, and the only fix is a new store build. A
`build-info.json` without a `fingerprint` block is treated as a failure, not a
pass.

**Where the baseline comes from.** `scripts/ota/baseline.sh` downloads the
`build-info.json` **asset of the release named by `baseline-tag`**
(`gh release download "$TAG" --pattern build-info.json`), not an artifact of the
current run. This is not a stylistic choice: `actions/download-artifact` can
only resolve artifacts produced by the run it executes in, so wiring the gate to
a same-run artifact would compare the current commit's fingerprint against
itself — the gate would pass unconditionally and stop guarding anything. A
missing tag, a missing release, or a release with no `build-info.json` asset is
fatal for the same reason; there is no silent pass. Point `baseline-tag` at the
release of the store build **currently installed on that channel**.

Fingerprints are computed with the consumer's own `@expo/fingerprint`
devDependency: `npx --no fingerprint fingerprint:generate --platform <ios|android>`
run in the consumer root, so the consumer's `fingerprint.config.js` is picked
up automatically. `--no` (not `--yes`) is deliberate — the bin must come from
the consumer's lockfile, never from whatever npm package happens to be named
`fingerprint`.

### Release secrets and how they reach the lanes

`scripts/release/decode-secrets.sh` turns the base64 secrets into files under
`$RUNNER_TEMP/secrets` (mode `600` inside a `700` directory) and publishes
their paths through `$GITHUB_ENV`:

| Secret | File | Exported path variable |
| --- | --- | --- |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | `upload.keystore` | `ANDROID_UPLOAD_KEYSTORE_PATH` |
| `PLAY_SERVICE_ACCOUNT_JSON_BASE64` (or raw `PLAY_SERVICE_ACCOUNT_JSON`) | `play-service-account.json` | `PLAY_SERVICE_ACCOUNT_JSON_PATH` |
| `ASC_KEY_P8_BASE64` | `asc-key.p8` | `ASC_KEY_P8_PATH` |

It never echoes a value — only the variable name, the destination path and the
decoded byte count — and a value that decodes to zero bytes (a truncated
copy-paste, the classic failure) is fatal rather than silently producing an
empty key file.

The lanes themselves read: `APP_VERSION`, `APP_BUILD_NUMBER`,
`RELEASE_NOTES_STORE_FILE`, `IOS_BUNDLE_ID`, `IOS_SCHEME`, `ANDROID_PACKAGE`,
`BUILD_INFO_FILE`, `RNW_OUTPUT_DIR`, plus `ASC_KEY_ID`, `ASC_ISSUER_ID`,
`ASC_KEY_P8_BASE64`, `MATCH_PASSWORD`, `MATCH_GIT_URL`,
`MATCH_GIT_BASIC_AUTHORIZATION`, `ANDROID_UPLOAD_KEYSTORE_PASSWORD`,
`ANDROID_UPLOAD_KEY_ALIAS`, `ANDROID_UPLOAD_KEY_PASSWORD` and
`PLAY_SERVICE_ACCOUNT_JSON`.

### `build-info.json`

```json
{
  "sha": "…",
  "version": "1.2.3",
  "buildNumber": 1042,
  "stage": "internal",
  "fingerprint": { "ios": "…", "android": "…" },
  "expoSdk": "^54.0.0",
  "reactNative": "0.81.0",
  "workflowRunId": "…",
  "artifacts": {}
}
```

Written by `scripts/release/build-info.sh`. Adding a key is fine; renaming one
is a breaking change for the OTA gate and the store lanes alike. `expoSdk` and
`reactNative` have their range operator stripped (`^54.0.0` is written as
`54.0.0`) so the file is byte-comparable with the one the template's own
`build-info.sh` produces. `stage` falls back to `development` when `RNW_STAGE`
is unset, matching the template; `expo-prepare.yml`'s `stage` input defaults to
`internal` because a prepare run is by definition producing a build for at least
the internal track.

### Consumer-side release scripts

The workflows call three things the **consumer** owns:

| Consumer path | Called by | If missing |
| --- | --- | --- |
| `scripts/release/notes.mjs` | `scripts/release/notes.sh` (`--from-commits`, or `--from-body <file>` when `release-body-file` is set) | Falls back to an empty `store-notes.json` and the commit subjects as notes, with an `::warning::` |
| `scripts/release/verify-ios.sh <ipa-or-app> [--no-signing]` | the `ios verify` lane | The lane fails |
| `scripts/release/verify-android.sh <aab> <apk> [--cert-sha256 X]` | the `android verify` lane | The lane fails |

A consumer may also ship its own `scripts/release/resolve-version.sh`; this
repo ships an identical one (same contract: prints `APP_VERSION=` /
`APP_BUILD_NUMBER=`, writes `version` / `build-number` to `$GITHUB_OUTPUT`) and
`expo-prepare.yml` uses **this repo's copy**, so the two must never drift. The
resolution order is: a stable `vX.Y.Z` tag on HEAD → a version in
`$RELEASE_PR_TITLE` → the open `autorelease: pending` PR's title (only when
`GH_TOKEN` is set) → the newest **stable** `vX.Y.Z` tag with its patch bumped →
`0.0.1`. Prerelease tags (`v1.2.3-rc.1`) are ignored at every step: they never
win at HEAD and never seed the bump, so a repository that has only ever cut
release candidates starts at `0.0.1` rather than regressing from them.

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
| `knip` | `checks.yml` (`knip`) | **no package script; binary fallback** — falls back to the `knip` binary in `node_modules/.bin` (present: `knip` is a devDependency), so the toggle still works via the binary path. This is deliberate: a `package.json` script literally named `knip` fails `expo-doctor`'s "Check package.json for common issues" ("scripts in package.json conflict with the contents of node_modules/.bin"), and `checks.yml` runs expo-doctor too |
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
| `check:release` | `checks.yml` (`release-checks` toggle, off by default) | **opt-in** — only a consumer with a release setup ships it; the toggle stays `false` otherwise |
| `test:e2e:web` | `web.yml` (`e2e-script`) | yes (`bash scripts/e2e/web.sh`, which honors `PLAYWRIGHT_SKIP_EXPORT` — see [the Playwright / export contract](#the-playwright--export-contract)) |

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

The template implements this in `scripts/e2e/web.sh` (wired up as
`"test:e2e:web": "bash scripts/e2e/web.sh"`), which is the shape to copy —
a shell script rather than a one-liner, so the branch stays readable and the
extra arguments still pass through:

```bash
# scripts/e2e/web.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

if [ -n "${PLAYWRIGHT_SKIP_EXPORT:-}" ]; then
  echo "PLAYWRIGHT_SKIP_EXPORT set - testing the existing dist/ export"
else
  pnpm build:web --dev
fi

exec pnpm exec playwright test "$@"
```

Skip the export unconditionally when the variable is set — including locally,
where `dist/` may be stale — rather than trying to be clever about freshness:
`web.yml` guarantees the artifact it downloads is the one its own `build` job
just produced.

## The E2E hooks contract

`e2e-setup-script` / `e2e-teardown-script` are **consumer-relative file
paths**, not package.json script names, run via `bash` by
`scripts/e2e/run-hook.sh`:

- Setup runs once, right after `metro-start.sh` and before `metro-wait.sh`
  (both the iOS and the Android job); a **non-empty but missing path is
  fatal** (fails the job before the suite even attempts to run) — an empty
  string (`''`, the default) skips the step entirely.
- Teardown runs with `if: always()`, after the suite (pass or fail) and, on
  iOS, after the screen recording stops. On **both** platforms it is a normal
  workflow step on the runner host, not something the emulator-side script
  does: a host-side mock API has to be stopped on the host, and Android's
  suite runs inside `ReactiveCircus/android-emulator-runner`'s `script:`.
  (`ios-maestro.sh`/`android-maestro.sh` also honour the `RNW_E2E_SETUP_SCRIPT`
  / `RNW_E2E_TEARDOWN_SCRIPT` env variables, but nothing in CI sets those —
  they are the local-run path. Setting both the env var and the workflow input
  runs the hook twice.)
- `self-smoke.yml` wires these to
  `scripts/e2e/ci-mock-api-up.sh` / `scripts/e2e/ci-mock-api-down.sh` — the
  template ships both (its own mock GraphQL API server, started for the E2E
  suite and stopped after) and its own `ci.yml` passes the same two paths.
  A consumer that does not ship them must leave both inputs empty, or
  `e2e.yml` fails at the setup step (a non-empty but missing path is fatal).

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
  instead, which is local-only and never committed), but recommended so a
  local `.rnw/` checkout is ignored by every clone, not just CI's |

The template carries all six: `biome.json` (`files.includes` → `"!**/.rnw"`),
`eslint.config.mjs` (`ignores` → `'.rnw/**'`), `tsconfig.json` (`exclude` →
`".rnw"`), `knip.json` (`ignore` → `".rnw/**"`), `typos.toml`
(`[files] extend-exclude` → `".rnw/"`) and `.gitignore` (`/.rnw`). Copy that
set when bootstrapping a new consumer.

## Gotchas encoded

Hard-won CI/E2E lessons (mostly from `blinkbitcoin/esign`), and exactly where
each one lives so a future edit doesn't quietly regress it.

| Lesson | Encoded in |
| --- | --- |
| A hung Maestro driver must never eat the job twice | `scripts/e2e/maestro-bound.sh` (`bounded_maestro`, exit `124`) + `ios-maestro.sh`/`android-maestro.sh` (retry only on a real failure, never on `124`) |
| The suite's own timeout must not race the step's `timeout-minutes` | `scripts/e2e/step-timeout.sh` (step timeout = `suite-timeout-minutes + 5`), consumed via `fromJSON(steps.timeout.outputs.minutes)` in `e2e.yml` |
| Killing Metro must kill its whole process group, not just the wrapper pid | `scripts/e2e/README.md` notes `kill -TERM -"$(cat "$RNW_OUT/metro.pid")"` (leading `-`), which `metro-start.sh` also logs when it starts Metro; nothing kills Metro itself — the job teardown reaps the process group |
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
| A build number must never go backwards (stores reject the build forever), so a merge of a long-lived branch must not jump it either | `scripts/release/resolve-version.sh` counts `git rev-list --count --first-parent HEAD`, plus a monotonic `BUILD_NUMBER_OFFSET`; pinned by `test/resolve-version.bats` |
| An OTA update whose native fingerprint differs from the installed binary crashes every user on the channel on launch | `scripts/ota/fingerprint-gate.sh` compares per platform and dies on any mismatch (and on a `build-info.json` with no `fingerprint` block); `test/fingerprint-gate.bats` |
| A promotion must not ship a binary whose own build never went green | `scripts/release/require-green-run.sh` (polls `gh run list`; failure, cancellation, skip and "no run at all" are each fatal); `test/require-green-run.bats` |
| A decoded signing secret must never be world-readable, and a truncated one must not silently become an empty key file | `scripts/release/decode-secrets.sh` creates each file `600` inside a `700` directory *before* writing, and dies on a zero-byte decode; `test/decode-secrets.bats` |
| A release created with `GITHUB_TOKEN` does not trigger the `release: published` workflows that depend on it | `github-release.yml` mints an `actions/create-github-app-token@v2` token when `RELEASE_TAGGER_APP_ID`/`RELEASE_TAGGER_APP_PRIVATE_KEY` are set |
| An Android crash report is unreadable forever without that build's mapping file | `expo-build-android.yml` uploads `android-mapping` (and the apk) with `if: !cancelled()`, so a failed `verify` still yields them |
| An OTA gate wired to a same-run artifact silently stops guarding, because `download-artifact` only sees the current run | `scripts/ota/baseline.sh` fetches the baseline `build-info.json` from the `baseline-tag` release's **assets** via `gh release download`; a missing tag or asset is fatal |
| A lane fails in `before_all` when any of the five contract variables is empty — including the other platform's ids | All five are required inputs on the three lane-running workflows; `test/workflow-shape.bats` asserts every `fastlane.sh` step receives them |
| fastlane runs a lane with cwd = `fastlane/`, so a relative path handed to a lane resolves one directory too deep | `scripts/release/fastlane.sh` absolutises every path variable before `bundle exec` |
| A secret decoded to a file is not the same as a secret in the lane's environment — the template's lanes read `ENV.fetch('ASC_KEY_P8_BASE64')` | Both forms are passed; `test/workflow-shape.bats` asserts every declared secret reaches a `fastlane.sh` step's `env:` |
| Re-running a failed release job must not duplicate the section it appended to the release body | `scripts/release/release-assets.sh` `append` strips any section with the same heading first; `test/release-assets.bats` asserts two runs give a byte-identical body |
| A bare `[[ ]]` assertion in a bats body cannot fail the test under macOS's bash 3.2, so a security control can silently stop checking | `test/test_helper.bash` (`fail`/`contains`/`not_contains`) and the `\|\| fail` form in every release test file |
| A promoted release must ship the bytes that were tested, not a rebuild (a rebuild has a different signature and fingerprint) | `github-release.yml`'s `promote` + `from-tag` downloads the pre-release's assets and re-uploads them; `delete-source` runs only after the upload |
| `github.sha` on a `release: published` event is the default-branch tip, not the tag's commit | `scripts/release/target-sha.sh` resolves `TAG^{commit}` and feeds it to the green-run gate and `build-info.json`; exposed as `expo-prepare`'s `sha` output |
| A renamed App Review env name breaks the review form silently - deliver and pilot accept a smaller hash without erroring | `test/workflow-shape.bats` derives the names from a committed copy of the template's `fastlane/lanes/shared.rb` and compares both directions |
| A non-secret value passed as a workflow input is public, so a credential smuggled through one leaks quietly | `scripts/lib/build-env.sh` refuses keys ending in `_KEY`/`_TOKEN`/`_PASSWORD`/`_SECRET`/… and logs key names only; `test/build-env.bats` |
| An unset repo variable is `''`, which a `type: number` input rejects outright | The guide's `fromJSON(vars.X \|\| '1000')` idiom for `build-number-offset` and `rollout` |
| No runner image ships bundletool, and the `android build` lane needs it to derive the universal APK | `expo-build-android.yml` installs the pinned jar via `scripts/ci/bundletool-install.sh` before the lane runs (version kept equal to `scripts/lib/versions.sh` by `check-versions.sh`) |
