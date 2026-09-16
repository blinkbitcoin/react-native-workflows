#!/usr/bin/env bash
# Resolve the commit this release is actually being prepared from, and publish
# it as the `sha` output plus $WORKFLOWS_SHA.
#
# With a release-tag, `github.sha` is the wrong answer: on a `release:
# published` event it is the repository's default-branch tip at the time the
# event fired, which may already be several commits ahead of the tag. Gating on
# it would check the wrong commit's CI run, and stamping it into build-info.json
# would label the binary with a commit it was not built from.
#
# Usage: target-sha.sh [TAG]   (empty TAG falls back to $GITHUB_SHA, then HEAD)
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
require_cmd git

tag="${1:-}"
root="$(consumer_root)"
cd "$root"

if [ -n "$tag" ]; then
  sha="$(git rev-parse --verify --quiet "$tag^{commit}" 2>/dev/null || true)"
  if [ -z "$sha" ]; then
    # The tag may not be in the local clone if the checkout was ref-pinned
    # rather than full; fetching it is cheaper than failing the release.
    git fetch --no-tags --depth=1 origin "refs/tags/$tag:refs/tags/$tag" >/dev/null 2>&1 || true
    sha="$(git rev-parse --verify --quiet "$tag^{commit}" 2>/dev/null || true)"
  fi
  [ -n "$sha" ] || die "tag $tag does not resolve to a commit in this checkout - check out the tag (ref: $tag) or fetch tags"
  log "release tag $tag -> $sha"
else
  sha="${GITHUB_SHA:-$(git rev-parse HEAD)}"
  log "no release tag - using $sha"
fi

gh_output sha "$sha"
gh_env WORKFLOWS_SHA "$sha"
