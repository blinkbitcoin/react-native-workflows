#!/usr/bin/env bash
# Cancel any other queued/in-progress workflow run for the same commit, so a
# force-push doesn't leave stale runs racing the latest push.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd gh

: "${GH_TOKEN:?GH_TOKEN not set}"
: "${REPO:?REPO not set}"
: "${HEAD_SHA:?HEAD_SHA not set}"
self="${GITHUB_RUN_ID:-0}"

for status in queued in_progress; do
  gh api "repos/$REPO/actions/runs?head_sha=$HEAD_SHA&status=$status&per_page=100" \
    --jq ".workflow_runs[] | select(.id != $self) | \"\(.id) \(.name)\"" |
    while IFS=' ' read -r id name; do
      log "cancelling run $id ($name)"
      gh api -X POST "repos/$REPO/actions/runs/$id/cancel" >/dev/null
    done
done
