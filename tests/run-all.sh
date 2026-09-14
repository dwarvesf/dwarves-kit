#!/usr/bin/env bash
# run-all.sh -- run every tests/test-*.sh and report each.
#
# CI used to list one step per suite by hand. That list drifted to 74 of 131 files, so 57
# suites never ran anywhere and four of them had been red on master for some time. A green
# CI was checking 57% of what the repo had. A glob cannot drift.
#
# Suites run in PARALLEL, one process per core. They used to run one at a time, which cost
# 6m44s on ubuntu and 15m15s on macOS while the runner sat mostly idle: almost every suite
# is sub-second, and the wall clock was the sum of 146 of them. Output stays deterministic
# because results are collated in glob order after the run, not as each suite finishes.
#
# Usage: bash tests/run-all.sh [--only <pattern>]
# Env:   RUN_ALL_JOBS=<n>          parallel suites (default: core count; 1 = sequential)
#        RUN_ALL_TIMEOUT_SECS=<n>  per-suite ceiling (default: 300)
# Exit:  0 all green, 1 one or more failed (every failure is listed at the end).

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR" || exit 1

# Per-suite ceiling. One hung suite must not burn the whole CI job's budget.
TIMEOUT_SECS="${RUN_ALL_TIMEOUT_SECS:-300}"
_timeout() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else shift; "$@"; fi; }

# --- worker mode -------------------------------------------------------------
# The script re-invokes ITSELF as the xargs worker, so the parallel runner needs
# no second file on disk to keep in sync. Each worker owns its own log and status
# file, named after the suite: the old single /tmp/run-all-$$.log was one shared
# path per runner, which two concurrent suites would interleave into nonsense.
if [ "${1:-}" = "--run-one" ]; then
  suite="$2"; outdir="$3"
  name="$(basename "$suite" .sh)"
  if _timeout "$TIMEOUT_SECS" bash "$suite" >"$outdir/$name.log" 2>&1; then
    echo "ok" >"$outdir/$name.status"
    mark="."
  else
    echo "$?" >"$outdir/$name.status"
    mark="F"
  fi
  # Per-suite lines cannot stream: they are printed in glob order after the run.
  # Without this the terminal sits silent for the whole run. One character per
  # finished suite, on stderr so it never pollutes the parsable stdout report.
  printf '%s' "$mark" >&2
  exit 0
fi

ONLY=""
[ "${1:-}" = "--only" ] && ONLY="${2:-}"

_cores() {
  if command -v nproc >/dev/null 2>&1; then nproc
  elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu
  else echo 2
  fi
}
# DEFAULT IS 1: parallel execution is opt-in via RUN_ALL_JOBS until the ubuntu
# flake below is understood.
#
# Parallel runs are 2.3x faster and were green on a full dispatched matrix, on
# every macOS run, and on the PR runs. They then failed twice on master, on
# ubuntu only, on a DIFFERENT suite each time:
#   a1cd0c7  test-runs-dashboard       "the runs verb is missing from `mega --help`"
#   04c1eb1  test-understanding-wiring "the understanding-axis section names ADR-0031"
# Both are content greps over files IN THE REPO, and both suites pass alone,
# pass sequentially, and pass on macOS. Marking each one serial as it appeared
# just moved the failure to the next suite, so the cause is shared, not local to
# either file. The open hypothesis is that some suite rewrites a repo-tracked
# file in place for the length of an assertion, which a concurrent reader then
# greps mid-write. Until that is found and fixed, the default stays sequential.
#
# The kept machinery is not dead weight: it is what the investigation needs, and
# RUN_ALL_JOBS=4 reproduces the failure. RUN_ALL_JOBS=auto picks the capped core
# count, which is what the default will go back to once the flake is fixed. The
# cap is 4, not the core count: the heaviest suites spawn 100-800 subprocesses
# each, so one worker per core oversubscribes the box several times over. At -P
# 10 on a 10-core M4, three suites blew past the 300s ceiling.
JOBS="${RUN_ALL_JOBS:-1}"
if [ "$JOBS" = "auto" ]; then
  JOBS="$(_cores)"
  [ "$JOBS" -gt 4 ] && JOBS=4
fi

OUTDIR="$(mktemp -d)"
trap 'rm -rf "$OUTDIR"' EXIT

# --- phase 1: decide what runs, sequentially and cheaply ---------------------
# A suite may declare external tooling it cannot run without:
#   # requires: claude codex
# Missing tooling is a SKIP with the reason, never a failure. Some suites exercise agent
# CLIs that exist on an operator's machine and never on a CI runner; globbing everything
# without this turns "cannot run here" into "broken", which is how a green suite gets
# deleted for being noisy.
runlist="$OUTDIR/runlist"
parallellist="$OUTDIR/parallel"
seriallist="$OUTDIR/serial"
: >"$runlist"; : >"$parallellist"; : >"$seriallist"
skipped=0
for t in tests/test-*.sh; do
  [ -f "$t" ] || continue
  name="$(basename "$t" .sh)"
  [ -n "$ONLY" ] && case "$name" in *"$ONLY"*) : ;; *) continue ;; esac
  reqs="$(sed -n 's/^# requires:[[:space:]]*//p' "$t" | head -1)"
  missing=""
  for r in $reqs; do command -v "$r" >/dev/null 2>&1 || missing="$missing $r"; done
  if [ -n "$missing" ]; then
    printf '%-46s skip (needs%s)\n' "$name" "$missing"
    skipped=$((skipped + 1))
    continue
  fi
  printf '%s\n' "$t" >>"$runlist"
  # A suite may declare that it cannot share the machine:
  #   # serial: asserts kill timing, background load makes it flake
  # Such a suite measures WALL CLOCK behaviour, so a loaded box changes the thing
  # under test rather than just slowing it down. These run alone, after the
  # parallel batch drains.
  if sed -n 's/^# serial:[[:space:]]*//p' "$t" | head -1 | grep -q .; then
    printf '%s\n' "$t" >>"$seriallist"
  else
    printf '%s\n' "$t" >>"$parallellist"
  fi
done
count=$(wc -l <"$runlist" | tr -d ' ')
n_serial=$(wc -l <"$seriallist" | tr -d ' ')

# --- phase 2: run them, JOBS at a time ---------------------------------------
echo "run-all: $count suites, $JOBS at a time${n_serial:+, $n_serial serial}"
# Longest-first. With a few heavy suites among many trivial ones, the wall clock
# is decided by when the heaviest one STARTS: pick it up last and every worker
# waits on it alone at the end. Real per-suite cost is not known up front, so
# file size stands in for it, which ranks the known-heavy suites correctly.
# Reporting still reads $runlist, so the printed order stays glob order.
# wc -c, not stat: stat's format flag differs between BSD and GNU and this runs
# on both.
while IFS= read -r t; do
  printf '%s %s\n' "$(wc -c <"$t" | tr -d ' ')" "$t"
done <"$parallellist" | sort -rn | awk '{print $2}' >"$OUTDIR/schedule"
[ -s "$OUTDIR/schedule" ] && xargs -P "$JOBS" -I{} "$BASH" "$0" --run-one {} "$OUTDIR" <"$OUTDIR/schedule"

# Serial lane, after the parallel batch has fully drained, so the box is quiet.
while IFS= read -r t; do
  [ -n "$t" ] || continue
  "$BASH" "$0" --run-one "$t" "$OUTDIR"
done <"$seriallist"
echo "" >&2

# --- phase 3: collate in glob order ------------------------------------------
# A timeout and a red assertion are DIFFERENT facts and are accumulated separately. Both
# still exit 1, but a ceiling hit under load is not a broken suite, and flattening the two
# into one "FAILED ->" line cost two full re-runs to tell apart on 2026-09-12.
failed=""
timedout=""
while IFS= read -r t; do
  name="$(basename "$t" .sh)"
  log="$OUTDIR/$name.log"
  rc="$(cat "$OUTDIR/$name.status" 2>/dev/null || echo "missing")"
  printf '%-46s ' "$name"
  case "$rc" in
    ok)
      echo "ok"
      ;;
    124)
      echo "TIMEOUT (${TIMEOUT_SECS}s)"
      timedout="$timedout $name"
      # A killed suite printed no assertion, so the FAIL grep below would show nothing and
      # read as "failed for no reason". Say what actually happened and skip it.
      echo "      ! killed at ${TIMEOUT_SECS}s; no assertion failed, the suite ran out of time"
      sed 's/^/      | /' "$log" | tail -8
      ;;
    missing)
      echo "FAIL (no status written; the worker died)"
      failed="$failed $name"
      ;;
    *)
      echo "FAIL (rc=$rc)"
      failed="$failed $name"
      # Show the FAILING lines, then a short tail for context. A plain tail hid the real
      # assertion in a suite with 840 of them: the failure was 700 lines above the summary.
      # Strip ANSI colour BEFORE matching. Suites print "\033[0;31mFAIL\033[0m", so the
      # character before FAIL is `m`, and a [^a-z] guard never matches it. The first version
      # of this grep silently matched the word "fail" inside PASSING assertions instead
      # ("## Failure modes", "fail-safe present") and showed no real failure at all.
      _clean="$(sed $'s/\033\[[0-9;]*m//g' "$log")"
      if printf '%s\n' "$_clean" | grep -qE '(^|[[:space:]])FAIL([[:space:]]|:|$)'; then
        printf '%s\n' "$_clean" | grep -E '(^|[[:space:]])FAIL([[:space:]]|:|$)' | head -20 | sed 's/^/      ! /'
      fi
      sed 's/^/      | /' "$log" | tail -8
      ;;
  esac
done <"$runlist"

echo ""
if [ -n "$failed" ] || [ -n "$timedout" ]; then
  [ -n "$failed" ] && echo "run-all: FAILED ->$failed"
  if [ -n "$timedout" ]; then
    echo "run-all: TIMED OUT at ${TIMEOUT_SECS}s ->$timedout"
    echo "run-all: a timeout is this runner's ceiling, NOT an assertion failure; re-run the suite alone, or with RUN_ALL_TIMEOUT_SECS=<n>, before treating it as broken"
  fi
  echo "run-all: $count suites run${skipped:+, $skipped skipped for missing tooling}"
  exit 1
fi
echo "run-all: all $count suites passed${skipped:+, $skipped skipped for missing tooling}"
