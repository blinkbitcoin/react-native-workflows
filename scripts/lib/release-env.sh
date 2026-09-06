#!/usr/bin/env bash
# Shared env contract for scripts/release and scripts/ota. Source it after
# common.sh; do not execute.
# shellcheck shell=bash

# Where every release artifact this family produces is staged. Mirrors
# scripts/lib/e2e-env.sh's RNW_OUT so a job that does both keeps one directory.
RNW_OUT="${RNW_OUT:-${RUNNER_TEMP:-/tmp}/rnw}"
# Fastlane reads this to decide where to drop the .ipa/.aab it builds.
RNW_OUTPUT_DIR="${RNW_OUTPUT_DIR:-$RNW_OUT}"
RNW_RELEASE_META_DIR="${RNW_RELEASE_META_DIR:-$RNW_OUT/release-meta}"
RNW_OTA_DIR="${RNW_OTA_DIR:-$RNW_OUT/ota}"
# Where the artifacts a release job downloads are staged for release-assets.sh.
RNW_ASSETS_DIR="${RNW_ASSETS_DIR:-$RNW_OUT/assets}"
export RNW_OUT RNW_OUTPUT_DIR RNW_RELEASE_META_DIR RNW_OTA_DIR RNW_ASSETS_DIR
mkdir -p "$RNW_OUT"

# Publish the directories to $GITHUB_ENV so a later step's `with:` block can
# interpolate ${{ env.RNW_RELEASE_META_DIR }} without re-running a script.
# gh_env_once's guard is file-based, so this dedupes across the separate
# processes that each step in one job is.
gh_env_once RNW_OUT "$RNW_OUT"
gh_env_once RNW_OUTPUT_DIR "$RNW_OUTPUT_DIR"
gh_env_once RNW_RELEASE_META_DIR "$RNW_RELEASE_META_DIR"
gh_env_once RNW_OTA_DIR "$RNW_OTA_DIR"
gh_env_once RNW_ASSETS_DIR "$RNW_ASSETS_DIR"

# rnw_release_platform [ARG] -> ios|android
rnw_release_platform() {
  local p="${1:-${RNW_PLATFORM:-}}"
  case "$p" in
    ios | android) printf '%s\n' "$p" ;;
    *) die "platform must be ios or android (got '${p}')" ;;
  esac
}

# rnw_fingerprint PLATFORM -> the @expo/fingerprint hash for that platform.
#
# RNW_FP_IOS / RNW_FP_ANDROID short-circuit the computation. That is not only a
# test seam: a job that already computed the fingerprint in an earlier step
# (expo-prepare does) passes it down instead of paying for a second, slower and
# possibly *different* run - fingerprint input includes node_modules, so the
# same commit can hash differently after an unrelated install.
#
# The CLI is @expo/fingerprint's `fingerprint` bin (verified against the
# installed version): `fingerprint fingerprint:generate --platform ios`, run in
# the consumer root so the consumer's fingerprint.config.js is picked up
# automatically. It prints a JSON object carrying `.hash`; a bare-hash output
# from an older version is still accepted.
#
# `npx --no`, not `npx --yes`: the bin must come from the consumer's own
# devDependency. `--yes` would happily install some unrelated npm package
# called "fingerprint" and hash the app with it.
rnw_fingerprint() {
  local platform override out root
  platform="$(rnw_release_platform "${1:-}")"
  case "$platform" in
    ios) override="${RNW_FP_IOS:-}" ;;
    android) override="${RNW_FP_ANDROID:-}" ;;
  esac
  if [ -n "$override" ]; then printf '%s\n' "$override"; return 0; fi

  require_cmd npx
  root="$(consumer_root)"
  out="$(cd "$root" && npx --no fingerprint fingerprint:generate --platform "$platform")" ||
    die "fingerprint:generate failed for $platform (is @expo/fingerprint a devDependency of the consumer?)"
  case "$out" in
    *'{'*)
      require_cmd yq
      out="$(printf '%s' "$out" | yq -r '.hash // ""')"
      ;;
    *)
      out="$(printf '%s\n' "$out" | tr -d '[:space:]')"
      ;;
  esac
  [ -n "$out" ] || die "could not read a fingerprint hash for $platform out of fingerprint:generate's output"
  printf '%s\n' "$out"
}
