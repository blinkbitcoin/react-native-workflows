#!/usr/bin/env bash
# shellcheck shell=bash
# Sourced by publish-badges.sh and badges-cleanup.sh; not executable on its own.
#
# gh-pages is the one branch this family writes to. Everything about that is
# here, because it is also the one place where a bug silently rewrites a branch
# rather than failing a check: an orphan created over an existing history, or a
# push that clobbers a concurrent one, both look like success in the log.
#
# Two properties the callers depend on:
#
#   * the branch may not exist yet. The first publish creates it as a true
#     orphan (no parent, no files carried over from the consumer's default
#     branch), so gh-pages never contains a copy of the source tree.
#   * branches publish concurrently. Two pushes racing is the normal case, not
#     the exception, so a rejected push is rebased and retried rather than
#     treated as an error.
#
# The consumer's own checkout stays on its own ref throughout: gh-pages is only
# ever a separate worktree.

# gh_pages_assert_branch NAME - a branch name that is safe as a path segment.
# BRANCH reaches these scripts from github.head_ref / github.ref_name, which a
# PR author controls, and it is used to build a directory that is then `git rm`'d
# by the cleanup script.
gh_pages_assert_branch() {
  local name="${1-}"
  case "$name" in
    '') die "BRANCH is empty" ;;
    -* | /* | */ | *..* | *//*) die "refusing to use branch name '$name' as a gh-pages path" ;;
    *[!A-Za-z0-9._/-]*) die "branch name '$name' has characters that cannot be a gh-pages path" ;;
  esac
}

# gh_pages_worktree DIR - put a gh-pages worktree at DIR, creating the branch as
# an orphan when it does not exist yet. Returns 1 without creating anything when
# CREATE=0 and the branch is missing (the cleanup script's "nothing to clean").
# Must be called from inside the consumer checkout.
gh_pages_worktree() {
  local dir="$1"
  git config user.name "${GH_PAGES_USER_NAME:-github-actions[bot]}"
  git config user.email "${GH_PAGES_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  # A runner is reused and a job may publish more than once, so a leftover
  # worktree at DIR (or a stale registration for a directory already deleted)
  # would make `git worktree add` fail on the second call.
  rm -rf "$dir"
  git worktree prune
  if git fetch -q origin gh-pages 2>/dev/null; then
    # --detach first, then -B: a plain `worktree add <dir> origin/gh-pages`
    # DWIMs a local branch and fails outright if one already exists.
    git worktree add -q --detach "$dir" origin/gh-pages
    git -C "$dir" checkout -q -B gh-pages origin/gh-pages
  else
    [ "${CREATE:-1}" = 1 ] || return 1
    git worktree add -q --detach "$dir" HEAD
    git -C "$dir" checkout -q --orphan gh-pages
    # --orphan keeps the index and the working tree of the commit it came from;
    # without these two the first badge commit would also publish a copy of the
    # consumer's source tree.
    git -C "$dir" rm -rfq --cached .
    git -C "$dir" clean -fdxq
  fi
}

# gh_pages_push DIR - push gh-pages, rebasing onto whatever landed meanwhile.
# GH_PAGES_PUSH_ATTEMPTS / GH_PAGES_RETRY_DELAY exist so the bats suite does not
# have to sleep through the real backoff.
gh_pages_push() {
  local dir="$1" attempt attempts="${GH_PAGES_PUSH_ATTEMPTS:-5}" delay="${GH_PAGES_RETRY_DELAY:-2}"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if git -C "$dir" push -q origin gh-pages; then
      return 0
    fi
    log "gh-pages: push attempt $attempt of $attempts was rejected; rebasing onto origin/gh-pages"
    if git -C "$dir" fetch -q origin gh-pages; then
      git -C "$dir" rebase -q origin/gh-pages || git -C "$dir" rebase --abort || true
    fi
    sleep "$((attempt * delay))"
  done
  die "could not push gh-pages in $attempts attempts"
}
