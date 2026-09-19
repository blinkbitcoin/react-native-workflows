#!/usr/bin/env bash
# Start self-ci.yml on the release PR's branch, by name.
#
# release-please opens its PR with GITHUB_TOKEN, and GitHub creates a
# pull_request run for that PR but never gives it a job - it is marked failed
# the moment the PR merges. workflow_dispatch is the one event GitHub still
# fires for work done with that token, so this is how the PR gets a CI run
# that actually executes. The red run stays beside it until the release PR
# is opened by the RELEASE_TAGGER App instead (self-release.yml).
#
# The branch is read here, in the shell, not with fromJSON() in the step's
# `env:`: the runner validates a step's env expressions even when its `if` is
# false, and fromJSON('') is a template error (it failed the template's
# release job on its first no-PR push).
#
# Usage: dispatch-release-pr-ci.sh
# Env: PR_JSON (release-please's `pr` output), GH_TOKEN, GH_REPO
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd gh jq
: "${GH_REPO:?GH_REPO not set (owner/name)}"

[ -n "${PR_JSON:-}" ] || die "PR_JSON is empty: release-please reported a PR but passed no pr output"
branch="$(jq -r '.headBranchName // empty' <<<"$PR_JSON")" \
  || die "PR_JSON is not valid JSON: $PR_JSON"
[ -n "$branch" ] || die "release-please's pr output has no headBranchName: $PR_JSON"

log "dispatching self-ci.yml on $branch"
gh workflow run self-ci.yml --repo "$GH_REPO" --ref "$branch"
