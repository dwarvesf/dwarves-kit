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
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/tests/test-alpha.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$1/tests/test-beta.sh"
}
RA() { local k="$1"; shift; bash "$k/tests/run-all.sh" "$@"; }
K="$TMP/kit"; mkkit "$K"
LOG="$TMP/state/dwarves-kit/suite-times.tsv"
export KIT_SUITE_TIMES_FILE="$LOG"

echo "[1] two runs append two lines per suite, six TSV fields each"
KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; RC1=$?
KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; RC2=$?
N="$(wc -l <"$LOG" 2>/dev/null | tr -d ' ')"
BAD="$(awk -F'\t' 'NF != 6 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9:]*Z$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ {c++} END {print c+0}' "$LOG" 2>/dev/null)"
if [ "$RC1" -eq 0 ] && [ "$RC2" -eq 0 ] && [ "$N" = 4 ] && [ "$BAD" = 0 ] \
   && [ "$(cut -f3 "$LOG" | sort -u | tr '\n' ' ')" = "test-alpha test-beta " ]; then ok "4 lines, both suites, well-formed"
else no "rc=$RC1/$RC2 lines=$N bad=$BAD log=$(cat "$LOG" 2>/dev/null)"; fi

echo "[2] a refused --all (exit 64) appends nothing"
RA "$K" --all >/dev/null 2>&1 </dev/null; RC=$?
if [ "$RC" -eq 64 ] && [ "$(wc -l <"$LOG" | tr -d ' ')" = 4 ]; then ok "refusal wrote no line"; else no "rc=$RC lines=$(wc -l <"$LOG")"; fi

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

echo "[5] tune: 2 x p95 with a 60 s floor, hand-set (commented) lines and the header kept"
{
  echo "# Per-suite ceilings (header kept)"
  echo "# second header line"
  echo "test-heavy 900"
  echo "test-hand 777  # hand-set: cold run is slow"
  echo "test-quick 60"
  echo "test-silent 123"
} >"$K/bin/test-affected.timeouts"
: >"$FIX"
for s in 80 90 100; do printf '2026-10-04T00:00:00Z\tabc\ttest-heavy\t%s\t0\t1\n' "$s" >>"$FIX"; done
for s in 1 1 2; do printf '2026-10-04T00:00:00Z\tabc\ttest-quick\t%s\t0\t1\n' "$s" >>"$FIX"; done
printf '2026-10-04T00:00:00Z\tabc\ttest-hand\t5\t0\t1\n2026-10-04T00:00:00Z\tabc\ttest-newcomer\t40\t0\t1\n' >>"$FIX"
OUT="$(KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] \
   && grep -qx 'test-heavy 200' <<<"$OUT" \
   && grep -qx 'test-quick 60' <<<"$OUT" \
   && grep -qx 'test-newcomer 80' <<<"$OUT" \
   && grep -qx 'test-silent 123' <<<"$OUT" \
   && grep -qx 'test-hand 777  # hand-set: cold run is slow' <<<"$OUT" \
   && grep -qx '# second header line' <<<"$OUT" \
   && [ "$(head -1 <<<"$OUT")" = "# Per-suite ceilings (header kept)" ]; then ok "dry run prints the rewritten file"
else no "rc=$RC out=$OUT"; fi
UNCHANGED="$(grep -c '^test-heavy 900$' "$K/bin/test-affected.timeouts")"
[ "$UNCHANGED" = 1 ] && ok "the dry run did not touch the file" || no "dry run wrote the file"
KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune --write >/dev/null 2>&1
KIT_SUITE_TIMES_FILE="$FIX" RA "$K" --times tune --write >/dev/null 2>&1
if grep -qx 'test-heavy 200' "$K/bin/test-affected.timeouts" && [ "$(grep -c '^# tuned from suite-times history' "$K/bin/test-affected.timeouts")" = 1 ]; then ok "--write rewrites in place, twice is idempotent (one marker line)"
else no "file=$(cat "$K/bin/test-affected.timeouts")"; fi
if awk '$1 !~ /^#/ && NF && $2 !~ /^[0-9]+$/ {bad=1} END {exit bad}' "$K/bin/test-affected.timeouts"; then ok "every data line is still '<suite> <seconds>'"; else no "malformed line"; fi

echo "[6] --all under KIT_RUN_ALL=1 prints one expected-wall line from the history"
OUT="$(KIT_RUN_ALL=1 RA "$K" --all 2>&1 </dev/null)"
N="$(grep -c '^run-all: expected wall about [0-9]*s' <<<"$OUT")"
[ "$N" = 1 ] && ok "one line: $(grep '^run-all: expected wall' <<<"$OUT" | cut -c1-60)" || no "lines=$N out=$OUT"

echo "[7] the log is capped to KIT_SUITE_TIMES_CAP lines"
CAPLOG="$TMP/cap/suite-times.tsv"
for i in 1 2 3; do KIT_SUITE_TIMES_CAP=3 KIT_SUITE_TIMES_FILE="$CAPLOG" KIT_RUN_ALL=1 RA "$K" --all >/dev/null 2>&1 </dev/null; done
[ "$(wc -l <"$CAPLOG" | tr -d ' ')" = 3 ] && ok "6 appended lines trimmed to the last 3" || no "lines=$(wc -l <"$CAPLOG")"

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
K2="$TMP/kit2"; mkdir -p "$K2/tests/lib"; cp "$DIR/tests/run-all.sh" "$K2/tests/run-all.sh"; cp "$DIR/tests/lib/run-lock.sh" "$K2/tests/lib/"
printf '#!/usr/bin/env bash\nexit 0\n' >"$K2/tests/test-solo.sh"
OUT="$(KIT_SUITE_TIMES_FILE="$TMP/k2/log.tsv" KIT_RUN_ALL=1 RA "$K2" --all 2>&1 </dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ ! -e "$TMP/k2/log.tsv" ] && grep -q '^run-all: all 1 suites passed' <<<"$OUT"; then ok "no helper, no log, same result"; else no "rc=$RC out=$OUT"; fi

echo
echo "run-all-times: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
