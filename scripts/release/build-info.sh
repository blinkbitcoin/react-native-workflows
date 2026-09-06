#!/usr/bin/env bash
# Write $RNW_RELEASE_META_DIR/build-info.json - the one machine-readable record
# of what a release build actually is. Every later stage reads it: the OTA
# fingerprint gate compares against `fingerprint`, the store lanes read
# `version`/`buildNumber`, and the GitHub release ships it as an asset.
#
# Schema (fixed; adding a key is fine, renaming one is a breaking change):
#   {sha, version, buildNumber, stage, fingerprint:{ios,android},
#    expoSdk, reactNative, workflowRunId, artifacts:{}}
#
# Env: APP_VERSION, APP_BUILD_NUMBER (resolve-version.sh), FP_IOS, FP_ANDROID
# (fingerprint.sh), RNW_STAGE, GITHUB_SHA, GITHUB_RUN_ID.
# Usage: build-info.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"
require_cmd node

root="$(consumer_root)"
mkdir -p "$RNW_RELEASE_META_DIR"
dest="$RNW_RELEASE_META_DIR/build-info.json"

[ -n "${APP_VERSION:-}" ] || die "APP_VERSION is not set - run resolve-version.sh first"
[ -n "${APP_BUILD_NUMBER:-}" ] || die "APP_BUILD_NUMBER is not set - run resolve-version.sh first"

BUILD_INFO_DEST="$dest" \
  BUILD_INFO_ROOT="$root" \
  BUILD_INFO_SHA="${GITHUB_SHA:-$(git -C "$root" rev-parse HEAD 2>/dev/null || echo unknown)}" \
  BUILD_INFO_STAGE="${RNW_STAGE:-internal}" \
  node --input-type=module -e '
import { writeFileSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.env.BUILD_INFO_ROOT;
let pkg = {};
try {
  pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
} catch {
  // A consumer without a readable package.json still gets a build-info.json;
  // the two version fields are simply null rather than failing the release.
}
const dep = (name) => pkg.dependencies?.[name] ?? pkg.devDependencies?.[name] ?? null;

const info = {
  sha: process.env.BUILD_INFO_SHA,
  version: process.env.APP_VERSION,
  buildNumber: Number(process.env.APP_BUILD_NUMBER),
  stage: process.env.BUILD_INFO_STAGE,
  fingerprint: {
    ios: process.env.FP_IOS || null,
    android: process.env.FP_ANDROID || null,
  },
  expoSdk: dep("expo"),
  reactNative: dep("react-native"),
  workflowRunId: process.env.GITHUB_RUN_ID || null,
  artifacts: {},
};
writeFileSync(process.env.BUILD_INFO_DEST, JSON.stringify(info, null, 2) + "\n");
'

log "wrote $dest"
cat "$dest" >&2
