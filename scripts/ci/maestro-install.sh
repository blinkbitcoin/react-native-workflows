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

# Maestro prints a first-run analytics notice before anything else, so ask it
# not to - which also stops CI reporting telemetry on every run.
export MAESTRO_CLI_NO_ANALYTICS=1

bin="$HOME/.maestro/bin/maestro"

# The first dotted number in the output, not the whole output. Comparing the
# whole string worked on any machine where maestro had run once and failed on
# every fresh runner, where the notice above is printed and the check reported
# `expected 2.10.0, got Anonymous analytics enabled...`. The env var alone
# would fix today's banner; parsing is what survives the next one.
maestro_version() {
  "$1" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

installed_version() {
  [ -x "$bin" ] || return 1
  maestro_version "$bin"
}

if [ "$(installed_version || true)" != "$MAESTRO_VERSION" ]; then
  rm -rf "$HOME/.maestro"
  # The official installer honours MAESTRO_VERSION to pin a specific release.
  MAESTRO_VERSION="$MAESTRO_VERSION" bash -c "$(curl -Lsf https://get.maestro.mobile.dev)"
fi

[ -x "$bin" ] || die "maestro install failed: $bin not found"
installed="$(maestro_version "$bin")"
[ "$installed" = "$MAESTRO_VERSION" ] ||
  die "maestro version mismatch: expected $MAESTRO_VERSION, got $installed"

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$HOME/.maestro/bin" >> "$GITHUB_PATH"
fi
