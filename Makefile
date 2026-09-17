.DEFAULT_GOAL := help
SHELL := /bin/bash
# `find`, not `scripts/*/*.sh`: that glob is fixed at depth 2, so a script one
# directory deeper is skipped silently. Same form as scripts/ci/lint-ci.sh.
shellcheck: ## shellcheck every script (bash strict)
	find scripts -name '*.sh' -exec shellcheck -x {} +
actionlint: ## Lint workflows and composite actions
	actionlint -color
test: ## bats unit tests for the pure scripts
	bats test/
check-versions: ## Fail when workflow defaults disagree with scripts/lib/versions.sh
	bash scripts/self/check-versions.sh
tool-versions: ## Fail when an installed tool is not the version the baseline pins
	node packages/dev-config/bin/check-tool-versions.mjs
test-package: ## node:test for packages/dev-config
	node --test "packages/dev-config/**/*.test.mjs"
spell: ## typos over the whole repo
	typos
check: shellcheck actionlint test test-package check-versions tool-versions spell ## Everything self-ci runs
# Clone-wide, not worktree-scoped: a git worktree shares .git/hooks with the
# main checkout, so this installs the hooks for every worktree of this clone.
hooks: ## Install the git hooks (lefthook) - affects the whole clone, not just this worktree
	mise exec -- lefthook install
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
.PHONY: shellcheck actionlint test test-package check-versions tool-versions spell check hooks help
