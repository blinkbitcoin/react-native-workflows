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
spell: ## typos over the whole repo
	typos
check: shellcheck actionlint test check-versions spell ## Everything self-ci runs
hooks: ## Install the git hooks (lefthook)
	mise exec -- lefthook install
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
.PHONY: shellcheck actionlint test check-versions spell check hooks help
