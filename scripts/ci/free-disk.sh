#!/usr/bin/env bash
# Free disk space on a Linux GitHub runner before a large native build.
# A no-op on macOS: the runner images differ enough that there is nothing
# safe or useful to prune, and an iOS/macOS caller should be able to call
# this unconditionally without a platform check of its own.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"

if [ "$(uname -s)" != "Linux" ]; then
  log "free-disk: not Linux (uname -s = $(uname -s)); nothing to free, skipping"
  exit 0
fi

df -h /

sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/.ghcup

ndk_dir="/usr/local/lib/android/sdk/ndk"
if [ -d "$ndk_dir" ]; then
  latest=$(find "$ndk_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V | tail -1)
  find "$ndk_dir" -mindepth 1 -maxdepth 1 -type d ! -name "$latest" -print0 |
    xargs -0 -r sudo rm -rf
fi

if command -v docker >/dev/null 2>&1; then
  sudo docker image prune -af || true
fi

df -h /
