#!/usr/bin/env bash
# Shared helpers for every script in this repo. Source it; do not execute.
# shellcheck shell=bash
log() { printf '%s\n' "$*" >&2; }
die() { printf '::error::%s\n' "$*" >&2; exit 1; }
group() { printf '::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
gh_output() { if [ -n "${GITHUB_OUTPUT:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; else printf '%s=%s\n' "$1" "$2"; fi; }
gh_env() { if [ -n "${GITHUB_ENV:-}" ]; then printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"; fi; export "$1=$2"; }
# gh_env_once KEY VALUE - like gh_env, but only appends to $GITHUB_ENV when no
# "KEY=" line already exists there. File-based, so it dedupes across the many
# separate steps (each its own process) that may source the same env-setup
# library within one job, not just within one process.
gh_env_once() {
  if [ -n "${GITHUB_ENV:-}" ]; then
    grep -q "^$1=" "$GITHUB_ENV" 2>/dev/null || printf '%s=%s\n' "$1" "$2" >> "$GITHUB_ENV"
  fi
  export "$1=$2"
}
# consumer_root is canonical (pwd -P) on purpose: cache `path:` matching and tar operations need stable absolute paths.
consumer_root() { local base="${GITHUB_WORKSPACE:-$PWD}"; local wd="${WORKING_DIRECTORY:-.}"; cd "$base/$wd" && pwd -P; }
require_cmd() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "missing command: $c"; done; }
