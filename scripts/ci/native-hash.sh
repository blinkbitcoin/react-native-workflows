#!/usr/bin/env bash
# Hash of every input the native (Xcode/Gradle) build consumes in an Expo prebuild app:
# the lockfile-resolved versions of runtime deps + native-adjacent dev deps, plus the
# config/plugin/module/patch files. A jest/eslint bump does not change it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
root="${1:-$(consumer_root)}"
require_cmd yq shasum
lock="$root/pnpm-lock.yaml"; [ -f "$lock" ] || die "no pnpm-lock.yaml in $root"
deps=$(yq -r '.importers["."].dependencies // {} | to_entries[] | (.key + "@" + .value.version)' "$lock")
devs=$(yq -r '.importers["."].devDependencies // {} | to_entries[] | select(.key | test("^(expo|@expo/|react-native|@react-native|@react-native-community|@config-plugins/|patch-package)")) | (.key + "@" + .value.version)' "$lock")
files=$(cd "$root" && find . -maxdepth 1 \( -name 'app.config.*' -o -name 'app.json' -o -name 'Gemfile.lock' -o -name '.mise.toml' -o -name 'google-services.json' -o -name 'GoogleService-Info.plist' \) -type f | sort)
dirs=$(cd "$root" && for d in plugins modules patches; do [ -d "$d" ] && find "$d" -type f | sort; done || true)
{
  printf '%s\n' "$deps" "$devs"
  for f in $files $dirs; do printf '%s ' "$f"; shasum -a 256 "$root/$f" | cut -c1-64; done
  printf 'extra=%s\n' "${NATIVE_EXTRA_GLOBS:-}"
} | shasum -a 256 | cut -c1-16
