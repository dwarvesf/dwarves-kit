#!/usr/bin/env bash
# negctl.sh - the negative control in one command: green, break one thing, red, restore, green.
#
#   bash scripts/negctl.sh "<test command>" "<mutate command>"
#   bash scripts/negctl.sh --help
#
# Example:
#   bash scripts/negctl.sh "bash scripts/test-release-notes.sh" "sed -i.bak 's/dev:/dov:/' scripts/release-notes.sh"
#
# Steps, all run through bash -c in the repo root:
#   1. refuse when a tracked file has uncommitted changes (the restore uses git)
#   2. run the test: it must exit 0
#   3. run the mutate command: it must change at least one tracked file
#   4. run the test: it must exit non-zero, else the test does not cover the break.
#      A red run that is only a load or syntax error is refused: it proves nothing.
#      The red counts when its output holds a failed-assertion line (FAIL, not ok,
#      N failed, failures: N). Without one, exit 126 or 127 or a shell syntax-error
#      message marks a load error.
#   5. restore: git checkout the changed files, remove the untracked files the
#      mutation created (proved by comparing the untracked list before and after;
#      a file that existed before the mutation is never removed)
#   6. run the test: it must exit 0 again
# A trap restores on any exit, Ctrl-C included. Progress goes to stderr. A refusal
# ends stderr with exactly two lines: the rule, then a "Fix:" line. On success
# stdout holds the proof block: NEGATIVE CONTROL, Command, Output (the last
# 15 lines of the red run), Exit, Verdict.
#
# The test command and the mutate command are the operator's own arguments and run through
# bash -c by design. Nothing else reaches a shell: a file name from the tree is only ever passed
# quoted after "--", and test output is only printed, with control characters removed and
# every line indented (so it cannot pass for a refusal). Text from the tree or from test output
# that is echoed into a rule line has every character outside A-Za-z0-9._/@- , comma and space
# replaced by ?.
#
# The mutation must edit tracked files. A tracked file the mutation adds to git
# cannot be restored by checkout: it is named and left in place.
#
# Exit codes: 0 green, red, green; 1 a step failed or the red was a load error;
# 2 refused before anything ran (dirty tree, not a git work tree); 64 bad usage.
# bash 3.2 safe.
set -euo pipefail

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# refuse <exit code> <rule> <fix>: restore any break first, so nothing prints after the pair,
# then print two lines on stderr and leave.
armed=0
refuse() {
    [ "$armed" -eq 0 ] || restore
    printf 'negctl: %s\nFix: %s\n' "$2" "$3" >&2
    exit "$1"
}

# clean <text>: every character outside A-Za-z0-9._/@- , comma and space becomes ?.
clean() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._/@ ,-' '?'; }
# plain <file>: the file with control characters (an escape, a carriage return) removed.
plain() { LC_ALL=C sed "s/[$(printf '\001-\010\013-\037\177')]//g" <"$1"; }

use_fix='bash scripts/negctl.sh "<test command>" "<mutate command>"'

case "${1-}" in
-h | --help)
    usage
    exit 0
    ;;
esac
if [ "$#" -ne 2 ] || [ -z "$1" ] || [ -z "$2" ]; then
    refuse 64 "need exactly two arguments, a test command and a mutate command" "$use_fix"
fi
test_cmd="$1"
mutate_cmd="$2"

if ! top="$(git rev-parse --show-toplevel 2>/dev/null)" || ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
    refuse 2 "REFUSED, this is not a git work tree with a commit" 'git init && git add -A && git commit -m "init"'
fi
cd "$top"
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    refuse 2 "REFUSED, tracked files have uncommitted changes and the restore step uses git" 'git commit -am "wip: before the negative control"'
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/negctl.XXXXXX")"
out="$work/out"
created="$work/created"
: >"$created"
child=""
mutating=0
created_known=0
restore_failed=0
stuck_said=0
rc=0

tracked_changes() { git -c core.quotepath=off diff HEAD --no-renames --name-only; }
untracked_files() { git -c core.quotepath=off ls-files --others --exclude-standard | LC_ALL=C sort; }
show_tail() { plain "$out" | tail -n 15 | sed 's/^/    /' >&2; }

# The test runs as a background job in its own process group, so a signal to
# negctl can stop the whole test tree before the restore starts.
kill_child() {
    [ -n "$child" ] || return 0
    kill -TERM -- "-$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    child=""
}

run_test() {
    set -m
    (
        trap - INT TERM HUP
        exec bash -c "$test_cmd"
    ) >"$out" 2>&1 </dev/null &
    child=$!
    set +m
    rc=0
    wait "$child" || rc=$?
    child=""
}

# A red run proves something only when the test ran and failed an assertion.
# Prints why and returns 0 when the red run is a load or syntax error instead.
assert_re='^[[:space:]]*(FAIL|not ok|--- FAIL|AssertionError)|[1-9][0-9]* (failed|failing)|failures: [1-9]|test result: FAILED'
load_re='syntax error|unexpected EOF|unexpected end of file'
red_load_error() {
    local code="$1" clean="$work/red-clean" line
    sed $'s/\x1b\\[[0-9;]*[A-Za-z]//g' "$out" >"$clean"
    if grep -aEq "$assert_re" "$clean"; then
        return 1
    fi
    case "$code" in
    126 | 127)
        echo "exit $code, the test command could not run"
        return 0
        ;;
    esac
    if line="$(grep -aE -m1 "$load_re" "$clean")"; then
        printf '%s\n' "$line" | sed 's/^[[:space:]]*//' | cut -c1-100 | LC_ALL=C tr -c 'A-Za-z0-9._/@ \n,-' '?'
        return 0
    fi
    return 1
}

on_signal() {
    echo "negctl: interrupted, restoring" >&2
    exit "$1"
}

# Idempotent: a second call finds nothing left to do. Signals are ignored while
# it runs so a second Ctrl-C cannot leave the break in place.
restore() {
    trap '' INT TERM HUP
    kill_child
    local f
    local to_restore=() stuck=()
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if git cat-file -e "HEAD:$f" 2>/dev/null; then
            to_restore+=("$f")
        else
            stuck+=("$f")
        fi
    done <<EOF
$(tracked_changes)
EOF
    if [ "${#to_restore[@]}" -gt 0 ]; then
        git checkout -q HEAD -- "${to_restore[@]}" || {
            [ "$stuck_said" -eq 1 ] || echo "negctl: git checkout failed for: $(clean "${to_restore[*]}")" >&2
            stuck_said=1
            restore_failed=1
        }
    fi
    if [ "${#stuck[@]}" -gt 0 ]; then
        [ "$stuck_said" -eq 1 ] || echo "negctl: not in HEAD, left in place: $(clean "${stuck[*]}")" >&2
        stuck_said=1
        restore_failed=1
    fi
    if [ "$mutating" -eq 1 ] && [ "$created_known" -eq 0 ]; then
        echo "negctl: stopped while the mutation ran; untracked files it may have created were left alone" >&2
        mutating=0
    fi
    if [ -s "$created" ]; then
        untracked_files >"$work/now"
        LC_ALL=C comm -12 "$created" "$work/now" >"$work/remove"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            rm -f -- "$f"
        done <"$work/remove"
        : >"$created"
    fi
    trap 'on_signal 130' INT
    trap 'on_signal 143' TERM
    trap 'on_signal 129' HUP
}

cleanup() {
    local status=$?
    restore
    case "$work" in
    */negctl.*) rm -rf "$work" ;;
    esac
    if [ "$status" -eq 0 ] && [ "$restore_failed" -ne 0 ]; then
        status=1
    fi
    exit "$status"
}

trap cleanup EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
armed=1

echo "negctl: 1/4 test before the change" >&2
run_test
if [ "$rc" -ne 0 ]; then
    show_tail
    refuse 1 "the test is not green before the change, nothing was mutated" "$test_cmd"
fi
if [ -n "$(tracked_changes)" ]; then
    refuse 1 "the test changed tracked files by itself, so a mutation cannot be told apart; restored" "git status --short"
fi

untracked_files >"$work/before"
mutating=1
mutate_rc=0
(bash -c "$mutate_cmd") >"$work/mutate-out" 2>&1 || mutate_rc=$?
untracked_files >"$work/after"
LC_ALL=C comm -13 "$work/before" "$work/after" >"$created"
created_known=1
if [ "$mutate_rc" -ne 0 ]; then
    plain "$work/mutate-out" | tail -n 15 | sed 's/^/    /' >&2
    refuse 1 "the mutate command failed with exit $mutate_rc; restored" "$mutate_cmd"
fi
changed="$(tracked_changes)"
if [ -z "$changed" ]; then
    refuse 1 "the mutation changed no tracked file; restored" "git ls-files"
fi
changed_line="$(printf '%s\n' "$changed" | LC_ALL=C tr -c 'A-Za-z0-9._/@ \n-' '?' | paste -sd, - | sed 's/,/, /g')"

echo "negctl: 2/4 test with the break in place (changed: $changed_line)" >&2
run_test
red_rc="$rc"
if [ "$red_rc" -eq 0 ]; then
    show_tail
    refuse 1 "the test stayed green with the break in place: the test does not cover it; restored" "$use_fix"
fi
if load_line="$(red_load_error "$red_rc")"; then
    show_tail
    refuse 1 "REFUSED, the red run is a load or syntax error, not a failing assertion ($load_line); restored" "$use_fix"
fi
if [ -s "$out" ]; then
    plain "$out" | tail -n 15 >"$work/red-tail"
else
    echo "<no output>" >"$work/red-tail"
fi

echo "negctl: 3/4 restore" >&2
restore
if [ -n "$(tracked_changes)" ] || [ "$restore_failed" -ne 0 ]; then
    refuse 1 "the tree is not restored" "git status --short"
fi

echo "negctl: 4/4 test after the restore" >&2
run_test
if [ "$rc" -ne 0 ]; then
    show_tail
    refuse 1 "the test is not green after the restore" "$test_cmd"
fi
restore
if [ "$restore_failed" -ne 0 ]; then
    refuse 1 "the tree is not restored" "git status --short"
fi

echo "NEGATIVE CONTROL: broke $changed_line"
echo "Command: $test_cmd"
echo "Output:"
cat "$work/red-tail"
echo "Exit: $red_rc"
echo "Verdict: RED, as expected"
echo
echo "Broke: $mutate_cmd (changed: $changed_line). Restored with git checkout; the tree is clean. The test was green before (exit 0) and is green again (exit 0)."
