#!/usr/bin/env bash
# Maestro E2E on the booted iOS simulator.
# Needs: app installed and launched (app-launch.sh), Metro running.
# Output: $RNW_OUT/maestro/junit.xml + debug output (screenshots, per-flow logs).
# Usage: ios-maestro.sh
# No `set -e`: the suite's failure is handled here (retry, forensics), not by
# the shell exiting mid-script.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/../lib/common.sh"
source "$HERE/../lib/e2e-env.sh"
export PATH="$HOME/.maestro/bin:$PATH"
# shellcheck source=scripts/e2e/maestro-bound.sh
. "$HERE/maestro-bound.sh"
require_cmd maestro

# The iOS driver builds and installs its XCUITest runner on first use; on a
# cold simulator that regularly takes minutes.
export MAESTRO_DRIVER_STARTUP_TIMEOUT=600000

root="$(consumer_root)"
cd "$root" || exit 1
flows="$RNW_MAESTRO_FLOWS"
[ -d "$flows" ] || die "no flows directory at $root/$flows (RNW_MAESTRO_FLOWS)"
out="$RNW_OUT/maestro"
mkdir -p "$out"

trap 'rnw_run_hook RNW_E2E_TEARDOWN_SCRIPT || true' EXIT
rnw_run_hook RNW_E2E_SETUP_SCRIPT || die "RNW_E2E_SETUP_SCRIPT failed"

args=(test "$flows" --platform ios)
# Address the picked simulator explicitly: a developer Mac (and a warm runner)
# can have an Android emulator attached at the same time, and Maestro otherwise
# picks whichever device it finds first.
args+=(--udid "$(rnw_sim_udid)")
[ -f "$flows/config.yaml" ] && args+=(--config "$flows/config.yaml")
args+=(
  -e "APP_ID=$(rnw_app_id ios)"
  --debug-output "$out"
  --flatten-debug-output
  --format junit
  --output "$out/junit.xml"
)
# The consumer's config.yaml usually carries includeTags already; the env var is
# for narrowing a single run (a smoke-only PR job) without editing the config.
[ -n "${RNW_MAESTRO_INCLUDE_TAGS:-}" ] && args+=(--include-tags "$RNW_MAESTRO_INCLUDE_TAGS")
[ -n "${RNW_MAESTRO_EXCLUDE_TAGS:-}" ] && args+=(--exclude-tags "$RNW_MAESTRO_EXCLUDE_TAGS")

bound=$((RNW_SUITE_TIMEOUT_MINUTES * 60))
status=0
group "maestro test (iOS, bound ${RNW_SUITE_TIMEOUT_MINUTES}m)"
bounded_maestro "$bound" maestro "${args[@]}" || status=$?
endgroup

# A hung driver is not retried - the second attempt would only run into the
# step's timeout-minutes and cost another suite's worth of wall clock.
if [ "$status" -ne 0 ] && [ "$status" -ne 124 ]; then
  log "::warning::Maestro suite failed (status $status) - rerunning the suite once"
  status=0
  group "maestro test (iOS, retry)"
  bounded_maestro "$bound" maestro "${args[@]}" || status=$?
  endgroup
fi
exit "$status"
