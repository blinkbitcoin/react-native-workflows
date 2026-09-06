#!/usr/bin/env bash
# Extract a value out of `expo config --json --type public`, caching the JSON
# per consumer so repeated calls in one CI job don't re-spawn Metro/expo-cli.
# EXPO_CONFIG_JSON overrides the source entirely (used by unit tests to feed
# a fixture without running expo).
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

refresh=false
key=""
for arg in "$@"; do
  case "$arg" in
    --refresh) refresh=true ;;
    *) key="$arg" ;;
  esac
done
[ -n "$key" ] || die "usage: expo-config.sh [--refresh] KEY"

if [ -n "${EXPO_CONFIG_JSON:-}" ]; then
  json_file="$EXPO_CONFIG_JSON"
  [ -f "$json_file" ] || die "EXPO_CONFIG_JSON not found: $json_file"
else
  require_cmd pnpm yq shasum
  root="$(consumer_root)"
  cache_key=$(printf '%s' "$root" | shasum -a 256 | cut -c1-16)
  json_file="${RUNNER_TEMP:-/tmp}/rnw-expo-config-$cache_key.json"
  if [ "$refresh" = true ] || [ ! -f "$json_file" ]; then
    (cd "$root" && pnpm exec expo config --json --type public) > "$json_file"
  fi
fi

case "$key" in
  ios.scheme-name)
    name=$(yq -r '.name' "$json_file")
    [ "$name" != "null" ] || die "expo config has no .name in $json_file"
    printf '%s\n' "$name" | tr -dc 'A-Za-z0-9\n'
    ;;
  *)
    value=$(yq -r ".$key // \"\"" "$json_file")
    [ -n "$value" ] || die "expo config key not found: $key"
    printf '%s\n' "$value"
    ;;
esac
