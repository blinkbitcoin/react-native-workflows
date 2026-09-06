#!/usr/bin/env bash
# Materialise base64-encoded signing/store credentials as files under
# $RUNNER_TEMP/secrets (mode 600 in a 700 directory) and publish their paths
# through $GITHUB_ENV so the fastlane lanes can read them.
#
# Nothing here ever echoes a secret value: only the variable name, the target
# path and the decoded byte count reach the log. The decoded bytes go straight
# from the env var into the file, never through a subshell substitution that
# could end up in `set -x` output.
#
# Inputs (all optional; a missing one just skips that file):
#   ANDROID_UPLOAD_KEYSTORE_BASE64   -> upload.keystore            -> ANDROID_UPLOAD_KEYSTORE_PATH
#   PLAY_SERVICE_ACCOUNT_JSON_BASE64 -> play-service-account.json  -> PLAY_SERVICE_ACCOUNT_JSON_PATH
#   PLAY_SERVICE_ACCOUNT_JSON        -> same file, written verbatim when it is raw JSON
#   ASC_KEY_P8_BASE64                -> asc-key.p8                 -> ASC_KEY_P8_PATH
#
# Usage: decode-secrets.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

secrets_dir="${RNW_SECRETS_DIR:-${RUNNER_TEMP:-/tmp}/secrets}"
mkdir -p "$secrets_dir"
chmod 700 "$secrets_dir"

# macOS's base64 wants -D, GNU coreutils wants -d, and newer macOS accepts both.
# Detect once rather than guessing per call.
b64_decode() {
  if printf '' | base64 -d >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

# decode_var VAR_NAME FILENAME PATH_VAR
decode_var() {
  local var="$1" filename="$2" path_var="$3" value dest size
  value="${!var:-}"
  if [ -z "$value" ]; then
    log "$var not set - skipping $filename"
    return 0
  fi
  dest="$secrets_dir/$filename"
  # Create with the final mode before any bytes land in it, so the decoded
  # secret is never world-readable even for an instant.
  : > "$dest"
  chmod 600 "$dest"
  printf '%s' "$value" | tr -d '\n' | b64_decode > "$dest" ||
    die "$var is not valid base64"
  size="$(wc -c < "$dest" | tr -d ' ')"
  [ "$size" -gt 0 ] || die "$var decoded to an empty file"
  log "$var -> $dest ($size bytes)"
  gh_env "$path_var" "$dest"
}

# write_raw VAR_NAME FILENAME PATH_VAR - for a secret already stored as plain
# text (the Play service account is commonly pasted as raw JSON, not base64).
write_raw() {
  local var="$1" filename="$2" path_var="$3" value dest size
  value="${!var:-}"
  [ -n "$value" ] || return 0
  dest="$secrets_dir/$filename"
  : > "$dest"
  chmod 600 "$dest"
  printf '%s' "$value" > "$dest"
  size="$(wc -c < "$dest" | tr -d ' ')"
  log "$var -> $dest ($size bytes, verbatim)"
  gh_env "$path_var" "$dest"
}

group "decode secrets"
decode_var ANDROID_UPLOAD_KEYSTORE_BASE64 upload.keystore ANDROID_UPLOAD_KEYSTORE_PATH
if [ -n "${PLAY_SERVICE_ACCOUNT_JSON_BASE64:-}" ]; then
  decode_var PLAY_SERVICE_ACCOUNT_JSON_BASE64 play-service-account.json PLAY_SERVICE_ACCOUNT_JSON_PATH
else
  write_raw PLAY_SERVICE_ACCOUNT_JSON play-service-account.json PLAY_SERVICE_ACCOUNT_JSON_PATH
fi
decode_var ASC_KEY_P8_BASE64 asc-key.p8 ASC_KEY_P8_PATH
endgroup
