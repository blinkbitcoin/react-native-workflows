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
# The prefix test below is intentionally unanchored at the end (no trailing
# `/` or `$`), so it also matches e.g. expo-doctor and react-native-web, not
# just the packages literally named expo/react-native/etc. That's deliberate:
# most expo-*/react-native-* devDependencies are native-adjacent (config
# plugins, codegen, native modules), and the cost of a false positive here is
# only an occasional unnecessary rebuild, never a missed native change.
devs=$(yq -r '.importers["."].devDependencies // {} | to_entries[] | select(.key | test("^(expo|@expo/|react-native|@react-native|@react-native-community|@config-plugins/|patch-package)")) | (.key + "@" + .value.version)' "$lock")
files=$(cd "$root" && find . -maxdepth 1 \( -name 'app.config.*' -o -name 'app.json' -o -name 'Gemfile.lock' -o -name '.mise.toml' -o -name 'google-services.json' -o -name 'GoogleService-Info.plist' \) -type f | sort)
dirs=$(cd "$root" && for d in plugins modules patches; do [ -d "$d" ] && find "$d" -type f | sort; done || true)
{
  printf '%s\n' "$deps" "$devs"
  # Word-splitting $files/$dirs here assumes consumer paths contain no
  # spaces or glob metacharacters (true for this repo's real consumers, an
  # Expo app tree); switch to `while IFS= read -r f` if that ever changes.
  for f in $files $dirs; do printf '%s ' "$f"; shasum -a 256 "$root/$f" | cut -c1-64; done
  printf 'extra=%s\n' "${NATIVE_EXTRA_GLOBS:-}"
} | shasum -a 256 | cut -c1-16
