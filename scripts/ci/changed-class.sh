#!/usr/bin/env bash
# Classify a diff range as docs-only or not, so callers can skip expensive
# native builds/tests for PRs that only touch documentation.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
base="${1:-}"
head="${2:?usage: changed-class.sh BASE_SHA HEAD_SHA}"
# DOCS_GLOBS *replaces* the default pattern (the escape hatch for a consumer
# whose docs live nowhere near docs/); DOCS_GLOBS_EXTRA *adds* alternatives to
# whichever pattern is in force. checks.yml's `docs-globs` input is wired to
# DOCS_GLOBS_EXTRA, because "extra alternatives" is what it promises - passing
# it as a replacement would silently stop treating docs/ and **.md as docs and
# run the full suite on every docs-only PR.
#
# `(^|/)LICENSE$`, not `^LICENSE$`: a monorepo keeps a copy of the licence next
# to every package, and the anchored form matched only the root one - so a
# five-line copyright bump ran the whole native matrix.
default_docs_globs='^docs/|\.md$|(^|/)LICENSE$|^\.github/ISSUE_TEMPLATE/|^\.github/PULL_REQUEST_TEMPLATE'
docs_globs="${DOCS_GLOBS:-$default_docs_globs}"
# An `[ ... ] && x` one-liner would exit the script under `set -e` when the
# variable is empty (the list's status is the failing test's), so: an if.
if [ -n "${DOCS_GLOBS_EXTRA:-}" ]; then
  docs_globs="$docs_globs|$DOCS_GLOBS_EXTRA"
fi

# Every "cannot classify" path below fails OPEN: docs-only=false and exit 0, so
# the caller runs the full pipeline. Under `set -euo pipefail` an abort here
# would fail the step instead, and a red Checks job is a worse answer than a
# needlessly complete matrix. An unreadable diff must never read as "docs".
if [ -z "$base" ]; then
  gh_output docs-only false
  exit 0
fi

# github.event.before is the all-zero sha on the first push of a new branch:
# there is no previous commit to diff against.
case "$base" in
  *[!0]*) ;;
  *)
    log "::notice::base $base is the all-zero sha (first push of a branch) - running everything"
    gh_output docs-only false
    exit 0
    ;;
esac

# A force-push can leave the recorded base unreachable, and a shallow clone can
# leave it absent. `git diff` would then exit non-zero and take the step with it.
if ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  log "::notice::base $base is not reachable in this checkout - running everything"
  gh_output docs-only false
  exit 0
fi

# Use merge-base (three-dot) semantics so commits landed on the target branch
# after the PR branch forked don't leak into the diff and flip a docs-only PR
# to false. Fall back to a plain two-dot diff only when merge-base can't be
# computed (e.g. a shallow clone missing the common ancestor).
if git merge-base "$base" "$head" >/dev/null 2>&1; then
  files=$(git diff --name-only "$base...$head")
else
  log "warning: git merge-base failed for $base..$head; falling back to two-dot diff (may include unrelated target-branch changes)"
  files=$(git diff --name-only "$base" "$head")
fi
if [ -z "$files" ]; then
  gh_output docs-only false
  exit 0
fi

non_docs=$(printf '%s\n' "$files" | grep -Ev "$docs_globs" || true)
if [ -z "$non_docs" ]; then
  gh_output docs-only true
else
  gh_output docs-only false
fi
