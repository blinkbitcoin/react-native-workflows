.DEFAULT_GOAL := help
SHELL := /bin/bash
shellcheck: ## shellcheck every script (bash strict)
	shellcheck -x scripts/*/*.sh
actionlint: ## Lint workflows and composite actions
	actionlint -color
test: ## bats unit tests for the pure scripts
	bats test/
check-versions: ## Fail when workflow defaults disagree with scripts/lib/versions.sh
	bash scripts/self/check-versions.sh
check: shellcheck actionlint test check-versions ## Everything self-ci runs
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-16s\033[0m %s\n", $$1, $$2}'
.PHONY: shellcheck actionlint test check-versions check help
