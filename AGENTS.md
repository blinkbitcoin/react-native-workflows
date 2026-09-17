# Agent guide

Reusable GitHub Actions workflows, composite actions and bash scripts for
building, testing and releasing React Native (Expo) apps. Consumers pin `@v0`
and call the workflows; nothing here is copied into their repos. The published
contract is [`docs/consumer-guide.md`](docs/consumer-guide.md) — a change to an
input, output, secret or env var is a change to every app that pins this repo.

Read this file before touching anything. `make help` is the source of truth for
commands, and `test/docs-contract.bats` fails the build if it and the table
below drift apart.

## Layout

```
.github/workflows/  the reusable workflows (workflow_call) + this repo's self-* CI
.github/actions/    composite actions (setup, maestro, forensics, free-disk, native-key)
scripts/checks/     the checks.yml steps (audit, codegen, commitlint, expo-doctor, i18n)
scripts/ci/         shared CI plumbing (changed-class, lint-ci, pnpm-install, tool-version, gh-pages badges)
scripts/e2e/        simulators, emulators, Metro, Maestro, forensics collection
scripts/native/     prebuild, pods, iOS/Android builds and packaging
scripts/ota/        expo-updates export, fingerprint gate, publish, smoke
scripts/release/    version/notes resolution, fastlane invocation, release assets
scripts/web/        web export, Playwright install and run
scripts/self/       this repo's own gates (check-versions, tag-major)
scripts/lib/        sourced bash helpers (common, versions, *-env, expo-config)
test/               the bats suite + fixtures/ (consumer callers, kept byte-identical)
docs/               consumer-guide, cache-keys, forensics, runners
```

## Commands

Every row is a make target; nothing here is run through a package manager.

| Target | |
|---|---|
| `make hooks` | Install the git hooks (lefthook, from `.mise.toml`) — clone-wide, see the worktree rule |
| `make check` | Everything self-ci runs: the five gates below |
| `make shellcheck` | shellcheck every script under `scripts/` (bash strict) |
| `make actionlint` | Lint the workflows and composite actions |
| `make test` | The bats suite over the pure scripts |
| `make check-versions` | Fail when a workflow default disagrees with `scripts/lib/versions.sh` |
| `make spell` | typos over the whole repo |
| `make help` | Show every target with its description |

## Rules of the road

- **Do all branch work in a git worktree**
  (`git worktree add ../shared-workflows-<topic> -b <branch> origin/main`),
  never by switching branches in the shared clone: several agent sessions share
  that checkout, and a commit made there lands on whatever branch another
  session left checked out. **`make hooks` is the one thing that is not
  worktree-scoped:** a worktree shares `.git/hooks` with the main checkout, so
  running it from a topic worktree makes these hooks live in every worktree of
  the clone. That is intended once this is on `main` — one `make hooks` per
  physical clone — but a branch that changes `lefthook.yml` changes what every
  sibling worktree runs. `mise exec -- lefthook uninstall` reverses it.
- **The consumer guide is the contract.** Adding, renaming or re-defaulting a
  workflow input, output or secret without the matching
  `docs/consumer-guide.md` row is a breaking change shipped silently.
  `test/consumer-contract.bats` holds the guide and the fixtures under
  `test/fixtures/consumer-min/` byte-identical — when it fails, both copies
  move together or neither does. A real consumer passes inputs of its own, so
  it is held to the fixture only where it must not diverge: its `ci.yml`
  trigger block, which is where a second docs rule (`paths-ignore`) would creep
  back in beside `checks.yml`'s classifier.
- **Shell lives in `scripts/`, never inline in a workflow.** A `run:` block of
  more than a couple of lines is unshellcheckable, untestable and unreadable in
  a run log; give it a file under the matching `scripts/<area>/` and a bats
  test. Everything under `scripts/` is `shellcheck -x` clean under
  `set -euo pipefail`.
- **Every script gets bats coverage**, and every assertion ends in
  `|| fail "..."` — bash 3.2 (macOS's `/bin/bash`) does not honour `errexit`
  for a bare `[[ ]]`, so an unguarded assertion cannot fail a test locally.
  `test/assertions-enforced.bats` enforces this.
- **Tool versions live in `scripts/lib/versions.sh`**, mirrored into
  `.mise.toml` and into workflow input defaults. Never bump one copy alone;
  `make check-versions` is what catches it.
- **Jobs check this repo out into `.workflows/`** via `job.workflow_repository` /
  `job.workflow_sha`, and reference everything through `$WORKFLOWS_DIR`. Never reference
  a path under `scripts/` or `.github/actions/` from a consumer-visible
  interface.
- **Permissions start at `contents: read`** at the top of a workflow; a job
  that needs more declares the extra scope *and* re-declares `contents: read`,
  because a job-level `permissions:` block replaces the top-level one rather
  than extending it.
- **Conventional commits with a closed scope enum**
  (`commitlint.config.mjs`): `actions checks ci deps docs e2e lib native ota
  release self test tooling web workflows`. Squash merges take the PR title as
  the commit message, so `pr-title.yml` lints the title too.
- **Releases are release-please's job.** `self-release.yml` cuts the version
  and re-points the moving `v0`/`v0.1` tags through
  `scripts/self/tag-major.sh`; never move a tag or edit a version by hand.
- **Docs ship with the code.** Adding or removing a `##`-documented make target
  without updating the command table above is a hard failure.

## Testing map

| Layer | Where | Run with |
|---|---|---|
| Pure bash scripts | `test/*.bats` | `make test` |
| Workflow and action shape (inputs, permissions, step names) | `test/workflow-shape.bats`, `test/actions-shape.bats` | `make test` |
| The consumer contract (guide ↔ fixtures ↔ real caller) | `test/consumer-contract.bats` | `make test` |
| Hooks and the docs command table | `test/hooks.bats`, `test/docs-contract.bats` | `make test` |
| Parity with the consumer's own copy of a shared script | `test/resolve-version.bats`, `test/build-info.bats`, `test/workflow-shape.bats` | `make test` **with `WORKFLOWS_TEMPLATE_DIR` set** |
| The family end to end, against a real consumer | `.github/workflows/self-smoke.yml` | `workflow_dispatch` |

Two variables point the suite at a real consumer, and both are worth setting
together — that is the configuration `self-ci.yml`'s `parity` job uses:

```sh
WORKFLOWS_TEMPLATE_DIR=~/Dev/blink/react-native-mobile-template \
WORKFLOWS_CONSUMER_ROOT=~/Dev/blink/react-native-mobile-template \
  mise exec -- bats test/
```

`WORKFLOWS_CONSUMER_ROOT` is what `consumer-contract.bats` reads; `WORKFLOWS_TEMPLATE_DIR`
is what the parity cases read. **Without them four cases skip**, saying `parity
NOT verified` rather than implying the copies agree. `WORKFLOWS_PARITY_REQUIRED=1`
turns such a skip into a failure, which is what makes the CI job honest.

## Where to look next

- What consumers may call, and with what: [`docs/consumer-guide.md`](docs/consumer-guide.md).
- Why a cache missed: [`docs/cache-keys.md`](docs/cache-keys.md).
- What a failed E2E run leaves behind: [`docs/forensics.md`](docs/forensics.md).
- Runner labels, macOS billing, KVM and disk: [`docs/runners.md`](docs/runners.md).
- Contributing workflow and PR expectations: [`CONTRIBUTING.md`](CONTRIBUTING.md).
  Vulnerability reports: [`SECURITY.md`](SECURITY.md).
