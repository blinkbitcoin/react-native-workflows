#!/usr/bin/env bash
# Block until a named workflow's run for a given sha has finished successfully.
#
# The point is ordering, not information: promoting a build to a store when the
# internal release workflow for the same commit is still running (or has failed)
# ships an unverified binary. So a failure or cancellation is fatal, and so is
# "no run of that workflow exists for this sha at all" - a silently-skipped gate
# is the failure mode this script exists to prevent.
#
# Usage: require-green-run.sh WORKFLOW_FILE SHA
# Env: RNW_GREEN_TIMEOUT_MINUTES (45), RNW_GREEN_DISCOVERY_MINUTES (5),
#      RNW_GREEN_POLL_SECONDS (30), GH_TOKEN.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd gh yq

workflow="${1:?usage: require-green-run.sh WORKFLOW_FILE SHA}"
sha="${2:?usage: require-green-run.sh WORKFLOW_FILE SHA}"

timeout_minutes="${RNW_GREEN_TIMEOUT_MINUTES:-45}"
discovery_minutes="${RNW_GREEN_DISCOVERY_MINUTES:-5}"
poll_seconds="${RNW_GREEN_POLL_SECONDS:-30}"

now() { date +%s; }
start="$(now)"
deadline="$((start + timeout_minutes * 60))"
discovery_deadline="$((start + discovery_minutes * 60))"

log "waiting for $workflow on $sha (timeout ${timeout_minutes}m, discovery ${discovery_minutes}m)"

while :; do
  # `|| true`: a transient API error must not fail the gate on the first blip;
  # the loop retries and the overall timeout is the real bound.
  runs="$(gh run list --workflow "$workflow" --commit "$sha" --json conclusion,status,databaseId 2>/dev/null || true)"
  count=0
  if [ -n "$runs" ]; then
    count="$(printf '%s' "$runs" | yq -r 'length // 0' 2>/dev/null || echo 0)"
  fi

  if [ "$count" -gt 0 ]; then
    status="$(printf '%s' "$runs" | yq -r '.[0].status // ""')"
    conclusion="$(printf '%s' "$runs" | yq -r '.[0].conclusion // ""')"
    run_id="$(printf '%s' "$runs" | yq -r '.[0].databaseId // ""')"
    if [ "$status" = "completed" ]; then
      case "$conclusion" in
        success)
          log "$workflow run $run_id for $sha succeeded"
          gh_output run-id "$run_id"
          exit 0
          ;;
        skipped)
          die "$workflow run $run_id for $sha was skipped - nothing verified this commit"
          ;;
        *)
          die "$workflow run $run_id for $sha concluded '$conclusion' - refusing to continue"
          ;;
      esac
    fi
    log "$workflow run $run_id is $status; polling again in ${poll_seconds}s"
  else
    if [ "$(now)" -ge "$discovery_deadline" ]; then
      die "no $workflow run found for $sha within ${discovery_minutes}m - it was never started"
    fi
    log "no $workflow run for $sha yet; polling again in ${poll_seconds}s"
  fi

  [ "$(now)" -lt "$deadline" ] || die "$workflow did not complete for $sha within ${timeout_minutes}m"
  sleep "$poll_seconds"
done
