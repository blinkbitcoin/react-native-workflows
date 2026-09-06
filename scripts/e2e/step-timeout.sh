#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

# GitHub Actions expressions have no arithmetic operators, so `timeout-minutes:
# ${{ inputs.suite-timeout-minutes + 5 }}` cannot be written inline. This step
# computes the per-attempt suite bound plus a margin (device teardown, forensics)
# and publishes it as the `minutes` output.
minutes="${RNW_SUITE_TIMEOUT_MINUTES:-10}"
margin="${RNW_STEP_TIMEOUT_MARGIN_MINUTES:-5}"
case "$minutes" in '' | *[!0-9]*) die "RNW_SUITE_TIMEOUT_MINUTES must be a non-negative integer (got '$minutes')" ;; esac
case "$margin" in '' | *[!0-9]*) die "RNW_STEP_TIMEOUT_MARGIN_MINUTES must be a non-negative integer (got '$margin')" ;; esac

gh_output minutes "$((minutes + margin))"
