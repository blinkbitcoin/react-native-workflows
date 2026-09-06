#!/usr/bin/env bash
# Fetch the published manifest for a channel and assert the update server
# actually serves it.
#
# A publish that "succeeded" but serves nothing is indistinguishable from a
# working one until a user opens the app, so this fetches the manifest the
# client would fetch, with the same expo-* headers, and fails when it does not
# come back.
#
# Usage: smoke.sh CHANNEL
# Env: OTA_MANIFEST_URL (empty skips the smoke), OTA_RUNTIME_VERSION,
#      OTA_SMOKE_PLATFORM (default ios).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

channel="${1:?usage: smoke.sh CHANNEL}"
url="${OTA_MANIFEST_URL:-}"
if [ -z "$url" ]; then
  log "OTA_MANIFEST_URL is empty - skipping the manifest smoke check"
  exit 0
fi
require_cmd curl

platform="${OTA_SMOKE_PLATFORM:-ios}"
body="${RUNNER_TEMP:-/tmp}/rnw-ota-manifest"
trap 'rm -f "$body"' EXIT

# Built as an array so an unset runtime version contributes no argument at all
# (an unquoted ${VAR:+-H "..."} would word-split the header on its space).
runtime_args=()
[ -z "${OTA_RUNTIME_VERSION:-}" ] || runtime_args=(-H "expo-runtime-version: $OTA_RUNTIME_VERSION")

group "ota manifest smoke ($channel)"
code="$(curl -sS -o "$body" -w '%{http_code}' \
  -H "expo-channel-name: $channel" \
  -H "expo-platform: $platform" \
  -H "expo-protocol-version: 1" \
  -H "expo-api-version: 1" \
  "${runtime_args[@]+"${runtime_args[@]}"}" \
  -H 'accept: multipart/mixed' \
  "$url")" || die "manifest request to $url failed"
log "HTTP $code, $(wc -c < "$body" | tr -d ' ') bytes"
endgroup

[ "$code" = "200" ] || die "manifest for $channel returned HTTP $code (expected 200)"
[ -s "$body" ] || die "manifest for $channel came back empty"
log "manifest for $channel is being served"
