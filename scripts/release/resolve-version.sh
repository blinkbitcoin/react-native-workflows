#!/usr/bin/env bash
# Resolve the version and build number for a release run.
#
# This is this repo's own copy of the consumer's scripts/release/resolve-version.sh
# and MUST keep the same contract: it prints
#
#   APP_VERSION=X.Y.Z
#   APP_BUILD_NUMBER=N
#
# on stdout, writes `version` / `build-number` to $GITHUB_OUTPUT and exports
# APP_VERSION / APP_BUILD_NUMBER into $GITHUB_ENV. A consumer that ships its own
# copy and this one must never disagree, or a tag build and an OTA build of the
# same commit get different version strings.
#
# Version, first match wins:
#   1. a `vX.Y.Z` tag pointing at HEAD (the tag build itself)
#   2. a version inside $RELEASE_PR_TITLE (the release-please PR being built)
#   3. a version inside the title of the open `autorelease: pending` PR (via gh)
#   4. the newest stable `vX.Y.Z` tag with its patch component bumped by one
#   5. 0.0.1 when the repo has no stable version tag at all (0.0.0, bumped)
#
# Prerelease tags (`v1.2.3-rc.1`) are ignored *entirely*, at every step: they
# never win at HEAD and never seed the patch bump. A repository that has only
# ever cut release candidates therefore starts at 0.0.1 - which is what the
# template's copy does, and keeping the two identical is the whole point.
#
# Build number: first-parent commit count + $BUILD_NUMBER_OFFSET (default 1000).
# First-parent on purpose: a merge of a long-lived branch must not jump the
# build number by that branch's whole history, and App Store Connect / Play
# both reject a build number that ever goes backwards.
#
# Usage: resolve-version.sh [dir]   (default: the consumer root)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd git

dir="${1:-}"
[ -n "$dir" ] || dir="$(consumer_root)"
[ -d "$dir" ] || die "resolve-version.sh: no such directory: $dir"
cd "$dir"

# `|| true` throughout: every one of these is an optional source, and with
# `set -o pipefail` a no-match grep would otherwise abort the script.
extract_version() { printf '%s' "${1:-}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true; }

version=""
origin=""

tag="$(git tag --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
if [ -n "$tag" ]; then
  version="${tag#v}"
  origin="tag at HEAD ($tag)"
fi

if [ -z "$version" ] && [ -n "${RELEASE_PR_TITLE:-}" ]; then
  version="$(extract_version "$RELEASE_PR_TITLE")"
  [ -z "$version" ] || origin="RELEASE_PR_TITLE"
fi

# The GH_TOKEN gate matches the template's copy: without a token `gh pr list`
# fails anyway, and on a self-hosted runner an unauthenticated call can block on
# an interactive auth prompt instead of failing fast.
if [ -z "$version" ] && [ -n "${GH_TOKEN:-}" ] && command -v gh >/dev/null 2>&1; then
  title="$(gh pr list --state open --label 'autorelease: pending' --json title --jq '.[0].title' 2>/dev/null || true)"
  version="$(extract_version "$title")"
  [ -z "$version" ] || origin="open 'autorelease: pending' PR title"
fi

if [ -z "$version" ]; then
  last="$(git tag --list 'v*' --sort=-v:refname 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
  if [ -n "$last" ]; then
    base="${last#v}"
    origin="patch bump of the newest stable tag ($last)"
  else
    # 0.0.0 rather than a literal default, so the "no tags yet" case goes
    # through the same bump and lands on 0.0.1.
    base="0.0.0"
    origin="patch bump of 0.0.0 (no stable v* tag in this repository)"
  fi
  IFS=. read -r major minor patch <<< "$base"
  version="$major.$minor.$((patch + 1))"
fi

# Belt and braces: every branch above assigns, so an empty version here means
# one of them silently produced nothing rather than that no source matched.
[ -n "$version" ] || die "could not resolve a version (no tag, no release PR title, no v* tag)"

count="$(git rev-list --count --first-parent HEAD)"
offset="${BUILD_NUMBER_OFFSET:-1000}"
case "$offset" in
  '' | *[!0-9]*) die "BUILD_NUMBER_OFFSET must be a non-negative integer (got '$offset')" ;;
esac
build="$((count + offset))"

log "version $version from $origin; build $build ($count first-parent commits + offset $offset)"
printf 'APP_VERSION=%s\n' "$version"
printf 'APP_BUILD_NUMBER=%s\n' "$build"
gh_output version "$version"
gh_output build-number "$build"
gh_env APP_VERSION "$version"
gh_env APP_BUILD_NUMBER "$build"
