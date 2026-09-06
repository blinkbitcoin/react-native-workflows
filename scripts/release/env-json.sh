#!/usr/bin/env bash
# Publish the flat JSON object in $RNW_ENV_JSON into $GITHUB_ENV so a fastlane
# lane can read caller-supplied values it was not designed to take as
# arguments (APP_VARIANT, a store track name, ...).
#
# Values are printed, so this is for configuration, never for credentials - a
# secret belongs in `secrets:` and decode-secrets.sh.
#
# Usage: env-json.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

env_file="${RUNNER_TEMP:-/tmp}/rnw-env-json.env"
trap 'rm -f "$env_file"' EXIT

json="${RNW_ENV_JSON:-}"
if [ -z "$json" ] || [ "$json" = '{}' ]; then
  log "RNW_ENV_JSON is empty - nothing to publish"
  exit 0
fi
require_cmd node

# node, not yq: only node can reliably reject a non-object and coerce scalars to
# the exact strings GitHub's env file expects.
# shellcheck disable=SC2016  # the ${...} inside are JS template literals, not shell
RNW_ENV_JSON="$json" node --input-type=module -e '
const raw = process.env.RNW_ENV_JSON;
let obj;
try { obj = JSON.parse(raw); } catch (e) {
  console.error(`::error::RNW_ENV_JSON is not valid JSON: ${e.message}`);
  process.exit(1);
}
if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
  console.error("::error::RNW_ENV_JSON must be a flat JSON object");
  process.exit(1);
}
for (const [k, v] of Object.entries(obj)) {
  if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(k)) {
    console.error(`::error::RNW_ENV_JSON key is not a valid env name: ${k}`);
    process.exit(1);
  }
  if (v !== null && typeof v === "object") {
    console.error(`::error::RNW_ENV_JSON value for ${k} must be a scalar`);
    process.exit(1);
  }
  process.stdout.write(`${k}=${v === null ? "" : String(v)}\n`);
}
' > "$env_file"

while IFS= read -r line; do
  [ -n "$line" ] || continue
  log "env-json: ${line%%=*}"
  if [ -n "${GITHUB_ENV:-}" ]; then printf '%s\n' "$line" >> "$GITHUB_ENV"; fi
done < "$env_file"
