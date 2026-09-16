#!/usr/bin/env bash
# Enable KVM acceleration for the Android emulator on a Linux GitHub-hosted
# runner. Guarded on GITHUB_ACTIONS+RUNNER_OS (not just `uname -s`) so this
# never touches udev rules or requires sudo on a developer's own machine by
# accident; a workflow author who wires an Android emulator job to a
# non-Linux runner still finds out (the emulator step itself will be
# catastrophically slow without KVM) but this script itself just skips.
# Set WORKFLOWS_FORCE_RUNNER_SCRIPTS=1 to bypass the guard for deliberate
# local/self-hosted testing.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if [ "${WORKFLOWS_FORCE_RUNNER_SCRIPTS:-}" != "1" ] &&
   { [ "${GITHUB_ACTIONS:-}" != "true" ] || [ "${RUNNER_OS:-}" != "Linux" ]; }; then
  log "enable-kvm: not a Linux GitHub Actions runner (GITHUB_ACTIONS=${GITHUB_ACTIONS:-}, RUNNER_OS=${RUNNER_OS:-}); nothing to do, skipping"
  exit 0
fi
require_cmd sudo udevadm

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$sdk_dir" ] || die "neither ANDROID_HOME nor ANDROID_SDK_ROOT is set"
gh_env ANDROID_SDK_DIR "$sdk_dir"
