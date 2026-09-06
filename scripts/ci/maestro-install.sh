#!/usr/bin/env bash
# Install (or verify) Maestro CLI at the pinned version, then put it on PATH.
# MAESTRO_VERSION may be overridden by the caller's environment even though
# versions.sh also exports a default -- capture any pre-set value first so
# sourcing versions.sh below doesn't clobber it.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
_maestro_version_override="${MAESTRO_VERSION:-}"
source "$(dirname "$0")/../lib/versions.sh"
if [ -n "$_maestro_version_override" ]; then
  MAESTRO_VERSION="$_maestro_version_override"
fi
require_cmd curl bash

bin="$HOME/.maestro/bin/maestro"

installed_version() {
  [ -x "$bin" ] || return 1
  "$bin" --version 2>/dev/null
}

if [ "$(installed_version || true)" != "$MAESTRO_VERSION" ]; then
  rm -rf "$HOME/.maestro"
  # The official installer honours MAESTRO_VERSION to pin a specific release.
  MAESTRO_VERSION="$MAESTRO_VERSION" bash -c "$(curl -Lsf https://get.maestro.mobile.dev)"
fi

[ -x "$bin" ] || die "maestro install failed: $bin not found"
installed="$("$bin" --version)"
[ "$installed" = "$MAESTRO_VERSION" ] ||
  die "maestro version mismatch: expected $MAESTRO_VERSION, got $installed"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"
fi
