#!/usr/bin/env bash
# Shared env contract for scripts/native and scripts/e2e. Source it after
# common.sh; do not execute. Every variable is optional and has a default, so a
# consumer only sets what it needs to override (see scripts/e2e/README.md).
# shellcheck shell=bash

RNW_DEV_CLIENT="${RNW_DEV_CLIENT:-true}"
RNW_MAESTRO_FLOWS="${RNW_MAESTRO_FLOWS:-.maestro}"
RNW_SUITE_TIMEOUT_MINUTES="${RNW_SUITE_TIMEOUT_MINUTES:-10}"
RNW_METRO_PORT="${RNW_METRO_PORT:-8081}"
# Host-side mock API the E2E setup hook starts (the template's mock GraphQL
# server listens on 4000). Reversed into the emulator so the app's localhost
# URLs work unchanged; empty disables the reverse entirely.
RNW_MOCK_API_PORT="${RNW_MOCK_API_PORT-4000}"
RNW_OUT="${RNW_OUT:-${RUNNER_TEMP:-/tmp}/rnw}"
export RNW_DEV_CLIENT RNW_MAESTRO_FLOWS RNW_SUITE_TIMEOUT_MINUTES RNW_METRO_PORT RNW_MOCK_API_PORT RNW_OUT
mkdir -p "$RNW_OUT"

# Immutable "the run started here" stamp. collect-forensics.sh needs a fixed
# instant to select crash reports from, and metro.log cannot serve: it is
# appended throughout the run, so its mtime is the last Metro write. Created by
# whichever script sources this file first, then never touched again.
RNW_RUN_START="$RNW_OUT/run-start"
RNW_RUN_START_FRESH=
if [ ! -e "$RNW_RUN_START" ]; then
  : > "$RNW_RUN_START" 2>/dev/null && RNW_RUN_START_FRESH=1
fi
# RNW_RUN_START_FRESH says "this process created the stamp", i.e. nothing ran
# before it. A collector that stamps the run itself would select nothing at all,
# so it falls back to a time window instead.
export RNW_RUN_START RNW_RUN_START_FRESH

# Publish RNW_OUT/RNW_RUN_START to $GITHUB_ENV so every later step in the job
# (including composite actions, e.g. `forensics`'s default `path` input) can
# see them without re-sourcing this file. gh_env_once's guard is file-based
# (checks $GITHUB_ENV itself), so it dedupes across the many separate steps -
# each its own process - that source this file within one job, not just
# within one process.
gh_env_once RNW_OUT "$RNW_OUT"
gh_env_once RNW_RUN_START "$RNW_RUN_START"

# Directory holding scripts/lib, resolved from this file so callers in any
# subdirectory (scripts/native, scripts/e2e) find expo-config.sh.
RNW_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RNW_LIB_DIR

# rnw_platform [ARG] -> ios|android. Positional argument wins over RNW_PLATFORM.
rnw_platform() {
  local p="${1:-${RNW_PLATFORM:-}}"
  case "$p" in
    ios | android) printf '%s\n' "$p" ;;
    *) die "platform must be ios or android (got '${p}'); pass it as \$1 or set RNW_PLATFORM" ;;
  esac
}

rnw_expo_config() { bash "$RNW_LIB_DIR/expo-config.sh" "$1"; }

# rnw_app_id PLATFORM -> the application id under test. RNW_APP_ID wins; the
# default comes straight from the resolved Expo config, which already carries
# any variant suffix (the template's app.config.ts appends `.dev` itself), so
# nothing is appended here.
rnw_app_id() {
  if [ -n "${RNW_APP_ID:-}" ]; then printf '%s\n' "$RNW_APP_ID"; return 0; fi
  case "$(rnw_platform "${1:-}")" in
    ios) rnw_expo_config ios.bundleIdentifier ;;
    android) rnw_expo_config android.package ;;
  esac
}

rnw_scheme() { rnw_expo_config scheme; }

# rnw_ios_scheme -> the Xcode scheme/target name. Derived from the Expo config
# (`name` stripped of non-alphanumerics, which is what prebuild generates) but
# validated against the workspace prebuild actually wrote: the workspace name is
# authoritative, a disagreement is only a warning so the build still runs.
rnw_ios_scheme() {
  local root ws ws_name cfg_name
  root="$(consumer_root)"
  ws="$(find "$root/ios" -maxdepth 1 -name '*.xcworkspace' 2>/dev/null | head -1)"
  [ -n "$ws" ] || die "no ios/*.xcworkspace in $root - run prebuild.sh ios and pods.sh first"
  ws_name="$(basename "$ws" .xcworkspace)"
  cfg_name="$(rnw_expo_config ios.scheme-name)"
  if [ "$ws_name" != "$cfg_name" ]; then
    printf '::warning::expo-config scheme-name (%s) disagrees with the generated workspace (%s); using the workspace name\n' \
      "$cfg_name" "$ws_name" >&2
  fi
  printf '%s\n' "$ws_name"
}

RNW_IOS_PRODUCTS_DIR="ios/build/Build/Products/Debug-iphonesimulator"
RNW_ANDROID_APK="android/app/build/outputs/apk/debug/app-debug.apk"
export RNW_IOS_PRODUCTS_DIR RNW_ANDROID_APK

# The picked simulator is remembered in $RNW_OUT so every later step addresses
# it explicitly: `booted` is ambiguous on a developer Mac with several
# simulators up, and GITHUB_ENV does not reach a local shell.
rnw_sim_udid() {
  if [ -n "${RNW_SIM_UDID:-}" ]; then printf '%s\n' "$RNW_SIM_UDID"; return 0; fi
  [ -f "$RNW_OUT/sim-udid" ] || die "no simulator selected - run ios-simulator.sh pick first"
  cat "$RNW_OUT/sim-udid"
}

# rnw_run_hook VAR_NAME - run a consumer-relative hook script when the variable
# names one. Missing file is fatal: a silently skipped setup hook produces a
# confusing suite failure later.
rnw_run_hook() {
  local var="$1" path="${!1:-}" root
  [ -n "$path" ] || return 0
  root="$(consumer_root)"
  [ -f "$root/$path" ] || die "$var points at a missing file: $root/$path"
  log "running $var: $path"
  (cd "$root" && bash "$path")
}
