#!/usr/bin/env bash
# Produce the store-notes bundle in $RNW_RELEASE_META_DIR:
#
#   store-notes.json  {"<locale>": {"testflight","play","appstore"}}
#   notes-store.txt   the plain-text notes handed to the store lanes
#   notes.md          the human-readable release body
#
# The consumer owns the real generator (scripts/release/notes.mjs); this script
# only calls it and, when the consumer does not ship one, writes a usable
# fallback rather than failing the release: an empty store-notes.json plus the
# commit subjects as notes. A release whose notes are literally the commit log
# is a bad release note, not a broken pipeline - so it warns loudly.
#
# Env: NOTES_LOCALES (default 'en'), RELEASE_BODY_FILE (a release body, from the
# release-body-file input or fetched by release-body.sh; switches notes.mjs to
# --from-body --body-section).
# Usage: notes.sh
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"

root="$(consumer_root)"
mkdir -p "$RNW_RELEASE_META_DIR"
cd "$root"

group "release notes"
if [ -f "scripts/release/notes.mjs" ]; then
  require_cmd node
  if [ -n "${RELEASE_BODY_FILE:-}" ] && [ -f "$RELEASE_BODY_FILE" ]; then
    # --body-section: the body is a whole changelog entry (headings, links,
    # commit references); the generator takes the section a store listing can
    # actually use rather than the raw markdown.
    log "running the consumer's notes.mjs --from-body --body-section"
    NOTES_LOCALES="${NOTES_LOCALES:-en}" \
      node scripts/release/notes.mjs --from-body "$RELEASE_BODY_FILE" --body-section --out "$RNW_RELEASE_META_DIR"
  else
    log "running the consumer's notes.mjs --from-commits"
    NOTES_LOCALES="${NOTES_LOCALES:-en}" \
      node scripts/release/notes.mjs --from-commits --out "$RNW_RELEASE_META_DIR"
  fi
else
  printf '::warning::consumer has no scripts/release/notes.mjs - falling back to commit subjects; store listings will get generic notes\n' >&2
  printf '{}\n' > "$RNW_RELEASE_META_DIR/store-notes.json"
  last_tag="$(git tag --list 'v*' --sort=-v:refname 2>/dev/null | head -1 || true)"
  if [ -n "$last_tag" ]; then
    git log --no-merges --format='- %s' "$last_tag..HEAD" > "$RNW_RELEASE_META_DIR/notes-store.txt" || true
  else
    git log --no-merges --format='- %s' -n 50 > "$RNW_RELEASE_META_DIR/notes-store.txt" || true
  fi
  # An empty notes file makes App Store Connect reject the submission, so never
  # ship one: fall back to a single generic line.
  [ -s "$RNW_RELEASE_META_DIR/notes-store.txt" ] ||
    printf -- '- Bug fixes and improvements\n' > "$RNW_RELEASE_META_DIR/notes-store.txt"
  {
    printf '## %s (%s)\n\n' "${APP_VERSION:-unreleased}" "${APP_BUILD_NUMBER:-0}"
    cat "$RNW_RELEASE_META_DIR/notes-store.txt"
  } > "$RNW_RELEASE_META_DIR/notes.md"
fi

# notes.mjs is the consumer's, so assert the two files the store lanes need
# rather than trusting it produced them.
for f in store-notes.json notes-store.txt; do
  [ -f "$RNW_RELEASE_META_DIR/$f" ] || die "release notes step produced no $f in $RNW_RELEASE_META_DIR"
done
[ -f "$RNW_RELEASE_META_DIR/notes.md" ] || cp "$RNW_RELEASE_META_DIR/notes-store.txt" "$RNW_RELEASE_META_DIR/notes.md"

gh_env RELEASE_NOTES_STORE_FILE "$RNW_RELEASE_META_DIR/notes-store.txt"
log "release-meta contents:"
ls -l "$RNW_RELEASE_META_DIR" >&2
endgroup
