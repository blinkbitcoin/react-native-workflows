#!/usr/bin/env bash
# Publish the caller's non-secret build environment ($RNW_BUILD_ENV, a flat JSON
# object) into $GITHUB_ENV, so values like OTA_ENABLED, EXPO_UPDATES_URL,
# EXPO_PUBLIC_*, ANDROID_UPLOAD_CERT_SHA256 or STORE_NOTES_INCLUDE_CHANGELOG
# reach prebuild, the fastlane lanes, the verify scripts and the notes generator.
#
# Only key names are logged, never values - the keys are what a reader needs in
# order to debug "why did this build get that flag", and a value that turned out
# to be sensitive should not be in the log because it was assumed not to be.
#
# Keys must match ^[A-Z][A-Z0-9_]*$, and a key that *looks* like a credential
# (ends in _KEY, _TOKEN, _PASSWORD, _SECRET, or is a known credential name) is
# refused outright. This input is a workflow `inputs:` value: GitHub does not
# mask it, it shows in the run's parameters, and it is trivially readable by
# anyone who can see the run. Refusing here is the difference between a caller
# noticing at once and a credential quietly ending up in a public log.
#
# Usage: source it, then rnw_publish_build_env
# shellcheck shell=bash

rnw_publish_build_env() {
  local json count
  json="${RNW_BUILD_ENV:-}"
  if [ -z "$json" ] || [ "$json" = '{}' ]; then
    log "build-env is empty - nothing to publish"
    return 0
  fi
  require_cmd node

  local env_file="${RUNNER_TEMP:-/tmp}/rnw-build-env.env"
  # shellcheck disable=SC2016  # the ${...} inside are JS template literals
  RNW_BUILD_ENV="$json" node --input-type=module -e '
const raw = process.env.RNW_BUILD_ENV;
let obj;
try { obj = JSON.parse(raw); } catch (e) {
  console.error(`::error::build-env is not valid JSON: ${e.message}`);
  process.exit(1);
}
if (obj === null || typeof obj !== "object" || Array.isArray(obj)) {
  console.error("::error::build-env must be a flat JSON object");
  process.exit(1);
}
// Anything that reads as a credential is refused rather than published: this
// value is a workflow input, which GitHub neither masks nor hides.
const SECRETISH = /(^|_)(KEY|TOKEN|PASSWORD|PASSPHRASE|SECRET|CREDENTIALS?)$/;
const NEVER = new Set([
  "PLAY_SERVICE_ACCOUNT_JSON", "ASC_KEY_P8_BASE64",
  "ANDROID_UPLOAD_KEYSTORE_BASE64", "MATCH_GIT_BASIC_AUTHORIZATION",
]);
for (const [k, v] of Object.entries(obj)) {
  if (!/^[A-Z][A-Z0-9_]*$/.test(k)) {
    console.error(`::error::build-env key is not an upper-case env name: ${k}`);
    process.exit(1);
  }
  if (SECRETISH.test(k) || NEVER.has(k)) {
    console.error(`::error::build-env key ${k} looks like a credential; pass it as a secret instead - build-env is a workflow input and is not masked`);
    process.exit(1);
  }
  if (v !== null && typeof v === "object") {
    console.error(`::error::build-env value for ${k} must be a scalar`);
    process.exit(1);
  }
  process.stdout.write(`${k}=${v === null ? "" : String(v)}\n`);
}
' > "$env_file"

  count=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    log "build-env: ${line%%=*}"
    if [ -n "${GITHUB_ENV:-}" ]; then printf '%s\n' "$line" >> "$GITHUB_ENV"; fi
    export "${line%%=*}=${line#*=}"
    count=$((count + 1))
  done < "$env_file"
  rm -f "$env_file"
  log "build-env: published $count variable(s)"
}
