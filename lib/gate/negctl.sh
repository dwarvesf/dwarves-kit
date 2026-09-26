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
# a genuinely vacuous mutation stays green on every attempt and still FAILs -- and a GREEN
# attempt that itself leaves tracked dirt beyond the mutation stops the retries outright
# rather than let that leftover state make the NEXT attempt spuriously RED.
# Load is the other axis and is deliberately NOT here: holding machine load from a proof tool
# is hostile on a shared box. Induce it around negctl instead, as
# docs/verification/wavefront-startup-windows-negctl.sh does.
#
# A test-cmd side write breaks steps 3 and 5 the same way a flaky test breaks step 4: `git
# diff HEAD` is a live, cumulative snapshot, not a delta, so a tracked file <test-cmd> writes
# while running (a fixture it renders on every pass, not the mutation itself) shows up
# indistinguishable from the mutation's own change. Every tracked-diff capture below passes
# `--no-renames`, too: without it, a staged `git mv` collapses a delete-then-add pair into one
# rename entry and `--name-only` reports only the new path, hiding the old path's deletion
# from every set this script builds.
#
# Usage: negctl.sh <root> <test-cmd> <mutate-cmd>
#   1. refuse if any tracked file is modified or staged (the restore would wipe it)
#   2. snapshot the tree (tracked + untracked), run <test-cmd>: must be GREEN (exit 0);
#      capture the tracked diff here too (the baseline diff) -- anything <test-cmd> itself
#      writes even before any mutation, so step 3's "did the mutation change anything" check
#      never credits the mutation with a write that predates it
#   3. run <mutate-cmd>; the tracked files it changed (staged or not), minus the baseline
#      diff, are reported as "Changed:"; empty is a FAIL ("the mutation changed no tracked
#      file"). The raw, un-subtracted set is still what step 5 restores under that name.
#   4. run <test-cmd>: must be RED (non-zero), else the check is vacuous. Up to
#      NEGCTL_RED_ATTEMPTS tries; after every GREEN try that is not the last, the tree is
#      checked for tracked dirt beyond the mutation's own set -- an attempt that itself wrote
#      a tracked file could otherwise make the NEXT attempt spuriously RED, hiding a
#      genuinely vacuous mutation. That is a FAIL, named by file, and retries stop there.
#   5. restore. The mutation's own set restores exactly as step 3 found it, even when that
#      set is empty. Anything else tracked-different from HEAD -- most often a file
#      <test-cmd> wrote while going RED -- restores too, but only if it exists at HEAD:
#      `git checkout HEAD --` aborts its ENTIRE call the moment one path doesn't resolve
#      there, so a brand-new tracked file the run added is never included in that call. It
#      is named in a FAIL instead and left exactly where it landed -- never `git rm`, never
#      `git clean`. An untracked file the mutation created or removed is unrestorable either
#      way and is caught by step 6, same as always.
#   6. run <test-cmd>: must be GREEN again; the tree must match the snapshot from step 2.
#   Prints `Verdict: PASS` and exits 0 only when every step held; otherwise the first
#   failure names itself in `Verdict: FAIL: <reason>` and the exit is 1. A dirty tree is
#   `REFUSED`, exit 2, before anything runs. Restore runs on every exit path once the
#   mutation's own set is known -- even an empty one -- so an interrupt as early as the gap
#   between the mutation running and that set being captured still restores whatever the
#   tree has picked up by then.
#
# Usage: negctl.sh --base-ref <ref> <root> <test-cmd>
#   Step 1's refusal is correct but permanent on a SHARED checkout: a repo where other
#   sessions hold uncommitted work is never clean, so the mutate mode can never run there
#   (real case, 2026-09-18/19: two shared repos stayed dirty all session, five controls had
#   to be hand-rolled). This mode proves the same thing a different way: the change under
#   test is proven by the ref that PREDATES it, not by damaging the working tree. It
#   extracts <root> at <ref> into a throwaway dir via `git archive` (mutates nothing, so a
#   dirty checkout never trips a refusal) and requires <test-cmd> to come back RED there.
#   A base ref that passes proves nothing, so that is a FAIL, not a pass, same fail-closed
#   contract as the mutate mode. It shares the same `Command:`/`Exit:`/`Verdict:` block
#   proof-ledger.sh check() parses. Mutate mode also assumes it is the sole writer to <root>
#   for the run's duration; a concurrently-touched (shared) checkout should use this mode
#   instead, since it never touches the working tree at all.
set -uo pipefail

if [ "${1:-}" = "--base-ref" ]; then
  base_ref="${2:-}"; root="${3:-}"; test_cmd="${4:-}"
  [ -n "$base_ref" ] && [ -n "$root" ] && [ -n "$test_cmd" ] \
    || { echo "usage: negctl.sh --base-ref <ref> <root> <test-cmd>" >&2; exit 64; }
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "negctl: $root is not a git repo" >&2; exit 64; }
  git -C "$root" rev-parse --verify "${base_ref}^{commit}" >/dev/null 2>&1 \
    || { echo "negctl: base ref '$base_ref' does not resolve to a commit in $root" >&2; exit 64; }

  extract="$(mktemp -d)"
  cleanup() { rm -rf "$extract"; }
  trap cleanup EXIT

  # git archive reads from the object store, never the working tree, so it cannot refuse or
  # damage a dirty checkout; that is the entire reason this mode exists.
  if ! git -C "$root" archive "$base_ref" | tar -x -C "$extract" 2>/dev/null; then
    echo "negctl: failed to extract $base_ref from $root" >&2
    exit 1
  fi

  echo "## Negative control (negctl, base-ref mode)"
  echo "Base ref: $base_ref"
  echo "Command: $test_cmd"
  (cd "$extract" && bash -c "$test_cmd") >/dev/null 2>&1
  rc=$?
  echo "Exit: $rc (base ref, RED expected)"
  if [ "$rc" -ne 0 ]; then
    echo "Verdict: PASS"
    exit 0
  fi
  echo "Verdict: FAIL: the check passed at $base_ref, so it proves nothing about the change"
  exit 1
fi

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

# $1 = needle path; remaining args (may be none) = haystack. bash 3.2 (macOS's /bin/bash)
# treats "${arr[@]}" on a zero-element array as unset under `set -u`, so every call site
# guards with a length check first rather than expanding an empty array bare.
_path_in() {
  needle="$1"; shift
  for hay in "$@"; do
    [ "$hay" = "$needle" ] && return 0
  done
  return 1
}

# Populates the global array `beyond`: a fresh, live `git diff HEAD --no-renames --name-only`
# against $root, with every path already in restore_files (the mutation's own set) removed.
# This is "whatever is tracked-different from HEAD right now, beyond what the mutation itself
# already accounted for" -- used both by the retry-loop guard (step 4) and by restore()
# (step 5), always recomputed fresh since the tree keeps changing between calls.
_beyond_mutate_set() {
  beyond=()
  while IFS= read -r -d '' f; do
    if [ "${#restore_files[@]}" -gt 0 ] && _path_in "$f" "${restore_files[@]}"; then
      continue
    fi
    beyond+=("$f")
  done < <(git -C "$root" diff HEAD --no-renames --name-only -z 2>/dev/null)
}

restore_files=()
restore_done=0
restore() {
  [ "$restore_done" -eq 1 ] && return 0
  restore_done=1
  # No early return here even when restore_files is empty: the recompute below must always
  # run, including for a Ctrl-C-triggered EXIT-trap call landing before restore_files itself
  # was ever populated (the gap between mutate_cmd running and its capture, right below).
  if [ "${#restore_files[@]}" -gt 0 ]; then
    git -C "$root" checkout -q HEAD -- "${restore_files[@]}" 2>/dev/null \
      || fail "restore failed: git checkout HEAD -- ${restore_files[*]}"
  fi

  _beyond_mutate_set
  side_effect_head=(); side_effect_new=()
  if [ "${#beyond[@]}" -gt 0 ]; then
    for f in "${beyond[@]}"; do
      if git -C "$root" cat-file -e "HEAD:$f" 2>/dev/null; then
        side_effect_head+=("$f")
      else
        side_effect_new+=("$f")
      fi
    done
  fi
  if [ "${#side_effect_head[@]}" -gt 0 ]; then
    git -C "$root" checkout -q HEAD -- "${side_effect_head[@]}" 2>/dev/null \
      || fail "restore failed: git checkout HEAD -- ${side_effect_head[*]}"
    printf 'Side effect: %s\n' "$(printf '%s, ' "${side_effect_head[@]}" | sed 's/, $//')"
  fi
  if [ "${#side_effect_new[@]}" -gt 0 ]; then
    new_list="$(printf '%s, ' "${side_effect_new[@]}" | sed 's/, $//')"
    printf 'Side effect (unrestorable): %s\n' "$new_list"
    fail "test-cmd added new tracked file(s) beyond the mutation that cannot be restored from HEAD: $new_list; left in place, never auto-removed"
  fi
}
trap restore EXIT

echo "## Negative control (negctl)"
before="$(snapshot)"
echo "Command: $test_cmd"
run_test; rc_before=$?
echo "Exit: $rc_before (green before mutation)"
[ "$rc_before" -eq 0 ] || fail "test was not green before the mutation"

baseline_diff=()
while IFS= read -r -d '' f; do baseline_diff+=("$f"); done < <(git -C "$root" diff HEAD --no-renames --name-only -z 2>/dev/null)

(cd "$root" && bash -c "$mutate_cmd") >/dev/null 2>&1
# staged or unstaged, NUL-delimited so a path with a space or a quote survives
while IFS= read -r -d '' f; do restore_files+=("$f"); done < <(git -C "$root" diff HEAD --no-renames --name-only -z 2>/dev/null)
echo "Mutation: $mutate_cmd"
if [ "${#baseline_diff[@]}" -gt 0 ]; then
  printf 'Baseline side write: %s\n' "$(printf '%s, ' "${baseline_diff[@]}" | sed 's/, $//')"
fi
mutate_only=()
if [ "${#restore_files[@]}" -gt 0 ]; then
  for f in "${restore_files[@]}"; do
    if [ "${#baseline_diff[@]}" -gt 0 ] && _path_in "$f" "${baseline_diff[@]}"; then
      continue
    fi
    mutate_only+=("$f")
  done
fi
if [ "${#mutate_only[@]}" -gt 0 ]; then
  printf 'Changed: %s\n' "$(printf '%s, ' "${mutate_only[@]}" | sed 's/, $//')"
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
  if [ "$red_used" -lt "$red_attempts" ]; then
    _beyond_mutate_set
    if [ "${#beyond[@]}" -gt 0 ]; then
      fail "attempt $red_used of $red_attempts was green but left tracked dirt beyond the mutation ($(printf '%s, ' "${beyond[@]}" | sed 's/, $//')); retries are unsafe against a polluted tree"
      break
    fi
  fi
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
