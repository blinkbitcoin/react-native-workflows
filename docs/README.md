# Documentation index

Start here. [`docs/consumer-guide.md`](consumer-guide.md) is the contract; the
rest explain the parts of it that surprise people.

## Which doc when

| You want to... | Read |
| --- | --- |
| Call a workflow from your app repo, or look up an input, output or secret | [consumer-guide.md](consumer-guide.md) |
| Work out why a cache missed, or what invalidates one | [cache-keys.md](cache-keys.md) |
| Read what a failed (or passing) E2E run left behind | [forensics.md](forensics.md) |
| Choose a runner label, or understand the macOS bill | [runners.md](runners.md) |

## One line each

| Doc | Contents |
| --- | --- |
| [consumer-guide.md](consumer-guide.md) | Every workflow's inputs, outputs and secrets; the full caller examples; versioning and the `@v0` pin; the `.rnw/` self-checkout |
| [cache-keys.md](cache-keys.md) | Each cache's key shape, what invalidates it, and the restore/save split |
| [forensics.md](forensics.md) | The artifacts an E2E job uploads on iOS and Android, what is in each, and retention |
| [runners.md](runners.md) | Runner labels, macOS billing at 10x, self-hosted notes, KVM and disk pressure |

## Elsewhere in the repo

| Path | Contents |
| --- | --- |
| `AGENTS.md` | The canonical rules-of-the-road file for humans and coding agents. `CLAUDE.md` includes it |
| `CONTRIBUTING.md` | Setup, worktrees, commit conventions, and what a change has to carry |
| `SECURITY.md` | Private reporting, the threat model and the secrets policy |
| `README.md` | What this repo is, the 60-second caller, the workflow table, the after-push checklist |
| `scripts/e2e/README.md` | How the E2E scripts fit together on a runner |
| `docs/superpowers/` | The specs and plans this repo was built from. History, not a guide |
