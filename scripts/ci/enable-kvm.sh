#!/usr/bin/env bash
# Enable KVM acceleration for the Android emulator on a Linux GitHub runner.
# Unlike free-disk.sh this dies (rather than skipping) on a non-Linux host:
# an Android emulator job without KVM doesn't fail loudly, it just runs
# catastrophically slowly, which is worse than a clear error up front.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

[ "$(uname -s)" = "Linux" ] || die "enable-kvm.sh only runs on Linux (Android emulator acceleration); uname -s = $(uname -s)"
require_cmd sudo udevadm

echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' |
  sudo tee /etc/udev/rules.d/99-kvm4all.rules >/dev/null
sudo udevadm control --reload-rules
sudo udevadm trigger --name-match=kvm

sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
[ -n "$sdk_dir" ] || die "neither ANDROID_HOME nor ANDROID_SDK_ROOT is set"
gh_env ANDROID_SDK_DIR "$sdk_dir"
