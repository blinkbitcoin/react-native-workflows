# react-native-workflows

Reusable GitHub Actions workflows and bash scripts for building, testing, and
releasing React Native (Expo) apps: checks (typecheck/lint/format/knip/spell/
i18n/codegen/expo-doctor/audit/actionlint/shellcheck/commitlint), unit tests
with coverage, E2E (Maestro on iOS simulators and Android emulators, with
native-build caching), web export + Playwright + GitHub Pages, PR hygiene
(cancel-on-close, PR-title linting). Consumed by
`blinkbitcoin/react-native-mobile-template` and similar projects — see
**[docs/consumer-guide.md](docs/consumer-guide.md)** for the full contract.

## 60-second start

Add to your app repo's `.github/workflows/ci.yml`:

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request: { types: [opened, synchronize, reopened, labeled] }
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
```

Every job checks your app out, then checks *this repo* out into `.rnw/` at
the exact ref/sha that defines the running job, then runs its scripts through
`$RNW` — you never reference anything under `scripts/` or
`.github/actions/` directly. Full caller examples (`web.yml`, `pr-closed.yml`,
`pr-title.yml`) and every input/output/secret table:
[docs/consumer-guide.md](docs/consumer-guide.md).

## Workflows

| Workflow | Purpose |
| --- | --- |
| `checks.yml` | typecheck/lint/format/knip/spell/i18n/codegen/expo-doctor/audit/actionlint/shellcheck/commitlint toggles + docs-only classification |
| `unit.yml` | jest with coverage upload |
| `e2e.yml` | Maestro E2E on cached iOS simulator builds and Android emulator builds |
| `web.yml` | Expo web export, Playwright suite, GitHub Pages deploy |
| `pr-closed.yml` | cancels in-flight runs for a closed PR's head sha |
| `pr-title.yml` | Conventional Commits lint on the PR title |
| `self-ci.yml` | this repo's own CI (actionlint, shellcheck, bats, check-versions, spell) |
| `self-smoke.yml` | runs the family against a real consumer (dispatch + weekly cron) |
| `self-release.yml` | release-please + moving major/minor tag |

Cache keys: [docs/cache-keys.md](docs/cache-keys.md). Forensics artifacts:
[docs/forensics.md](docs/forensics.md). Runner notes (macOS billing,
self-hosted, KVM, disk): [docs/runners.md](docs/runners.md).

## After push

- Every job self-checks-out this repo into `.rnw/` via
  `repository: ${{ job.workflow_repository }}`, `ref: ${{ job.workflow_sha }}`
  (the job context's fields for the reusable workflow file that defines the
  current job, not the caller). **After pushing any change to a workflow under
  `.github/workflows/`, watch the first real CI run on a consumer and confirm
  the `.rnw` checkout step actually resolves to
  `blinkbitcoin/react-native-workflows` at the ref/sha that defines the
  running job** — a regression here would silently check out the wrong repo
  (or the consumer's own repo) into `.rnw` and break every downstream step
  that references `$RNW`.
- **Create the GitHub repo** (`blinkbitcoin/react-native-workflows`) and push
  `main`.
- **Tag the first release**: either merge release-please's first PR (it opens
  automatically on the first push to `main` once `self-release.yml` runs), or
  tag `v0.1.0` by hand and let `self-release.yml`'s `major-tag` job move `v0`
  and `v0.1` to it. Consumers pin `@v0` (see
  [Versioning](docs/consumer-guide.md#versioning)) until `1.0.0`, when `@v1`
  becomes available.
- **Run `self-smoke.yml`** (`workflow_dispatch`) once the target consumer
  (`blinkbitcoin/react-native-mobile-template` by default) exists and has the
  `scripts/e2e/ci-mock-api-{up,down}.sh` hooks the smoke `e2e` job depends on
  — confirm all three jobs (`checks`, `unit`, `e2e`) go green before relying
  on the weekly cron.
- **Set `E2E_IOS`** as a repo variable on any consumer that should run the
  iOS suite by default (`vars.E2E_IOS == 'true'` in its `ci.yml`) — remember
  macOS runners bill at 10x, so opt in deliberately per consumer.
