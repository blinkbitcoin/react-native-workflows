.DEFAULT_GOAL := help
SHELL := /bin/bash

# Every pinned tool (.mise.toml) is run through $(MISE), so a recipe gets the
# pinned version whoever calls make: a shell with mise activated, CI after
# mise-action, or a caller that activated nothing - a git hook run from an IDE,
# a GUI client or an agent. Otherwise the wrapping is every caller's job, and
# the one that forgets dies on `bats: No such file`. A prefix rather than an
# exported PATH: macOS ships make 3.81, which execs a simple recipe line itself
# and searches the PATH it was started with, not the one the makefile exports.
# No mise, no prefix: the tools are then the caller's to provide, as before.
MISE := $(shell command -v mise >/dev/null 2>&1 && echo 'mise exec --')

# `find`, not `scripts/*/*.sh`: that glob is fixed at depth 2, so a script one
# directory deeper is skipped silently. Same form as scripts/ci/lint-ci.sh.
shellcheck: ## shellcheck every script (bash strict)
	find scripts -name '*.sh' -exec $(MISE) shellcheck -x {} +
actionlint: ## Lint workflows and composite actions
	$(MISE) actionlint -color
test: ## bats unit tests for the pure scripts
	$(MISE) bats test/
check-versions: ## Fail when workflow defaults disagree with scripts/lib/versions.sh
	$(MISE) bash scripts/self/check-versions.sh
tool-versions: ## Fail when an installed tool is not the version the baseline pins
	$(MISE) node packages/dev-config/bin/check-tool-versions.mjs
test-package: ## node:test for packages/dev-config
	$(MISE) node --test "packages/dev-config/**/*.test.mjs"
spell: ## typos over the whole repo
	$(MISE) typos
check: shellcheck actionlint test test-package check-versions tool-versions spell ## Everything self-ci runs
# Clone-wide, not worktree-scoped: a git worktree shares .git/hooks with the
# main checkout, so this installs the hooks for every worktree of this clone.
hooks: ## Install the git hooks (lefthook) - affects the whole clone, not just this worktree
	$(MISE) lefthook install
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
.PHONY: shellcheck actionlint test test-package check-versions tool-versions spell check hooks help
