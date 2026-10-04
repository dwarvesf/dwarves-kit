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
# Usage: bash tests/run-all.sh [--all | --only <pattern> | --changed [<base>]] [--time]
#        Bare (no argument) is --changed: only the suites the diff against <base> touches
#        (default base: the merge-base with origin/master), plus the always-on lints. The
#        local check. --all is the full glob, what CI and the nightly job run; it refuses
#        (exit 64) unless CI is non-empty or KIT_RUN_ALL=1.
#        --time appends each suite's elapsed seconds to its report line and prints a
#        slowest-10 block after the report. It may appear before or after the mode
#        argument, and combines with --all, --only and --changed.
#        --times <verb> reads the suite timing history instead of running anything: p95 (per-suite
#        p95), runs (the last 20 runs, p50 and p95 wall per entry point), expected (wall of a full
#        run), tune [--write] [--allow-lower] (bin/test-affected.timeouts from the p95s, D4's rule). Every run appends one line per suite to that history, see
#        tests/lib/suite-times.sh. A write failure there never changes this script's exit code.
# Env:   KIT_RUN_ALL=1             allow --all outside CI (the nightly job sets it)
#        RUN_ALL_JOBS=<n>         parallel suites (default: auto on macOS, 1 elsewhere)
#        RUN_ALL_TIMEOUT_SECS=<n>  per-suite ceiling (default: 300; bin/test-affected.timeouts lists the
#                                  per-suite values). When set it applies to every suite.
# Exit:  0 all green, 1 one or more failed (every failure is listed at the end).

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$KIT_DIR" || exit 1

# History verbs read a log and run no suite: no refusal, no lock.
if [ "${1:-}" = "--times" ]; then
  shift; exec bash "$KIT_DIR/tests/lib/suite-times.sh" "${@:-p95}"
fi

# --all is the ~25 minute full glob, and it holds the per-host test lock below for all of it,
# so one session's --all queued every other session's run behind it. A README line saying
# "release only" did not stop that; this refusal does. GitHub Actions sets CI=true, the
# nightly job sets KIT_RUN_ALL=1. Checked before the lock, so a refused run never waits on it.
for _a in "$@"; do
  if [ "$_a" = "--all" ] && [ -z "${CI:-}" ] && [ "${KIT_RUN_ALL:-}" != "1" ]; then
    echo "run-all: --all is for CI and the nightly job (KIT_RUN_ALL=1); locally run: bash tests/run-all.sh --changed --time" >&2
    exit 64
  fi
done

# One heavy run at a time per host (tests/lib/run-lock.sh); re-execs this script under the lock.
source "$KIT_DIR/tests/lib/run-lock.sh"; run_lock_exec "$KIT_DIR/tests/run-all.sh" "$@"

# --time is order-free, so it is pulled out of the argument list before the positional
# parsing below ($1 is the mode, $2 is --only's pattern or --changed's base) rather than
# being threaded through it.
TIME=0
_args=()
for _a in "$@"; do
  if [ "$_a" = "--time" ]; then TIME=1; else _args+=("$_a"); fi
done
set -- ${_args[@]+"${_args[@]}"}

# Per-suite ceiling. One hung suite must not burn the whole CI job's budget.
TIMEOUT_SECS="${RUN_ALL_TIMEOUT_SECS:-300}"
# Per-suite ceilings live in ONE data file, bin/test-affected.timeouts (`<suite> <seconds>`, 2 x the
# measured p95 wall time under a parallel run, floor 60; the header there says how and when). bin/test-affected
# reads the same file. A suite with no line gets the default above.
# An explicit RUN_ALL_TIMEOUT_SECS wins for every suite (it is the operator's override).
suite_timeout() {
  if [ -n "${RUN_ALL_TIMEOUT_SECS:-}" ]; then echo "$RUN_ALL_TIMEOUT_SECS"; return; fi
  local listed=""
  if [ -r "$KIT_DIR/bin/test-affected.timeouts" ]; then
    listed="$(awk -v n="$1" '$1 == n && $2 ~ /^[0-9]+$/ { print $2; exit }' "$KIT_DIR/bin/test-affected.timeouts")"
  fi
  echo "${listed:-$TIMEOUT_SECS}"
}
_timeout() { if command -v timeout >/dev/null 2>&1; then timeout "$@"; else shift; "$@"; fi; }

# --- worker mode -------------------------------------------------------------
# The script re-invokes ITSELF as the xargs worker, so the parallel runner needs
# no second file on disk to keep in sync. Each worker owns its own log and status
# file, named after the suite: the old single /tmp/run-all-$$.log was one shared
# path per runner, which two concurrent suites would interleave into nonsense.
if [ "${1:-}" = "--run-one" ]; then
  suite="$2"; outdir="$3"
  name="$(basename "$suite" .sh)"
  # Whole seconds via date, not EPOCHREALTIME: Apple ships bash 3.2, which has neither
  # that variable nor the arithmetic to make sub-second numbers worth the trouble. The
  # stamp is written unconditionally; only the collate loop cares whether --time was given.
  _t0="$(date +%s)"
  _limit="$(suite_timeout "$name")"
  echo "$_limit" >"$outdir/$name.limit"
  if _timeout "$_limit" bash "$suite" >"$outdir/$name.log" 2>&1; then
    echo "ok" >"$outdir/$name.status"
    mark="."
  else
    echo "$?" >"$outdir/$name.status"
    mark="F"
  fi
  echo "$(( $(date +%s) - _t0 ))" >"$outdir/$name.time"
  # Per-suite lines cannot stream: they are printed in glob order after the run.
  # Without this the terminal sits silent for the whole run. One character per
  # finished suite, on stderr so it never pollutes the parsable stdout report.
  printf '%s' "$mark" >&2
  exit 0
fi

ONLY=""
[ "${1:-}" = "--only" ] && ONLY="${2:-}"
# Bare invocation is --changed. The full glob is what CI runs and takes 13-15 minutes
# sequential on a Mac; nobody types that by accident, so it is spelled --all.
MODE="${1:-}"
[ -z "$MODE" ] && MODE="--changed"

_cores() {
  if command -v nproc >/dev/null 2>&1; then nproc
  elif command -v sysctl >/dev/null 2>&1; then sysctl -n hw.ncpu
  else echo 2
  fi
}
# DEFAULT IS 1 ON LINUX: parallel execution is opt-in via RUN_ALL_JOBS there until
# the ubuntu flake below is understood. macOS defaults to auto: every macOS run of
# the parallel batch, CI and local, has been green, and the flake has never shown
# on a Mac, so the platform where the evidence holds gets the 2.3x.
#
# Parallel runs are 2.3x faster and were green on a full dispatched matrix, on
# every macOS run, and on the PR runs. They then failed twice on master, on
# ubuntu only, on a DIFFERENT suite each time: first test-runs-dashboard, then
# test-understanding-wiring, each on one assertion out of twenty-odd green ones.
# (The failing assertion text is deliberately NOT quoted here: docs/FEATURES.md
# is generated by scanning test files for feature names, so quoting an assertion
# wires this runner to whatever feature it mentions and breaks the freshness
# pin. Read the two commits for the exact wording.)
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
JOBS="${RUN_ALL_JOBS:-}"
if [ -z "$JOBS" ]; then
  case "$(uname -s)" in Darwin) JOBS=auto ;; *) JOBS=1 ;; esac
fi
if [ "$JOBS" = "auto" ]; then
  JOBS="$(_cores)"
  [ "$JOBS" -gt 4 ] && JOBS=4
fi

OUTDIR="$(mktemp -d)"
trap 'rm -rf "$OUTDIR"' EXIT

# --- --changed: pick suites by the diff ---------------------------------------
# The full glob is 13-15 minutes sequential on a Mac, and a branch that touches one lib
# file needs a handful of those suites. The selection rule lives in ONE place,
# bin/test-affected --list (path or long-basename references, changed suites, lib/<mod>
# suites, tests/test-meta.sh when the diff touches what it reads); this runner only executes
# what it names, in parallel.
#
# A suite may also declare that it must run on every diff:
#   # always: lints every KIT_* env read in the tree against the module registry
# Those are the tree-wide lints (naming contract, config registry, personal paths,
# scattered ids, engine boundary, the registry pin). They fail on a file you ADDED while
# naming no file you touched, so no diff-derived pick can reach them.
# Over-picking is fine; a suite this misses is one the changed file never appears in.
PICKED=""
if [ "$MODE" = "--changed" ]; then
  base="${2:-}"
  if [ -z "$base" ]; then
    base="$(git merge-base HEAD origin/master 2>/dev/null \
         || git merge-base HEAD master 2>/dev/null \
         || echo HEAD)"
  fi
  listing="$OUTDIR/listing"
  if ! bash "$KIT_DIR/bin/test-affected" --base "$base" --list >"$listing" 2>&1; then
    echo "run-all: bin/test-affected --list failed; running everything"
    sed 's/^/  /' "$listing"
  elif grep -q '^test-affected: no changes' "$listing"; then
    echo "run-all: --changed found no diff against $(git rev-parse --short "$base"); running everything"
  else
    PICKED="$OUTDIR/picked"
    awk '$1 ~ /^tests\/test-.*\.sh$/ {print $1}' "$listing" | sort -u >"$PICKED"
    named=$(awk '$1 ~ /^tests\/test-.*\.sh$/ && $0 !~ /\(always\)/ {print $1}' "$listing" | sort -u | wc -l | tr -d ' ')
    nchanged=$(sed -n 's/^test-affected: \([0-9]*\) changed files.*/\1/p' "$listing")
    grep -l '^# always:' tests/test-*.sh >>"$PICKED" 2>/dev/null
    sort -u -o "$PICKED" "$PICKED"
    # A picked `# runner:` file only relays sibling suites; the runner itself is
    # skipped below, so a pick naming it (bin/test-affected's meta_input picks
    # tests/test-meta.sh) would silently drop the whole group. Expand it into the
    # suites its `# runner-suites:` line names (sibling glob when it has none).
    # Done here, before the glob loop, because the runners' siblings sort before
    # the runner in glob order ('-' < '.'), too late for in-loop expansion.
    while IFS= read -r t; do
      [ -f "$t" ] && grep -q '^# runner:' "$t" || continue
      _sibs="$(sed -n 's/^# runner-suites: //p' "$t" | tr ' ' '\n' \
        | sed -n "s/^\\(..*\\)$/tests\\/$(basename "$t" .sh)-\\1.sh/p")"
      if [ -n "$_sibs" ]; then printf '%s\n' "$_sibs" >>"$PICKED"
      else printf '%s\n' "${t%.sh}"-*.sh >>"$PICKED"; fi
      sort -u -o "$PICKED" "$PICKED"
    done <"$PICKED"
    echo "run-all: --changed against $(git rev-parse --short "$base"): ${nchanged:-0} changed files -> $(wc -l <"$PICKED" | tr -d ' ') suites ($named named, the rest always-on)"
    sed 's/^/  /' "$PICKED"
    if [ "$named" -eq 0 ]; then
      echo "run-all: no suite names any of the changed files; only the always-on lints run"
      sed -n 's/^  UNCOVERED //p' "$listing" | sed 's/^/  /'
    fi
    [ -s "$PICKED" ] || exit 0
  fi
fi

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
  [ -n "$PICKED" ] && ! grep -qxF -- "$t" "$PICKED" && continue
  # A `# runner:` file only relays sibling suites, which the same glob already
  # schedules one by one; running it too would count every assert twice.
  grep -q '^# runner:' "$t" && continue
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

# One warning line on a loaded host, once, before the parallel phase (warning only; it exits 0).
[ -f "$KIT_DIR/lib/host/load-warn.sh" ] && { bash "$KIT_DIR/lib/host/load-warn.sh" "this run-all run" || true; }

# --- phase 2: run them, JOBS at a time ---------------------------------------
_run_t0="$(date +%s)"
echo "run-all: $count suites, $JOBS at a time${n_serial:+, $n_serial serial}"
# --all outside CI is the expensive run; say how long the history expects it to take.
# Silent without a history (or without the helper), never a failure.
if [ "$MODE" = "--all" ] && [ -z "${CI:-}" ] && [ "${KIT_RUN_ALL:-}" = "1" ] && [ -f "$KIT_DIR/tests/lib/suite-times.sh" ]; then
  sed 's|.*/||; s|\.sh$||' "$runlist" | bash "$KIT_DIR/tests/lib/suite-times.sh" expected "$JOBS" 2>/dev/null || true
fi
_load_start="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}')"
[ -n "$_load_start" ] || _load_start="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
[ -n "$_load_start" ] || _load_start=0
: >"$OUTDIR/times.tsv"
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
  # One history row per suite (suite, seconds, exit); suite-times.sh adds the time, sha and load.
  _trc="$rc"; case "$rc" in ok) _trc=0 ;; missing) _trc=255 ;; esac
  printf '%s\t%s\t%s\n' "$name" "$(cat "$OUTDIR/$name.time" 2>/dev/null || echo 0)" "$_trc" >>"$OUTDIR/times.tsv" 2>/dev/null
  secs=""
  [ "$TIME" = 1 ] && secs=" ($(cat "$OUTDIR/$name.time" 2>/dev/null || echo 0)s)"
  printf '%-46s ' "$name"
  case "$rc" in
    ok)
      echo "ok$secs"
      ;;
    124)
      limit="$(cat "$OUTDIR/$name.limit" 2>/dev/null || echo "$TIMEOUT_SECS")"
      echo "TIMEOUT (${limit}s)$secs"
      timedout="$timedout $name"
      [ "$limit" = "$TIMEOUT_SECS" ] || timedout="${timedout}(${limit}s)"
      # A killed suite printed no assertion, so the FAIL grep below would show nothing and
      # read as "failed for no reason". Say what actually happened and skip it.
      echo "      ! killed at ${limit}s; no assertion failed, the suite ran out of time"
      sed 's/^/      | /' "$log" | tail -8
      ;;
    missing)
      echo "FAIL (no status written; the worker died)$secs"
      failed="$failed $name"
      ;;
    *)
      echo "FAIL (rc=$rc)$secs"
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

# Append this run to the per-host timing history. Best effort: any failure is swallowed so the
# exit code below stays the suites' verdict.
if [ -f "$KIT_DIR/tests/lib/suite-times.sh" ]; then
  _hist_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
  _hist_rc=0; { [ -z "$failed" ] && [ -z "$timedout" ]; } || _hist_rc=1
  bash "$KIT_DIR/tests/lib/suite-times.sh" append "$OUTDIR/times.tsv" "$_hist_sha" "$_load_start" >/dev/null 2>&1 || true
  bash "$KIT_DIR/tests/lib/suite-times.sh" append-run run-all "$count" "$(( $(date +%s) - _run_t0 ))" "$_hist_rc" "$_hist_sha" "$_load_start" >/dev/null 2>&1 || true
fi

# The ten worst offenders, so a slow run says where the time went without reading the
# whole report. Ten, not all of them: the tail is a long list of sub-second suites.
if [ "$TIME" = 1 ]; then
  echo ""
  echo "run-all: slowest:"
  while IFS= read -r t; do
    name="$(basename "$t" .sh)"
    printf '%s %s\n' "$(cat "$OUTDIR/$name.time" 2>/dev/null || echo 0)" "$name"
  done <"$runlist" | sort -rn | head -10 | while read -r s n; do printf '  %ss %s\n' "$s" "$n"; done
fi

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
