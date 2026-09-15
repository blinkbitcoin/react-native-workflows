#!/usr/bin/env bash
# Publishes the branch's rendered badges to gh-pages/badges/<branch>/.
#
# The consumer's render script (badges.yml's `render-script`, default
# `badges:render`) has already written coverage/badge/{unit,e2e,coverage}.svg
# and their .json siblings; this only moves them onto the branch GitHub serves
# through raw.githubusercontent.com. A badge the render script chose not to
# write - a skipped Unit writes no coverage badge - is simply not copied, so the
# one already published stays.
#
# Env: BRANCH (required), SHA (required), BADGE_DIR (default coverage/badge).
# CI: the Publish step of badges.yml.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/gh-pages-lib.sh"
require_cmd git

: "${BRANCH:?BRANCH is required}" "${SHA:?SHA is required}"
gh_pages_assert_branch "$BRANCH"

root="$(consumer_root)"
cd "$root"
badge_dir="${BADGE_DIR:-coverage/badge}"
[ -d "$badge_dir" ] || die "no badge directory at $root/$badge_dir - did the render script run?"

badges=()
while IFS= read -r file; do badges+=("$file"); done < <(
  find "$badge_dir" -maxdepth 1 -type f \( -name '*.svg' -o -name '*.json' \) | sort
)
[ "${#badges[@]}" -gt 0 ] || die "no .svg/.json badges in $root/$badge_dir - did the render script run?"

wt="${RUNNER_TEMP:-/tmp}/gh-pages"
gh_pages_worktree "$wt"
mkdir -p "$wt/badges/$BRANCH"
cp "${badges[@]}" "$wt/badges/$BRANCH/"
printf '%s\n' \
  '# CI-owned branch' \
  '' \
  'badges/<branch>/{coverage,unit,e2e}.svg (+ their .json siblings) - written by' \
  'the badges job in the CI workflow (react-native-workflows badges.yml ->' \
  'scripts/ci/publish-badges.sh) on every run; a branch directory is removed when' \
  "its pull request closes (badges-cleanup.sh). Do not edit by hand." \
  '' \
  'This branch is NOT the GitHub Pages source. Keep the Pages source set to' \
  '"GitHub Actions": the web export deploys as a Pages artifact, and the badges' \
  'are served from raw.githubusercontent.com.' > "$wt/README.md"

git -C "$wt" add -A badges README.md
if git -C "$wt" diff --cached --quiet; then
  log "gh-pages: badges for $BRANCH unchanged"
  exit 0
fi
git -C "$wt" commit -qm "chore(ci): badges for $BRANCH @ ${SHA:0:7}"
gh_pages_push "$wt"
log "gh-pages: published ${#badges[@]} file(s) to badges/$BRANCH"
