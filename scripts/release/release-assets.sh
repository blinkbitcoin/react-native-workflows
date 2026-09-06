#!/usr/bin/env bash
# Create or move a GitHub release and attach the fixed release asset set.
#
# Usage: release-assets.sh MODE
#   create-prerelease  create (or update) $TAG as a pre-release at $TARGET_SHA
#   promote            take $TAG out of pre-release, without making it latest
#   latest             take $TAG out of pre-release and mark it latest
#   append             append a section to $TAG's existing body
#
# Every mode uploads whatever of the fixed asset set is present in
# $RNW_ASSETS_DIR (`--clobber`, so re-running a stage is safe) together with a
# freshly computed SHA256SUMS. The list is fixed on purpose: a release whose
# assets vary run to run cannot be verified by a downstream script.
#
# Env: TAG (required), TITLE, TARGET_SHA, NOTES_FILE, APPEND_TITLE,
#      RNW_ASSETS_DIR (default $RNW_OUT/assets), GH_TOKEN, GH_REPO.
set -euo pipefail
source "$(dirname "$0")/../lib/common.sh"
source "$(dirname "$0")/../lib/release-env.sh"
require_cmd gh

mode="${1:?usage: release-assets.sh create-prerelease|promote|latest|append}"
tag="${TAG:?release-assets.sh needs TAG}"
assets_dir="${RNW_ASSETS_DIR:-$RNW_OUT/assets}"

# The body scratch files sit in $RUNNER_TEMP and would die with the runner, but
# a local run should not litter and a leftover body must never be picked up by
# a later invocation.
body_file="${RUNNER_TEMP:-/tmp}/rnw-release-body.md"
stripped_file="$body_file.stripped"
trap 'rm -f "$body_file" "$stripped_file"' EXIT

# The fixed asset set, as basename globs. Anything else in the directory is
# deliberately ignored rather than silently published.
ASSET_GLOBS=(
  'build-info.json'
  'store-notes.json'
  'notes-store.txt'
  'notes.md'
  '*.ipa'
  '*.aab'
  '*.apk'
  '*.dSYM.zip'
  'dsyms.zip'
  'mapping.txt'
)

assets=()
collect_assets() {
  local g f
  assets=()
  [ -d "$assets_dir" ] || return 0
  for g in "${ASSET_GLOBS[@]}"; do
    # Unquoted on purpose: $g is the glob pattern being expanded.
    # shellcheck disable=SC2086
    for f in "$assets_dir"/$g; do
      if [ -f "$f" ]; then assets+=("$f"); fi
    done
  done
  # Explicit: the loop's last `[ -f ]` is the function's exit status otherwise,
  # and a non-matching final glob would abort the caller under errexit.
  return 0
}

sha256_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"; else sha256sum "$1"; fi
}

release_exists() { gh release view "$tag" >/dev/null 2>&1; }

upload_assets() {
  local a
  collect_assets
  if [ "${#assets[@]}" -eq 0 ]; then
    log "no release assets found in $assets_dir - nothing to upload"
    return 0
  fi
  # Basenames only: the checksum file ships next to the assets on the release
  # page, where the absolute path of a runner's temp directory is noise.
  (
    cd "$assets_dir"
    : > SHA256SUMS
    for a in "${assets[@]}"; do sha256_of "$(basename "$a")" >> SHA256SUMS; done
  )
  assets+=("$assets_dir/SHA256SUMS")
  group "upload ${#assets[@]} assets to $tag"
  gh release upload "$tag" "${assets[@]}" --clobber
  endgroup
}

# Optional gh flags are built as arrays so an unset variable contributes no
# argument at all (an empty quoted "" would become a literal empty argument).
title_args=()
[ -z "${TITLE:-}" ] || title_args=(--title "$TITLE")
notes_args=()
if [ -n "${NOTES_FILE:-}" ] && [ -f "$NOTES_FILE" ]; then
  notes_args=(--notes-file "$NOTES_FILE")
fi
target_args=()
[ -z "${TARGET_SHA:-}" ] || target_args=(--target "$TARGET_SHA")

case "$mode" in
  create-prerelease)
    if release_exists; then
      log "release $tag already exists - updating it in place"
      gh release edit "$tag" --prerelease --draft=false "${title_args[@]+"${title_args[@]}"}" \
        "${notes_args[@]+"${notes_args[@]}"}"
    else
      if [ "${#notes_args[@]}" -eq 0 ]; then
        notes_args=(--generate-notes)
      fi
      gh release create "$tag" --prerelease \
        "${title_args[@]+"${title_args[@]}"}" \
        "${target_args[@]+"${target_args[@]}"}" \
        "${notes_args[@]}"
    fi
    upload_assets
    ;;
  promote)
    release_exists || die "release $tag does not exist - run create-prerelease first"
    # --latest=false on purpose: promoting a staged build out of pre-release is
    # not the same decision as declaring it the latest release.
    gh release edit "$tag" --prerelease=false --latest=false "${title_args[@]+"${title_args[@]}"}"
    upload_assets
    ;;
  latest)
    release_exists || die "release $tag does not exist - run create-prerelease first"
    gh release edit "$tag" --prerelease=false --latest "${title_args[@]+"${title_args[@]}"}"
    upload_assets
    ;;
  append)
    release_exists || die "release $tag does not exist - nothing to append to"
    [ "${#notes_args[@]}" -eq 2 ] || die "append needs NOTES_FILE pointing at an existing section file"
    title="${APPEND_TITLE:-Update}"
    heading="## $title"
    # Re-running a failed job is the ordinary way an Actions failure is
    # recovered (it is why the asset upload uses --clobber), so append has to be
    # idempotent too.
    #
    # The block is delimited by HTML-comment markers, not by "the heading down to
    # the next `## `". The notes file routinely *starts* with a `## ` heading -
    # notes.sh's fallback writes `## <version> (<build>)` and a release-please
    # body starts with `## [x.y.z](...)` - so a heading scan stops at the notes'
    # own heading and leaves their tail behind, stacking a little more of it on
    # every re-run. Markers bound the block regardless of its content.
    begin_marker="<!-- rnw:append:$title -->"
    end_marker="<!-- /rnw:append:$title -->"
    gh release view "$tag" --json body --jq '.body' > "$body_file"
    if grep -qxF "$begin_marker" "$body_file"; then
      awk -v b="$begin_marker" -v e="$end_marker" '
        $0 == b { skipping = 1; next }
        skipping && $0 == e { skipping = 0; next }
        !skipping { print }
      ' "$body_file" > "$stripped_file"
    else
      # Migration path: a body appended by a version of this script that
      # predates the markers has no begin marker, so fall back to the old
      # heading scan once. The next run is marker-delimited like any other.
      awk -v heading="$heading" '
        $0 == heading { skipping = 1; next }
        skipping && /^## / { skipping = 0 }
        !skipping { print }
      ' "$body_file" > "$stripped_file"
    fi
    # Trailing blank lines would otherwise accumulate one pair per re-run.
    {
      awk 'BEGIN { blank = 0 }
        /^[[:space:]]*$/ { blank++; next }
        { while (blank-- > 0) print ""; blank = 0; print }
      ' "$stripped_file"
      printf '\n%s\n%s\n\n' "$begin_marker" "$heading"
      cat "$NOTES_FILE"
      printf '%s\n' "$end_marker"
    } > "$body_file"
    gh release edit "$tag" --notes-file "$body_file"
    upload_assets
    ;;
  *)
    die "unknown mode '$mode' (create-prerelease|promote|latest|append)"
    ;;
esac

log "release $tag: $mode done"
gh_output tag "$tag"
gh_output url "$(gh release view "$tag" --json url --jq '.url')"
