#!/usr/bin/env bash
# run-all.sh keeps a per-host history of suite timings (tests/lib/suite-times.sh): every run
# appends one line per suite, `--times p95` reads it, `--times tune` rewrites the timeouts file
# by D4's rule, a missing log falls back cleanly, and a log that cannot be written never
# changes run-all's exit code. The history file is pointed at a temp dir through env, so
# nothing here touches the operator's real log.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export KIT_TEST_LOCK=0 KIT_LOAD_STUB=0
unset CI KIT_RUN_ALL KIT_SUITE_TIMES_CAP

mkkit() {  # $1 = dir: a kit-shaped tree with the REAL run-all.sh and the REAL helper
  mkdir -p "$1/tests/lib" "$1/bin"
  cp "$DIR/tests/run-all.sh" "$1/tests/run-all.sh"
  cp "$DIR/tests/lib/suite-times.sh" "$1/tests/lib/suite-times.sh"
  cp "$DIR/tests/lib/run-lock.sh" "$1/tests/lib/run-lock.sh"
  cp "$DIR/tests/lib/job-count.sh" "$1/tests/lib/job-count.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/tests/test-alpha.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/tests/test-beta.sh"
}
RA() { local k="$1"; shift; bash "$k/tests/run-all.sh" "$@"; }
K="$TMP/kit"; mkkit "$K"
LOG="$TMP/state/dwarves-kit/suite-times.tsv"
export KIT_SUITE_TIMES_FILE="$LOG"

echo "[1] two runs append two suite lines per suite plus one run line each, six TSV fields on a suite line"
KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; RC1=$?
KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; RC2=$?
N="$(awk -F'\t' '$3 !~ /^run:/' "$LOG" 2>/dev/null | wc -l | tr -d ' ')"
BAD="$(awk -F'\t' '$3 !~ /^run:/ && (NF != 6 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/) {c++} END {print c+0}' "$LOG" 2>/dev/null)"
RUNS="$(awk -F'\t' '$3 == "run:run-all" && NF == 8 && $7 == "kind=run" && $8 == "selected=2" && $5 == "0"' "$LOG" 2>/dev/null | wc -l | tr -d ' ')"
if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] && [ "$N" = 4 ] && [ "$BAD" = 0 ] && [ "$RUNS" = 2 ] \
   && [ "$(awk -F'\t' '$3 !~ /^run:/ {print $3}' "$LOG" | sort -u | tr '\n' ' ')" = "test-alpha test-beta " ]; then ok "4 suite lines, 2 run lines, both suites, well-formed"
else no "rc=$RC1/$RC2 suite lines=$N bad=$BAD runs=$RUNS log=$(cat "$LOG" 2>/dev/null)"; fi

echo "[2] a refused --all (exit 64) appends nothing"
RA "$K" --all >/dev/null 2>&1 </dev/null; RC=$?
if [ "$RC" -eq 64 ] && [ "$(wc -l <"$LOG" | tr -d ' ')" = 6 ]; then ok "refusal wrote no line"; else no "rc=$RC lines=$(wc -l <"$LOG")"; fi

echo "[3] the p95 verb reads the history (exit-0 runs only, nearest rank)"
FIX="$TMP/fix.tsv"
: >"$FIX"
for s in 1 2 3 4 5 6 7 8 9 10; do printf '2026-10-04T00:00:00Z\tabc1234\ttest-ladder\t%s\t0\t1.0\n' "$s" >>"$FIX"; done
printf '2026-10-04T00:00:00Z\tabc1234\ttest-ladder\t500\t124\t1.0\n' >>"$FIX"
OUT="$(KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times p95 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^test-ladder +10 runs +p95 10s$' <<<"$OUT"; then ok "10 passing runs, p95 10s, the 124 line ignored"
else no "rc=$RC out=$OUT"; fi
OUT="$(KIT_SUITE_TIMES_FILE="$LOG" RA "$K" --times p95 2>&1)"
if grep -qE '^test-alpha +2 runs' <<<"$OUT" && grep -qE '^test-beta +2 runs' <<<"$OUT"; then ok "the run-all history from case 1 reads back"
else no "out=$OUT"; fi

echo "[4] a missing log falls back cleanly: message on stderr, exit 0, nothing on stdout"
GONE="$TMP/nowhere/suite-times.tsv"
OUT="$(KIT_SUITE_TIMES_FILE="$GONE" RA "$K" --times p95 2>/dev/null)"; RC=$?
ERR="$(KIT_SUITE_TIMES_FILE="$GONE" RA "$K" --times p95 2>&1 >/dev/null)"
if [ "$RC" -eq 0 ] && [ -z "$OUT" ] && grep -q 'no history' <<<"$ERR"; then ok "p95 on a missing log"; else no "rc=$RC out=$OUT err=$ERR"; fi
printf '# header\ntest-alpha 300\n' >"$K/bin/test-affected.timeouts"
BEFORE="$(cksum <"$K/bin/test-affected.timeouts")"
KIT_SUITE_TIMES_FILE="$GONE" RA "$K" --times tune --write >/dev/null 2>&1; RC=$?
if [ "$RC" -eq 0 ] && [ "$BEFORE" = "$(cksum <"$K/bin/test-affected.timeouts")" ]; then ok "tune --write on a missing log leaves the timeouts file untouched"
else no "rc=$RC"; fi
OUT="$(KIT_RUN_ALL=1 KIT_SUITE_TIMES_FILE="$GONE.2" RA "$K" --all 2>&1 </dev/null)"
if ! grep -q 'expected wall' <<<"$OUT"; then ok "no history, no expected-wall line"; else no "out=$OUT"; fi

echo "[5] tune: 2 x p95, 60 s floor, 5 samples, never lowered, a kill is a floor, hand-set kept"
row() { printf '2026-10-04T00:00:00Z\tabc\t%s\t%s\t%s\t1\n' "$1" "$2" "$3" >>"$FIX"; }   # suite secs exit
{
  echo "# Per-suite ceilings (header kept)"
  echo "# second header line"
  echo "# Rule: seconds = max(60, 2 x p95 wall time). Measured as three full parallel runs of"
  echo "#   KIT_RUN_ALL=1 bash tests/run-all.sh --all --time"
  echo "# Sub-second suites measure 0 s and take the 60 s floor."
  echo "# One hand-set exception: kept verbatim."
  echo "test-heavy 900"
  echo "test-hand 777  # hand-set: cold run is slow"
  echo "test-quick 30"
  echo "test-few 500"
  echo "test-silent 123"
  echo "test-killed 100"
  echo "test-killedmany 100"
} >"$K/bin/test-affected.timeouts"
: >"$FIX"
for sec in 80 90 100 85 95; do row test-heavy "$sec" 0; done        # p95 100: candidate 200, existing 900 stays
for sec in 1 1 2 1 1; do row test-quick "$sec" 0; done              # candidate 60 >= 30: replaces
for sec in 10 10 10; do row test-few "$sec" 0; done                 # 3 samples: not enough
row test-hand 5 0
for sec in 40 38 39 40 37; do row test-newcomer "$sec" 0; done      # no line yet, 5 samples: added at 80
row test-thin 40 0; row test-thin 41 0                              # no line yet, 2 samples: not added
row test-killed 120 124; row test-killed 100 124                    # only kills: at least 2 x 120
for sec in 20 20 20 20 20; do row test-killedmany "$sec" 0; done; row test-killedmany 250 124   # kill 250 gives 500, beats candidate 60
row test-wedged 90 124                                              # no line yet, a kill at 90: 180
OUT="$(KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] \
   && grep -qx 'test-heavy 900' <<<"$OUT" \
   && grep -qx 'test-quick 60' <<<"$OUT" \
   && grep -qx 'test-few 500' <<<"$OUT" \
   && grep -qx 'test-newcomer 80' <<<"$OUT" \
   && ! grep -q 'test-thin' <<<"$OUT" \
   && grep -qx 'test-silent 123' <<<"$OUT" \
   && grep -qx 'test-killed 240' <<<"$OUT" \
   && grep -qx 'test-killedmany 500' <<<"$OUT" \
   && grep -qx 'test-wedged 180' <<<"$OUT" \
   && grep -qx 'test-hand 777  # hand-set: cold run is slow' <<<"$OUT"; then ok "each rule shows in the dry run"
else no "rc=$RC out=$OUT"; fi
OUT2="$(KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune --allow-lower 2>&1)"
grep -qx 'test-heavy 200' <<<"$OUT2" && ok "--allow-lower lets the candidate replace a higher line" || no "out=$OUT2"
grep -qx 'test-few 500' <<<"$OUT2" && ok "--allow-lower still needs 5 samples" || no "out=$OUT2"
grep -qx 'test-killed 240' <<<"$OUT2" && ok "--allow-lower keeps a kill as a floor" || no "out=$OUT2"
RA "$K" --times tune --nonsense >/dev/null 2>&1; [ "$?" -eq 64 ] && ok "an unknown tune flag exits 64" || no "unknown flag accepted"
UNCHANGED="$(grep -c '^test-heavy 900$' "$K/bin/test-affected.timeouts")"
[ "$UNCHANGED" = 1 ] && ok "the dry run did not touch the file" || no "dry run wrote the file"
KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune --write >/dev/null 2>&1
KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune --write >/dev/null 2>&1
F2="$K/bin/test-affected.timeouts"
if grep -qx 'test-quick 60' "$F2" && [ "$(grep -c '^# Source: suite-times history' "$F2")" = 1 ] && [ "$(grep -c '^# Rule:' "$F2")" = 1 ]; then ok "--write rewrites in place; twice is idempotent (one Rule, one Source line)"
else no "file=$(cat "$F2")"; fi
if ! grep -q 'three full parallel runs' "$F2" && ! grep -q 'KIT_RUN_ALL=1 bash tests/run-all.sh --all' "$F2" \
   && grep -q '^# Source: suite-times history, 26 exit-0 samples across 7 suites, runs 2026-10-04 to 2026-10-04 (tuned ' "$F2" \
   && [ "$(head -1 "$F2")" = "# Per-suite ceilings (header kept)" ] && grep -qx '# second header line' "$F2" && grep -qx '# One hand-set exception: kept verbatim.' "$F2"; then ok "the measurement paragraph is rewritten: source, sample count, date range; the rest of the header kept"
else no "header=$(head -14 "$F2")"; fi
if awk '$1 !~ /^#/ && NF && $2 !~ /^[0-9]+$/ {bad=1} END {exit bad}' "$F2"; then ok "every data line is still '<suite> <seconds>'"; else no "malformed line"; fi

echo "[6] --all under KIT_RUN_ALL=1 prints one expected-wall line from the history"
OUT="$(KIT_RUN_ALL=1 RA "$K" --all 2>&1 </dev/null)"
N="$(grep -c '^run-all: expected wall about [0-9]*s' <<<"$OUT")"
[ "$N" = 1 ] && ok "one line: $(grep '^run-all: expected wall' <<<"$OUT" | cut -c1-60)" || no "lines=$N out=$OUT"

echo "[7] the log is capped to KIT_SUITE_TIMES_CAP lines"
CAPLOG="$TMP/cap/suite-times.tsv"
for i in 1 2 3; do KIT_SUITE_TIMES_CAP=3 KIT_SUITE_TIMES_FILE="$CAPLOG" KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; done
[ "$(wc -l <"$CAPLOG" | tr -d ' ')" = 3 ] && ok "9 appended lines trimmed to the last 3" || no "lines=$(wc -l <"$CAPLOG")"

echo "[8] NEGATIVE CONTROL: an unwritable state dir never changes run-all's exit code"
BLOCK="$TMP/afile"; : >"$BLOCK"                      # a regular file where a directory must go
printf '#!/usr/bin/env bash\necho "FAIL: a real assertion"\nexit 1\n' >"$K/tests/test-red.sh"
KIT_SUITE_TIMES_FILE="$BLOCK/x/suite-times.tsv" KIT_RUN_ALL=1 RA "$K" --all >"$TMP/red.out" 2>&1 </dev/null; RCR=$?
mv -f "$K/tests/test-red.sh" "$TMP/red.discard"
KIT_SUITE_TIMES_FILE="$BLOCK/x/suite-times.tsv" KIT_RUN_ALL=1 RA "$K" --all >"$TMP/green.out" 2>&1 </dev/null; RCG=$?
if [ "$RCR" -eq 1 ] && grep -q '^run-all: FAILED ->.*test-red' "$TMP/red.out"; then ok "red suite still exits 1 with the log unwritable"; else no "rc=$RCR"; fi
if [ "$RCG" -eq 0 ] && grep -q '^run-all: all 2 suites passed' "$TMP/green.out"; then ok "green run still exits 0 with the log unwritable"; else no "rc=$RCG"; fi
[ -f "$BLOCK" ] && [ ! -d "$BLOCK" ] && ok "the blocker is untouched (nothing was written there)" || no "blocker changed"

echo "[9] a kit without the helper (older fixtures) runs exactly as before"
K2="$TMP/kit2"; mkdir -p "$K2/tests/lib"; cp "$DIR/tests/run-all.sh" "$K2/tests/run-all.sh"; cp "$DIR/tests/lib/run-lock.sh" "$DIR/tests/lib/job-count.sh" "$K2/tests/lib/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$K2/tests/test-solo.sh"
OUT="$(KIT_SUITE_TIMES_FILE="$TMP/k2/log.tsv" KIT_RUN_ALL=1 RA "$K2" --all 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ ! -e "$TMP/k2/log.tsv" ] && grep -q '^run-all: all 1 suites passed' <<<"$OUT"; then ok "no helper, no log, same result"; else no "rc=$RC out=$OUT"; fi

echo "[10] --times runs: the last 20 run lines, p50 and p95 wall per entry point"
RL="$TMP/runs.tsv"; : >"$RL"
for i in $(seq 1 25); do printf '2026-10-04T00:00:%02dZ\tabc\trun:run-all\t%s\t0\t1\tkind=run\tselected=9\n' "$i" "$((i * 10))" >>"$RL"; done
printf '2026-10-04T01:00:00Z\tabc\trun:test-affected\t5\t0\t1\tkind=run\tselected=3\n2026-10-04T01:00:01Z\tabc\trun:test-affected\t15\t1\t1\tkind=run\tselected=4\n' >>"$RL"
printf '2026-10-04T01:00:02Z\tabc\ttest-alpha\t7\t0\t1\n' >>"$RL"
OUT="$(KIT_SUITE_TIMES_FILE="$RL" RA "$K" --times runs 2>&1)"; RC=$?
ROWS="$(grep -c 'selected=' <<<"$OUT")"
if [ "$RC" -eq 0 ] && [ "$ROWS" = 20 ] && grep -qE '^run-all +18 runs +p50 [0-9]+s +p95 [0-9]+s' <<<"$OUT" && grep -qE '^test-affected +2 runs +p50 5s +p95 15s' <<<"$OUT" && ! grep -q 'test-alpha' <<<"$OUT"; then ok "20 rows printed, per-entry p50/p95, suite lines excluded: $(grep '^run-all ' <<<"$OUT" | tr -s ' ')"
else no "rc=$RC rows=$ROWS out=$OUT"; fi
OUT="$(KIT_SUITE_TIMES_FILE="$TMP/nowhere2.tsv" RA "$K" --times runs 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q 'no history' <<<"$OUT"; then ok "runs on a missing log falls back cleanly"; else no "rc=$RC out=$OUT"; fi
OUT="$(KIT_SUITE_TIMES_FILE="$LOG" RA "$K" --times p95 2>&1)"
! grep -q 'run:' <<<"$OUT" && ok "run lines never show up as suites in p95" || no "out=$OUT"

echo "[11] run-all warns once, before the parallel phase, and still exits with the suites' verdict"
mkdir -p "$K/lib/host"; cp "$DIR/lib/host/load-warn.sh" "$K/lib/host/load-warn.sh"; mkdir -p "$K/lib/config"; cp "$DIR/lib/config/kit-config.sh" "$K/lib/config/"
OUT="$(KIT_LOAD_STUB=77 KIT_RUN_ALL=1 RA "$K" --all 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(grep -c '^load-warn:' <<<"$OUT")" = 1 ] && [ "$(grep -n '^load-warn:' <<<"$OUT" | cut -d: -f1)" -lt "$(grep -n '^run-all: 2 suites' <<<"$OUT" | cut -d: -f1)" ]; then ok "one warning line, ahead of the suites line, exit 0"
else no "rc=$RC out=$OUT"; fi
OUT="$(KIT_LOAD_STUB=1 KIT_RUN_ALL=1 RA "$K" --all 2>&1 </dev/null)"
! grep -q '^load-warn:' <<<"$OUT" && ok "a quiet host prints no warning" || no "out=$OUT"
printf '#!/usr/bin/env bash\nexit 1\n' >"$K/tests/test-red2.sh"
KIT_LOAD_STUB=77 KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; RC=$?
mv -f "$K/tests/test-red2.sh" "$TMP/red2.discard"
[ "$RC" -eq 1 ] && ok "a loaded host with a red suite still exits 1" || no "rc=$RC"
RROW="$(awk -F'\t' '$3 == "run:run-all" && $5 == "1"' "$LOG" | tail -1)"
[ -n "$RROW" ] && ok "a failing run is recorded with exit 1 on its run line" || no "no failing run line"

echo "[12] --failed reruns only the suites whose latest history line did not pass"
K3="$TMP/kit3"; mkkit "$K3"
for n in gamma delta eps; do printf '#!/usr/bin/env bash\nexit 0\n' >"$K3/tests/test-$n.sh"; done
H="$TMP/failed-history.tsv"
hrow() { printf '2026-10-08T00:00:00Z\tabc1234\t%s\t%s\t%s\t1.0\n' "$1" "$2" "$3" >>"$H"; }   # suite secs exit
: >"$H"
hrow test-alpha 5 1                      # failed, never reran: picked
hrow test-beta 5 1; hrow test-beta 4 0   # failed, then passed: NOT picked
hrow test-gamma 300 124                  # a timeout is a failure: picked
hrow test-delta 3 255                    # the worker died: picked
hrow test-eps 2 0                        # always green: NOT picked
hrow test-gone 9 1                       # failed, but the suite is no longer on disk: ignored
printf '2026-10-08T00:00:01Z\tabc1234\trun:run-all\t400\t1\t1.0\tkind=run\tselected=6\n' >>"$H"   # run lines never count as suites
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
ran_ok() { grep -qE "^$1 +ok" <<<"$OUT"; }   # did suite $1 run and pass in $OUT
if [ "$RC" -eq 0 ] \
   && ran_ok test-alpha && ran_ok test-gamma && ran_ok test-delta \
   && ! ran_ok test-beta && ! ran_ok test-eps && ! grep -qE '^test-gone ' <<<"$OUT" \
   && grep -q '^run-all: 3 suites' <<<"$OUT" && grep -q '^run-all: all 3 suites passed' <<<"$OUT"; then
  ok "exactly alpha (exit 1), gamma (124) and delta (255) ran; beta (failed then passed), eps and the vanished suite did not"
else no "rc=$RC out=$OUT"; fi

echo "[12b] a suite that failed and then passed is not picked: only that history means nothing to run"
: >"$H"; hrow test-alpha 5 1; hrow test-alpha 4 0; hrow test-beta 1 0
BEFORE="$(wc -l <"$H" | tr -d ' ')"
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 1 ] && grep -q '^run-all: --failed: no failed suite' <<<"$OUT" \
   && ! grep -qE '^test-[a-z]+ +ok' <<<"$OUT" && [ "$(wc -l <"$H" | tr -d ' ')" = "$BEFORE" ]; then
  ok "one line, exit 0, no suite ran, no history line appended"
else no "rc=$RC out=$OUT"; fi

echo "[12c] an empty or missing history means nothing runs: one line, exit 0"
: >"$H"
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 1 ] && grep -q '^run-all: --failed: ' <<<"$OUT" \
   && ! grep -qE '^test-[a-z]+ +ok' <<<"$OUT" && [ ! -s "$H" ]; then
  ok "empty history: one line, nothing run, nothing logged"
else no "rc=$RC out=$OUT"; fi
OUT="$(KIT_SUITE_TIMES_FILE="$TMP/never/there.tsv" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(wc -l <<<"$OUT" | tr -d ' ')" = 1 ] && grep -q 'no history' <<<"$OUT" \
   && ! grep -qE '^test-[a-z]+ +ok' <<<"$OUT" && [ ! -e "$TMP/never/there.tsv" ]; then
  ok "missing history: one line naming it, nothing run, nothing created"
else no "rc=$RC out=$OUT"; fi

echo "[12d] --failed adds the always-on lints (as --changed does) only when something failed"
printf '#!/usr/bin/env bash\n# always: fixture tree-wide lint\nexit 0\n' >"$K3/tests/test-lint.sh"
: >"$H"; hrow test-alpha 5 1
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && grep -qE '^test-alpha +ok' <<<"$OUT" && grep -qE '^test-lint +ok' <<<"$OUT" && ! grep -qE '^test-gamma +ok' <<<"$OUT"; then
  ok "failed suite plus the always-on lint"
else no "rc=$RC out=$OUT"; fi
: >"$H"; hrow test-alpha 5 0
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && ! grep -qE '^test-lint +ok' <<<"$OUT" && grep -q '^run-all: --failed: no failed suite' <<<"$OUT"; then
  ok "nothing failed: the lint does not run alone"
else no "rc=$RC out=$OUT"; fi

echo "[12e] the rerun is logged, so the next --failed sees the suite green"
: >"$H"; hrow test-gamma 5 1
KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed >/dev/null 2>&1 </dev/null
OUT="$(KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^run-all: --failed: no failed suite' <<<"$OUT" && ! grep -qE '^test-[a-z]+ +ok' <<<"$OUT"; then
  ok "gamma failed, was rerun green, and is no longer picked"
else no "rc=$RC out=$OUT"; fi

echo "[12f] a suite that is still red after the rerun keeps --failed exiting 1"
printf '#!/usr/bin/env bash\necho "FAIL: still red"\nexit 1\n' >"$K3/tests/test-red3.sh"
: >"$H"; hrow test-red3 5 1
KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed >"$TMP/red3.out" 2>&1 </dev/null; RC=$?
KIT_SUITE_TIMES_FILE="$H" RA "$K3" --failed >"$TMP/red3b.out" 2>&1 </dev/null; RC2=$?
if [ "$RC" -eq 1 ] && [ "$RC2" -eq 1 ] && grep -q '^run-all: FAILED ->.*test-red3' "$TMP/red3.out" \
   && ! grep -qE '^test-(alpha|beta|gamma|delta|eps) ' "$TMP/red3.out"; then ok "only the red suite ran, red stays red, exit 1 both times"; else no "rc=$RC/$RC2"; fi
mv -f "$K3/tests/test-red3.sh" "$TMP/red3.discard"

echo
echo "run-all-times: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
