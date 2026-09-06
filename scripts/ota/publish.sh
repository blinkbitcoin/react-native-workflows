#!/usr/bin/env bash
# Publish the exported OTA update to a channel at a rollout percentage.
#
# Usage: publish.sh CHANNEL ROLLOUT
# Env: OTA_CLI_VERSION (required - the pinned eoas version), OTA_ENABLED,
#      OTA_PUBLISH_TOKEN.
#
# OTA_ENABLED is checked here as well as at the workflow level. The workflow
# guard (`if: inputs.ota-enabled`) is the one that normally applies; this one
# catches a hand-run of the script and a caller that wired the input to the
# wrong job.
#
# FLAGS ARE UNVERIFIED OFFLINE: `--branch`, `--rollout-percentage` and
# `--non-interactive` are what the OTA runbook specifies for `eoas`, but no
# network was available to check them against the pinned OTA_CLI_VERSION. Confirm
# `npx eoas@$OTA_CLI_VERSION publish --help` when the version is first pinned in
# a real environment, and fix this call plus docs/consumer-guide.md together.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"
require_cmd npx

channel="${1:?usage: publish.sh CHANNEL ROLLOUT}"
rollout="${2:?usage: publish.sh CHANNEL ROLLOUT}"
: "${OTA_CLI_VERSION:?publish.sh needs OTA_CLI_VERSION pinned (never publish from an unpinned CLI)}"

if [ "${OTA_ENABLED:-false}" != "true" ]; then
  log "OTA_ENABLED is not 'true' - skipping publish to $channel"
  exit 0
fi

case "$rollout" in
  '' | *[!0-9]*) die "ROLLOUT must be an integer percentage 0-100 (got '$rollout')" ;;
esac
[ "$rollout" -ge 0 ] && [ "$rollout" -le 100 ] || die "ROLLOUT must be between 0 and 100 (got '$rollout')"

[ -d "$RNW_OTA_DIR" ] || die "no export at $RNW_OTA_DIR - run scripts/ota/export.sh first"

root="$(consumer_root)"
cd "$root"

group "ota publish ($channel @ ${rollout}%)"
npx "eoas@$OTA_CLI_VERSION" publish \
  --branch "$channel" \
  --rollout-percentage "$rollout" \
  --non-interactive
endgroup
