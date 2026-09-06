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

Phase 2 is complete locally: the workflows, actions, scripts, bats suite and
docs are all here, `make check` is green, and `v0.1.0` / `v0.1` / `v0` already
exist as local tags. What is left is everything that needs a real GitHub
remote, in order:

1. **Create the GitHub repo** `blinkbitcoin/react-native-workflows` (public;
   consumers pin `@v0` by path, so it must be readable by their tokens) and
   push this branch as `main`.
2. **Push the tags.** They already exist locally — `git push --tags` publishes
   `v0.1.0` plus the moving `v0` and `v0.1`. From here on `self-release.yml`
   owns them: release-please cuts the release and its `major-tag` job re-points
   `v0`/`v0.1` via `scripts/self/tag-major.sh`. Consumers pin `@v0` (see
   [Versioning](docs/consumer-guide.md#versioning)) until `1.0.0`, when `@v1`
   becomes available.
3. **Run `self-smoke.yml`** by `workflow_dispatch`. Its target consumer
   (`blinkbitcoin/react-native-mobile-template` by default) must exist and
   ship the `scripts/e2e/ci-mock-api-{up,down}.sh` hooks the smoke `e2e` job
   wires in — the template does. Confirm all three jobs (`checks`, `unit`,
   `e2e`) go green before relying on the weekly cron.
4. **Verify the `.rnw` self-checkout on that first run.** Every job checks
   this repo out into `.rnw/` via `repository: ${{ job.workflow_repository }}`,
   `ref: ${{ job.workflow_sha }}` — the job context's fields for the reusable
   workflow file that defines the running job, not the caller. Open the
   checkout step's log and confirm it resolved to
   `blinkbitcoin/react-native-workflows` at the calling ref's sha. Do this
   again after any change to a file under `.github/workflows/`: a regression
   here would silently check out the wrong repo (or the consumer's own) into
   `.rnw` and break every step that references `$RNW`.
5. **Set the consumer repo variables.** `E2E_IOS=true` on any consumer whose
   iOS suite should run on every push/PR (macOS runners bill at 10x, so opt in
   deliberately per consumer); `RNW_MACOS_RUNNER` only if iOS should move off
   `macos-26` onto a different or self-hosted label. Both are read in the
   template's `ci.yml` as `vars.E2E_IOS` / `vars.RNW_MACOS_RUNNER`.

No secrets are needed for any of this — every workflow in this family runs on
`github.token`, and `consumer-token` is optional (only for a *private* smoke
target). The Phase 3 release secrets (signing, store credentials, EAS) belong
to the consumer and are listed in the template's own release runbook, not
here.
