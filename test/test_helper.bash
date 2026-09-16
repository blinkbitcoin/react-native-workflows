# shellcheck shell=bash
REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
export REPO_ROOT
FIXTURES="$REPO_ROOT/test/fixtures"
export FIXTURES

# fail MESSAGE - abort the current test with MESSAGE.
#
# Why every assertion in the release test files ends in `|| fail "..."` rather
# than standing on its own:
#
#   bats runs test bodies under `set -e`, but macOS ships bash 3.2 as
#   /bin/bash, and bash 3.2 does NOT honour errexit for a failing `[[ ]]` -
#   a *conditional command*, not a simple command. Verified on this machine:
#
#     bash-3.2 -c 'set -e; f(){ [[ a == b ]]; echo REACHED; }; f'  -> REACHED
#     bash-5.3 -c 'set -e; f(){ [[ a == b ]]; echo REACHED; }; f'  -> aborts
#
#   So a bare mid-body `[[ ]]` assertion silently cannot fail a test locally or
#   on a macOS runner: only the last command's status is observed. `[ ]` (the
#   test builtin, a simple command) is unaffected, which is why this went
#   unnoticed for so long. Routing every assertion through a function call -
#   a simple command - makes it abort under errexit on every bash.
fail() {
  printf '%s\n' "$*" >&2
  return 1
}

# contains HAYSTACK NEEDLE / not_contains HAYSTACK NEEDLE - substring checks
# that read as commands, so `|| fail` reads naturally at the call site.
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }
not_contains() { case "$1" in *"$2"*) return 1 ;; *) return 0 ;; esac; }

# parity_skip MESSAGE - skip a cross-repo parity case, unless CI insists.
#
# Several cases here compare a script in this repo against the consumer's own
# copy of it, which means they need a checkout of the template repo. This repo
# serves any consumer, so it has no business guessing where one sits on a
# particular machine: without $WORKFLOWS_TEMPLATE_DIR the case skips, and the message
# says the parity was NOT verified rather than implying the copies agree.
#
# On a laptop a skip is the right answer. In CI it is the exact failure this
# whole mechanism exists to prevent - a check that silently runs against nothing
# and reports green - so self-ci.yml sets WORKFLOWS_PARITY_REQUIRED=1 and a would-be
# skip becomes a failure instead.
parity_skip() {
  if [ "${WORKFLOWS_PARITY_REQUIRED:-0}" = "1" ]; then
    fail "WORKFLOWS_PARITY_REQUIRED=1 but this case cannot run: $*"
  fi
  skip "$*"
}
