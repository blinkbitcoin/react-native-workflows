# Contributing

Start with [`AGENTS.md`](AGENTS.md) — it has the folder map, the full command
table and the rules CI enforces. This file covers the workflow around a change.

## Setup

```sh
mise trust && mise install   # shellcheck, actionlint, bats, yq, node, typos, lefthook
make hooks                   # install the git hooks (once per clone, see below)
make check                   # verify the toolchain by running every gate
```

`make hooks` installs into `.git/hooks`, which a `git worktree` **shares with
the main checkout**. So it is one command per clone rather than per worktree,
and running it from a topic worktree makes these hooks live in every worktree
of that clone — including the main one. `mise exec -- lefthook uninstall`
reverses it.

There is no `package.json` and nothing to `npm install`: every tool comes from
`.mise.toml`, and the hooks call them through `mise exec --` so a hook and CI
run the same pinned binary. The one exception is commitlint, which npx fetches
on demand with the same invocation `scripts/checks/commitlint.sh` uses in CI.

## Branching

- Branch off `main`, one logical change per branch. `main` is protected;
  nothing lands except by pull request.
- **Work in a worktree**, not by switching branches in the shared clone:
  `git worktree add ../react-native-workflows-<topic> -b <branch> origin/main`.
  Several sessions share the main checkout, and a commit made there lands on
  whatever branch someone else left checked out.
- Name the branch for the change (`ci/hooks-and-hygiene`, `fix/metro-prewarm`).
- Rebase on `main` rather than merging it back in; the squash merge discards
  the branch history anyway.

## Commits and PR titles

Conventional Commits with a closed scope list, enforced by `commitlint` in the
`commit-msg` hook and again on the PR title by `pr-title.yml`:

```
<type>(<scope>): <subject>
```

Scopes: `actions checks ci deps docs e2e lib native ota release self test
tooling web workflows` (`commitlint.config.mjs` is the source of truth).

Pull requests are **squash-merged**, so GitHub uses the **PR title** as the
commit message on `main` — and release-please reads those messages to decide
the next version and write the changelog that consumers read before moving
their pin. Mark breaking changes with `!` (`feat(workflows)!: ...`) or a
`BREAKING CHANGE:` footer, and say in the PR body what a consumer has to change.

## Before you push

```sh
make check   # shellcheck, actionlint, bats, check-versions, typos
```

The `pre-push` hook runs exactly that, and `pre-commit` runs a faster subset on
staged files (shellcheck, actionlint when anything under `.github/` is staged,
typos). They are a safety net, not a substitute: `self-ci.yml` runs the same
gate on every PR. Escape hatches exist for genuinely broken tooling
(`git commit --no-verify`, `LEFTHOOK=0 git push`), and personal additions go in
a gitignored `lefthook-local.yml` rather than in `lefthook.yml`.

## What a change usually needs

- **A script change** needs a `test/*.bats` case, with every assertion ending
  in `|| fail "..."` (see the header of `test/assertions-enforced.bats` for
  why).
- **A workflow interface change** — an input, output, secret or env var — needs
  the matching row in [`docs/consumer-guide.md`](docs/consumer-guide.md), and
  the fixtures under `test/fixtures/consumer-min/` updated in the same commit.
  `test/consumer-contract.bats` keeps the guide's examples and the fixtures
  byte-identical, and separately checks the live consumer's `on:` block when
  `RNW_CONSUMER_ROOT` points at one.
- **A tool version bump** moves `scripts/lib/versions.sh` *and* the mirrors in
  `.mise.toml` and the workflow defaults; `make check-versions` is what fails
  otherwise.
- **A new `##`-documented make target** needs a row in the `AGENTS.md` command
  table, and vice versa — `test/docs-contract.bats` checks both directions.

## Pull requests

Fill in the template checklist honestly. Keep PRs reviewable; split mechanical
churn into its own commit. If a change is breaking for a repo pinned at `@v0`,
say so in the PR body — the pin is the only thing standing between a mistake
here and every consumer's CI.

Releases are automated: release-please keeps a release PR open on `main`, and
squash-merging it cuts the version and re-points the moving `v0`/`v0.1` tags.
Never move a tag or edit a version by hand.
