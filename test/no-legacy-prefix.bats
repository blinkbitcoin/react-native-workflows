#!/usr/bin/env bats
# Every assertion ends in `|| fail "..."` - see test_helper.bash.
#
# The family's variables were prefixed `RNW_`, the initials of this repo's name,
# and the checkout directory was `.rnw/`. A reader meeting `RNW_MAESTRO_FLOWS`
# or `$RNW` in their own app repo had no way to recover the expansion: it
# appeared nowhere near the point of use. They are `WORKFLOWS_` and `.workflows/`
# now.
#
# That rename touched ~1300 occurrences across ~135 files, which is more than
# review catches, and a half-finished rename is worse to read than either name
# alone. It is also the specific way this change fails quietly: a test matching
# `.with.path == ".rnw"` stops matching anything and goes green rather than red -
# test/workflow-shape.bats had two such cases, and one yq pattern matching
# `rnw/.github/actions/setup` was already stale before this file existed.
#
# So the absence of the old prefix is asserted rather than assumed.
load test_helper

# Archives are excluded on purpose: docs/superpowers/ and .superpowers/ are
# dated records of what was planned and reviewed at the time. Rewriting them to
# match today's names would make them lie about their own past.
legacy_hits() {
  cd "$REPO_ROOT" || return 1
  # -I skips binary files; the lockfile fixture is excluded because base64
  # integrity hashes contain the letters by coincidence, not as an identifier.
  # This file is excluded from its own search: it names the old prefix on
  # purpose, to explain what was renamed and why. A check that reads its own
  # explanation as a violation is a false positive waiting to happen.
  grep -rnIi 'rnw' \
    --exclude-dir=.git \
    --exclude-dir=.superpowers \
    --exclude-dir=node_modules \
    --exclude=no-legacy-prefix.bats \
    . 2>/dev/null |
    grep -v '^\./docs/superpowers/' |
    grep -v 'integrity: sha512' || true
}

@test "no RNW_ variable, \$RNW or .rnw path survives outside the archives" {
  hits="$(legacy_hits)"
  [ -z "$hits" ] || fail "the old prefix is still here - a half-finished rename reads worse than either name alone:
$hits"
}

@test "no file or directory is named with the old prefix" {
  cd "$REPO_ROOT" || fail "cannot reach the repo root"
  found="$(find . -path ./.git -prune -o -iname '*rnw*' -print 2>/dev/null || true)"
  [ -z "$found" ] || fail "these paths still carry the old prefix: $found"
}

# The checkout directory's name appears in consumer-facing advice (exclude it
# from Biome, knip and CodeQL) and in this repo's own shape tests. Those two
# have to agree, or the guide tells consumers to ignore a directory that is no
# longer there.
@test "the guide and the workflows agree on the checkout directory name" {
  command -v yq >/dev/null || skip "yq not installed"
  grep -qF '.workflows' "$REPO_ROOT/docs/consumer-guide.md" \
    || fail "the consumer guide no longer names the checkout directory"
  paths="$(yq -r '.jobs[].steps[]? | select(.uses? == "actions/checkout@v7") | .with.path // ""' \
    "$REPO_ROOT/.github/workflows/checks.yml" | grep -v '^$' | sort -u)"
  [ "$paths" = ".workflows" ] \
    || fail "checks.yml checks out to '$paths', which is not the directory the guide documents"
}
