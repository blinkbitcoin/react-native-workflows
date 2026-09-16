#!/usr/bin/env bash
# Removes gh-pages/badges/<branch>/ when a pull request closes, so the branch
# directory does not outlive the branch. Nothing to do - no gh-pages branch yet,
# or no directory for this branch - is success, not an error: this runs on every
# closed PR, including ones whose CI never published anything.
#
# Env: BRANCH (required). CI: the badges-cleanup job of pr-closed.yml.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/gh-pages-lib.sh"
require_cmd git

: "${BRANCH:?BRANCH is required}"
gh_pages_assert_branch "$BRANCH"

cd "$(consumer_root)"
# The unit of work, re-runnable on a moved tip - see gh_pages_push. Returns
# non-zero when the directory is not there: either nothing was ever published
# for this branch, or a competing cleanup already removed it. Modify/delete is
# the conflict a replayed commit can never resolve, which is why this is a
# function and not a straight line.
drop_badges() {
  local wt="$1"
  if [ ! -d "$wt/badges/$BRANCH" ]; then
    log "gh-pages: no badges published for $BRANCH - nothing to clean"
    return 1
  fi
  git -C "$wt" rm -rq "badges/$BRANCH"
  git -C "$wt" commit -qm "chore(ci): drop badges for closed branch $BRANCH"
}

wt="${RUNNER_TEMP:-/tmp}/gh-pages"

# CREATE=0: creating a gh-pages branch in order to delete nothing from it would
# be a surprising side effect of closing a pull request.
if ! CREATE=0 gh_pages_worktree "$wt"; then
  log "gh-pages: no such branch - nothing to clean"
  exit 0
fi
if drop_badges "$wt"; then
  gh_pages_push "$wt" drop_badges
  log "gh-pages: removed badges/$BRANCH"
fi
