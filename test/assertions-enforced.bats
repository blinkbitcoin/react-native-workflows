#!/usr/bin/env bats
# Guard: no assertion in this suite may rely on `set -e` catching it.
#
# Two shell rules make a mid-body assertion silently unenforceable, so a broken
# check reads as a passing test:
#
#   1. bash 3.2 - which is macOS's /bin/bash, and therefore the bash bats runs
#      under locally and on a macos-* runner - does not honour errexit for a
#      failing `[[ ]]`, because a conditional command is not a simple command:
#
#        bash-3.2 -c 'set -e; f(){ [[ a == b ]]; echo REACHED; }; f'  -> REACHED
#        bash-5.3 -c 'set -e; f(){ [[ a == b ]]; echo REACHED; }; f'  -> aborts
#
#      An ubuntu-latest runner has bash 5, so without this guard the same file
#      is enforced in CI and unenforced on a developer's Mac - a check that rots
#      locally and is caught, if ever, only by a red CI run.
#
#   2. POSIX exempts `! cmd` from errexit on every bash ("the shell does not
#      exit ... if the command's return status is being inverted with !"), so a
#      bare `! grep -q ...` cannot fail a test anywhere. That one had already
#      hidden a false positive in workflow-shape.bats.
#
# `[ ]` (the test *builtin* - a simple command) is unaffected, which is why the
# gap went unnoticed. The fix in both cases is `... || fail "message"`: `fail`
# is a function call, i.e. a simple command, and the whole `||` list is what
# errexit observes.
load test_helper

# A statement that is a bare `[[ ... ]]` or a bare `! ...`. Anchored at the
# start of the statement, so `if [[ ... ]]`, `while ...`, `[ ... ]` and
# assignments never match. Kept without a `^` so it can be anchored either
# against a raw line or against a `lineno:` prefix.
OFFENDING='[[:space:]]*(\[\[|!)[[:space:]]'

# Emits `lineno:text` per *logical* line, joining backslash continuations - a
# guard split across two physical lines is still a guard.
logical_lines() {
  awk '
    { line = line $0 }
    /\\$/ { sub(/\\$/, " ", line); if (start == 0) start = NR; next }
    { printf "%d:%s\n", (start ? start : NR), line; line = ""; start = 0 }
  ' "$1"
}

@test "no bats file has an unguarded [[ ]] or ! assertion" {
  offenders=""
  for f in "$REPO_ROOT"/test/*.bats; do
    # This file is exempt: its second test deliberately writes both an
    # unguarded and a guarded fixture in order to check the pattern itself.
    case "$(basename "$f")" in
      assertions-enforced.bats) continue ;;
    esac
    hits="$(logical_lines "$f" |
      grep -E "^[0-9]+:$OFFENDING" |
      grep -v '|| fail' |
      grep -vE '^[0-9]+:[[:space:]]*#' || true)"
    if [ -n "$hits" ]; then
      offenders="$offenders
$(basename "$f"):
$hits"
    fi
  done
  [ -z "$offenders" ] || fail "unguarded assertions found - append \`|| fail \"message\"\` to each (see the header of this file):$offenders"
}

# The guard is only worth having if it can actually fire, and its regex is the
# part most likely to rot, so it is exercised against synthetic files rather
# than trusted.
@test "the guard's pattern matches an unguarded assertion and spares a guarded one" {
  bad="$BATS_TEST_TMPDIR/bad.bats"
  good="$BATS_TEST_TMPDIR/good.bats"
  cat > "$bad" <<'EOF'
@test "x" {
  [[ "$output" == *"y"* ]]
  ! grep -q z "$f"
}
EOF
  cat > "$good" <<'EOF'
@test "x" {
  [[ "$output" == *"y"* ]] || fail "no y"
  ! grep -q z "$f" || fail "z is present"
  [ "$status" -eq 0 ]
  if [[ "$a" == "b" ]]; then :; fi
  ! grep -q z "$f" \
    || fail "still guarded, just wrapped"
  # [[ "$commented" == *"out"* ]]
}
EOF
  bad_hits="$(logical_lines "$bad" | grep -cE "^[0-9]+:$OFFENDING")"
  [ "$bad_hits" -eq 2 ] || fail "the pattern matched $bad_hits of the 2 unguarded assertions"
  good_hits="$(logical_lines "$good" |
    grep -E "^[0-9]+:$OFFENDING" |
    grep -v '|| fail' |
    grep -vE '^[0-9]+:[[:space:]]*#' || true)"
  [ -z "$good_hits" ] || fail "the pattern flagged a guarded or non-assertion line: $good_hits"
}
