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
#     the exception, so a rejected push is retried rather than treated as an
#     error - by re-applying the work on the freshly fetched tip, never by
#     replaying a commit. See gh_pages_push for why that distinction is the
#     whole of it.
#
# The consumer's own checkout stays on its own ref throughout: gh-pages is only
# ever a separate worktree.

# The one non-zero exit a re-apply callback may use to mean "there is nothing
# left to do here" - the ordinary no-op, or a competing commit that already did
# the work. Every OTHER non-zero exit is a real failure and is fatal. Keeping
# those two apart is the whole point: "nothing to do" and "the commit was
# rejected" look identical from a bare exit status, and treating the second as
# the first publishes nothing, exits 0 and leaves the branch's badge silently
# stale - which is the failure mode this file's header warns about.
GH_PAGES_NOOP=3
# gh_pages_worktree with CREATE=0 and no gh-pages on the remote: nothing to
# clean, which is success. Any other non-zero is a real failure.
GH_PAGES_ABSENT=4

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
  # Environment, not `git config`: these scripts run inside the consumer's own
  # checkout, and `git config user.name` would write the bot identity into its
  # .git/config and leave it there. The GIT_* variables are per-process.
  export GIT_AUTHOR_NAME="${GH_PAGES_USER_NAME:-github-actions[bot]}"
  export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
  export GIT_AUTHOR_EMAIL="${GH_PAGES_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
  # A runner is reused and a job may publish more than once, so a leftover
  # worktree at DIR (or a stale registration for a directory already deleted)
  # would make `git worktree add` fail on the second call.
  rm -rf "$dir"
  git worktree prune
  # The local gh-pages ref is scratch state for one push and nothing else. A
  # failed push leaves it behind, and since the branch still does not exist on
  # the remote, the orphan path below would then die with "a branch named
  # 'gh-pages' already exists" on every later run in this checkout - permanently,
  # until someone creates the branch by hand. The rm -rf and prune above
  # guarantee no worktree still holds it.
  git branch -q -D gh-pages 2>/dev/null || true
  if git fetch -q origin gh-pages 2>/dev/null; then
    # --detach first, then -B: a plain `worktree add <dir> origin/gh-pages`
    # DWIMs a local branch and fails outright if one already exists.
    git worktree add -q --detach "$dir" origin/gh-pages
    git -C "$dir" checkout -q -B gh-pages origin/gh-pages
  else
    # GH_PAGES_ABSENT, not a bare 1: a caller that treats every non-zero as
    # "the branch does not exist" would read a git failure as nothing-to-do and
    # exit green with the work undone - the same class of bug as the no-op
    # convention below.
    [ "${CREATE:-1}" = 1 ] || return "$GH_PAGES_ABSENT"
    git worktree add -q --detach "$dir" HEAD
    git -C "$dir" checkout -q --orphan gh-pages
    # --orphan keeps the index and the working tree of the commit it came from;
    # without these two the first badge commit would also publish a copy of the
    # consumer's source tree.
    git -C "$dir" rm -rfq --cached .
    git -C "$dir" clean -fdxq
  fi
}

# gh_pages_push DIR REDO - push gh-pages; on rejection reset to the freshly
# fetched tip and call REDO DIR to re-do the work there, then push again.
#
# Re-doing rather than rebasing is the whole point. Badge files are *derived*
# content: they have no merge semantics, so replaying our commit onto a
# competing one conflicts the moment the two touch the same path - which is
# precisely the interesting race (two publishes for one branch; a PR-close
# cleanup against that branch's in-flight publish). A replayed commit that
# conflicts can never converge however often it is retried, and `-X theirs`
# resolves only the content half, never modify/delete. Re-applying the copy (or
# the removal) onto whatever is now on the branch always converges, and gives
# the semantics a badge should have: last writer wins, per file, without
# discarding anything the other job wrote.
#
# REDO returns GH_PAGES_NOOP to mean "nothing left to do on this tip" - the
# competing commit already did it - which ends the run green rather than pushing
# an empty commit or burning the retry budget. Any other non-zero exit is a real
# failure (a refused commit, an unwritable path) and is fatal here.
#
# GH_PAGES_PUSH_ATTEMPTS / GH_PAGES_RETRY_DELAY exist so the bats suite does not
# have to sleep through the real backoff.
gh_pages_push() {
  local dir="$1" redo="$2" attempt rc attempts="${GH_PAGES_PUSH_ATTEMPTS:-5}" delay="${GH_PAGES_RETRY_DELAY:-2}"
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if git -C "$dir" push -q origin gh-pages; then
      return 0
    fi
    log "gh-pages: push attempt $attempt of $attempts was rejected; re-applying onto origin/gh-pages"
    sleep "$((attempt * delay))"
    git -C "$dir" fetch -q origin gh-pages || continue
    git -C "$dir" reset -q --hard origin/gh-pages
    # `|| rc=$?` rather than `; rc=$?`: a bare simple command would abort the
    # whole script under errexit before its status could be inspected.
    rc=0
    "$redo" "$dir" || rc=$?
    case "$rc" in
      0) ;;
      "$GH_PAGES_NOOP")
        log "gh-pages: nothing left to do on the new tip"
        return 0
        ;;
      *) die "the gh-pages re-apply step failed (exit $rc)" ;;
    esac
  done
  die "could not push gh-pages in $attempts attempts"
}
