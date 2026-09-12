#!/usr/bin/env bash
# negctl.sh -- the negative control, mechanised. FAILS CLOSED.
#
# Every behavioral proof owes "revert -> RED -> restore" (docs/verification/README.md), and
# every session re-derives the same five steps by hand: mutate a line, run the suite,
# `git checkout --`, run again. Two hazards live there: the restore wipes UNCOMMITTED work,
# and a control that never went red is still recorded as PASS. This script runs the sequence
# and prints the block proof-ledger.sh check() reads (Command:/Exit:/Verdict:).
#
# It lives beside proof-ledger.sh, not inside it: the gate FAILS OPEN on ambiguity so a gate
# bug never blocks unrelated work, while a tool that mutates the working tree must FAIL
# CLOSED. Mixing the two behind one banner is the invariant a reader would trust and get
# burned by. proof-ledger.sh keeps a `negctl` verb that forwards here.
#
# A PROBABILISTIC test breaks step 4. `run_test` is treated as deterministic, so a flaky
# suite can come back green under the mutation and negctl calls the control vacuous when the
# mutation was real. Set NEGCTL_RED_ATTEMPTS=<n> (default 1, byte-identical to before) to run
# step 4 up to n times and take the FIRST non-zero as RED. It never makes a green test red:
# a genuinely vacuous mutation stays green on every attempt and still FAILs.
# Load is the other axis and is deliberately NOT here: holding machine load from a proof tool
# is hostile on a shared box. Induce it around negctl instead, as
# docs/verification/wavefront-startup-windows-negctl.sh does.
#
# Usage: negctl.sh <root> <test-cmd> <mutate-cmd>
#   1. refuse if any tracked file is modified or staged (the restore would wipe it)
#   2. snapshot the tree (tracked + untracked), run <test-cmd>: must be GREEN (exit 0)
#   3. run <mutate-cmd>; the tracked files it changed (staged or not) are the restore set
#   4. run <test-cmd>: must be RED (non-zero), else the check is vacuous
#   5. restore the set with `git checkout HEAD --`, quoted, rc checked; any untracked file
#      the mutation created or removed is a FAIL (it cannot be restored by git)
#   6. run <test-cmd>: must be GREEN again; the tree must match the snapshot
#   Prints `Verdict: PASS` and exits 0 only when every step held; otherwise the first
#   failure names itself in `Verdict: FAIL: <reason>` and the exit is 1. A dirty tree is
#   `REFUSED`, exit 2, before anything runs. Restore runs on every exit path after step 3.
set -uo pipefail

root="${1:-}"; test_cmd="${2:-}"; mutate_cmd="${3:-}"
[ -n "$root" ] && [ -n "$test_cmd" ] && [ -n "$mutate_cmd" ] \
  || { echo "usage: negctl.sh <root> <test-cmd> <mutate-cmd>" >&2; exit 64; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "negctl: $root is not a git repo" >&2; exit 64; }

# Bounded retries for the RED step only. Rejected rather than coerced: a typo that silently
# became 1 would read as a clean single-attempt run and hide that the operator asked for more.
red_attempts="${NEGCTL_RED_ATTEMPTS:-1}"
case "$red_attempts" in
  ''|*[!0-9]*) echo "negctl: NEGCTL_RED_ATTEMPTS must be a positive integer (got '$red_attempts')" >&2; exit 64 ;;
esac
[ "$red_attempts" -ge 1 ] || { echo "negctl: NEGCTL_RED_ATTEMPTS must be >= 1 (got '$red_attempts')" >&2; exit 64; }

if [ -n "$(git -C "$root" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
  echo "negctl: REFUSED -- tracked files are modified or staged in $root; commit first (the restore step is 'git checkout HEAD --', it would wipe them)" >&2
  exit 2
fi

verdict="PASS"
fail() { [ "$verdict" = "PASS" ] && verdict="FAIL: $1"; return 0; }
run_test() { (cd "$root" && bash -c "$test_cmd") >/dev/null 2>&1; }
snapshot() { git -C "$root" status --porcelain --untracked-files=all 2>/dev/null; }

restore_files=()
restore_done=0
restore() {
  [ "$restore_done" -eq 1 ] && return 0
  restore_done=1
  [ "${#restore_files[@]}" -gt 0 ] || return 0
  git -C "$root" checkout -q HEAD -- "${restore_files[@]}" 2>/dev/null || fail "restore failed: git checkout HEAD -- ${restore_files[*]}"
}
trap restore EXIT

echo "## Negative control (negctl)"
before="$(snapshot)"
echo "Command: $test_cmd"
run_test; rc_before=$?
echo "Exit: $rc_before (green before mutation)"
[ "$rc_before" -eq 0 ] || fail "test was not green before the mutation"

(cd "$root" && bash -c "$mutate_cmd") >/dev/null 2>&1
# staged or unstaged, NUL-delimited so a path with a space or a quote survives
while IFS= read -r -d '' f; do restore_files+=("$f"); done < <(git -C "$root" diff HEAD --name-only -z 2>/dev/null)
echo "Mutation: $mutate_cmd"
if [ "${#restore_files[@]}" -gt 0 ]; then
  printf 'Changed: %s\n' "$(printf '%s, ' "${restore_files[@]}" | sed 's/, $//')"
else
  echo "Changed: <no tracked file>"
  fail "the mutation changed no tracked file"
fi

red_used=0
rc_red=0
while [ "$red_used" -lt "$red_attempts" ]; do
  red_used=$(( red_used + 1 ))
  run_test; rc_red=$?
  [ "$rc_red" -ne 0 ] && break
done
if [ "$red_attempts" -gt 1 ]; then
  echo "Exit: $rc_red (under mutation, RED expected; attempt $red_used of $red_attempts)"
else
  echo "Exit: $rc_red (under mutation, RED expected)"
fi
if [ "$rc_red" -eq 0 ]; then
  # The single-attempt wording is unchanged on purpose: the default path must stay
  # byte-identical, and two dated proof records quote this exact line.
  if [ "$red_attempts" -gt 1 ]; then
    fail "test stayed green under the mutation on all $red_attempts attempts (the check is vacuous)"
  else
    fail "test stayed green under the mutation (the check is vacuous)"
  fi
fi

restore
echo "Restore: git checkout HEAD -- ${restore_files[*]:-<nothing>}"
after="$(snapshot)"
if [ "$after" != "$before" ]; then
  fail "tree differs from the pre-run snapshot after restore (untracked leftovers or a file git cannot restore)"
  diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | sed -n 's/^[<>] /Delta: /p' | head -5
fi

run_test; rc_after=$?
echo "Exit: $rc_after (green after restore)"
[ "$rc_after" -eq 0 ] || fail "test not green after restore"

echo "Verdict: $verdict"
[ "$verdict" = "PASS" ]
