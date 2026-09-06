#!/usr/bin/env bash
# Run expo-doctor from the consumer's own devDependency pin when it has one,
# else fall back to the latest published version via pnpm dlx.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd pnpm node

root="$(consumer_root)"
cd "$root"

has_expo_doctor_dep() {
  node -e "process.exit(require('./package.json').devDependencies?.['expo-doctor'] ? 0 : 1)" 2>/dev/null
}

if has_expo_doctor_dep; then
  pnpm exec expo-doctor
else
  pnpm dlx expo-doctor@latest
fi
