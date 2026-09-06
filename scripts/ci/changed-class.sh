#!/usr/bin/env bash
# Classify a diff range as docs-only or not, so callers can skip expensive
# native builds/tests for PRs that only touch documentation.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
base="${1:-}"
head="${2:?usage: changed-class.sh BASE_SHA HEAD_SHA}"
docs_globs="${DOCS_GLOBS:-^docs/|\.md$|^LICENSE$|^\.github/ISSUE_TEMPLATE/|^\.github/PULL_REQUEST_TEMPLATE}"

if [ -z "$base" ]; then
  gh_output docs-only false
  exit 0
fi

files=$(git diff --name-only "$base" "$head")
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
