#!/usr/bin/env bash
# bin/test-affected runs the selected suites in parallel: the per-suite verdicts and the exit code
# are the serial ones, a TIMEOUT in one suite stops no other, the report order is the selection order
# whatever finishes first, the schedule is longest-listed-limit first, a `# serial:` suite runs alone
# after the batch, and the job count halves above the load-warn threshold.
#
# Concurrency is proved with a barrier, not a clock: each suite touches its own file and passes only
# once every sibling has too, so it can pass only while all of them run at the same time. With one job
# the barrier times out and the suite fails. NEGATIVE CONTROL: force the job count to 1 in the binary
# and the barrier case goes red.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TA="$KIT_DIR/bin/test-affected"
PASS=0; FAIL=0
ok()  { echo "  ok: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1" >&2; FAIL=$((FAIL+1)); }
has() { grep -qF -- "$2" <<<"$1" && ok "$3" || bad "$3 (missing '$2' in: $1)"; }
hasnt() { grep -qF -- "$2" <<<"$1" && bad "$3 (unexpected '$2' in: $1)" || ok "$3"; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export KIT_LOAD_WARN=100000 TA_MARK="$W/mark" TA_BAR="$W/bar"
unset KIT_LEDGER_DIR KIT_LOAD_STUB TEST_AFFECTED_JOBS TEST_AFFECTED_TIMEOUT_SECS
export DWARVES_KIT_LOG_DIR="$W/logs" KIT_SUITE_TIMES_FILE="$W/hist.tsv"

# The binary runs from $W/tabin so its siblings (job count, load check, history, log dir) resolve in the fixture.
mkdir -p "$W/tabin" "$W/lib/telemetry" "$W/lib/config" "$W/lib/host" "$W/tests/lib"
cp "$TA" "$W/tabin/test-affected"
cp "$KIT_DIR/lib/telemetry/kit-log-dir.sh" "$W/lib/telemetry/"; cp "$KIT_DIR/lib/config/kit-config.sh" "$W/lib/config/"
cp "$KIT_DIR/lib/host/load-warn.sh" "$W/lib/host/"
cp "$KIT_DIR/tests/lib/suite-times.sh" "$KIT_DIR/tests/lib/job-count.sh" "$W/tests/lib/"
TA2="$W/tabin/test-affected"

R="$W/repo"; mkdir -p "$R/tests" "$R/lib/x"; cd "$R"
git init -q -b main . 2>/dev/null && git config user.email t@t && git config user.name t
echo 1.0.0 > VERSION
for n in 1 2 3 4; do printf 'echo %s\n' "$n" > "lib/x/m$n.sh"; done
reset_suites() {  # every suite passes at once and names its own lib file
  for n in 1 2 3 4; do
    printf '#!/bin/bash\necho "start-s%s" >> "$TA_MARK"\nbash lib/x/m%s.sh >/dev/null\necho "end-s%s" >> "$TA_MARK"\n' "$n" "$n" "$n" > "tests/test-s$n.sh"
  done
}
reset_suites
git add -A && git commit -qm base
BASE="$(git rev-parse HEAD)"
touch_all() { for n in 1 2 3 4; do echo "# $1" >> "lib/x/m$n.sh"; done; }
fresh() { rm -rf "$W/logs" "$W/bar" "$TA_MARK" "$W/hist.tsv"; mkdir -p "$W/bar"; }
# A suite that passes only while its 3 siblings (s1..s3) run too.
barrier_suite() {
  printf '#!/bin/bash\ntouch "$TA_BAR/s%s"\nbash lib/x/m%s.sh >/dev/null\ni=0\nwhile [ "$(ls "$TA_BAR" | wc -l | tr -d " ")" -lt 3 ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done\n[ "$(ls "$TA_BAR" | wc -l | tr -d " ")" -ge 3 ]\n' "$1" "$1" > "tests/test-s$1.sh"
}
touch_all c1

echo "== 1. per-suite verdicts and the exit code survive the parallel run =="
fresh; reset_suites
printf '#!/bin/bash\nbash lib/x/m3.sh >/dev/null\necho "boom line"\nexit 1\n' > tests/test-s3.sh
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>/dev/null)"; rc=$?
has   "$out" "PASS tests/test-s1.sh" "s1 passes"
has   "$out" "PASS tests/test-s2.sh" "s2 passes"
has   "$out" "FAIL tests/test-s3.sh" "the red suite is FAIL"
has   "$out" "    | boom line" "the FAIL tail is shown under the suite"
has   "$out" "PASS tests/test-s4.sh" "a suite after the red one still ran"
has   "$out" "4 selected, 3 pass, 0 cached, 1 fail, 0 timeout" "the summary counts every verdict"
[ "$rc" = 1 ] && ok "exit 1 on a FAIL" || bad "rc=$rc"
fresh; reset_suites
TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "exit 0 when all are green" || bad "rc=$rc on an all-green run"

echo "== 2. the suites really run at the same time (barrier) =="
fresh; for n in 1 2 3; do barrier_suite "$n"; done; printf '#!/bin/bash\nbash lib/x/m4.sh >/dev/null\n' > tests/test-s4.sh
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>/dev/null)"; rc=$?
has "$out" "PASS tests/test-s1.sh" "three suites that wait for each other all pass"
has "$out" "4 selected, 4 pass" "none timed out on the barrier"
[ "$rc" = 0 ] && ok "exit 0 with the barrier" || bad "rc=$rc"
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
has "$out" "4 to run, 4 at a time" "stderr says how many run and how wide"

echo "== 3. a TIMEOUT in one suite does not stop the others =="
fresh; reset_suites
printf '#!/bin/bash\nbash lib/x/m2.sh >/dev/null\nsleep 8\n' > tests/test-s2.sh
printf '# header\ntest-s2 1\n' > "$W/tabin/test-affected.timeouts"
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>/dev/null)"; rc=$?
has   "$out" "TIMEOUT tests/test-s2.sh (limit 1s)" "the slow suite is TIMEOUT with its limit"
hasnt "$out" "FAIL tests/test-s2.sh" "a timeout is not a FAIL"
has   "$out" "PASS tests/test-s1.sh" "the suites around it still pass (s1)"
has   "$out" "PASS tests/test-s3.sh" "the suites around it still pass (s3)"
has   "$out" "PASS tests/test-s4.sh" "the suites around it still pass (s4)"
has   "$out" "4 selected, 3 pass, 0 cached, 0 fail, 1 timeout" "the summary counts one timeout"
[ "$rc" = 1 ] && ok "a timeout exits 1" || bad "rc=$rc"
command rm -f "$W/tabin/test-affected.timeouts"; reset_suites

echo "== 4. the report order is the selection order, whatever finishes first =="
fresh; reset_suites
printf '#!/bin/bash\nbash lib/x/m1.sh >/dev/null\nsleep 3\necho "end-s1" >> "$TA_MARK"\n' > tests/test-s1.sh
printf '#!/bin/bash\nbash lib/x/m2.sh >/dev/null\nsleep 1\necho "end-s2" >> "$TA_MARK"\n' > tests/test-s2.sh
out1="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>/dev/null)"
order="$(grep -o 'end-s[0-9]' "$TA_MARK" | tr '\n' ' ')"
case "$order" in "end-s2 end-s1 "*|*"end-s2 end-s1 ") ok "s2 finished before s1 (the finish order is not the name order)" ;; *) bad "finish order was: $order" ;; esac
lines="$(grep -E '^(PASS|FAIL) ' <<<"$out1" | tr '\n' '|')"
[ "$lines" = "PASS tests/test-s1.sh|PASS tests/test-s2.sh|PASS tests/test-s3.sh|PASS tests/test-s4.sh|" ] && ok "yet the lines are s1, s2, s3, s4" || bad "lines: $lines"
fresh
out2="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>/dev/null)"
[ "$out1" = "$out2" ] && ok "two runs print byte-identical output" || bad "output differs between runs"

echo "== 5. the schedule is longest listed limit first (unlisted = 300) =="
fresh; reset_suites
printf '# header\ntest-s1 60\ntest-s2 600\ntest-s4 10\n' > "$W/tabin/test-affected.timeouts"
TEST_AFFECTED_JOBS=1 bash "$TA2" --base "$BASE" --no-cache >/dev/null 2>&1
starts="$(grep -o 'start-s[0-9]' "$TA_MARK" | tr '\n' ' ')"
[ "$starts" = "start-s2 start-s3 start-s1 start-s4 " ] && ok "started s2 (600), s3 (unlisted 300), s1 (60), s4 (10)" || bad "start order: $starts"
fresh
TEST_AFFECTED_TIMEOUT_SECS=100 TEST_AFFECTED_JOBS=1 bash "$TA2" --base "$BASE" --no-cache >/dev/null 2>&1
starts="$(grep -o 'start-s[0-9]' "$TA_MARK" | tr '\n' ' ')"
[ "$starts" = "start-s2 start-s3 start-s1 start-s4 " ] && ok "the env override changes the limit, not the schedule" || bad "start order under override: $starts"
command rm -f "$W/tabin/test-affected.timeouts"

echo "== 6. a # serial: suite runs alone, after the batch =="
fresh; reset_suites
printf '#!/bin/bash\n# serial: measures wall clock\necho "start-s2" >> "$TA_MARK"\nbash lib/x/m2.sh >/dev/null\nsleep 1\necho "end-s2" >> "$TA_MARK"\n' > tests/test-s2.sh
for n in 1 3 4; do printf '#!/bin/bash\necho "start-s%s" >> "$TA_MARK"\nbash lib/x/m%s.sh >/dev/null\nsleep 1\necho "end-s%s" >> "$TA_MARK"\n' "$n" "$n" "$n" > "tests/test-s$n.sh"; done
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
has "$out" "1 serial" "stderr names the serial lane"
last3="$(tail -2 "$TA_MARK" | tr '\n' ' ')"
[ "$last3" = "start-s2 end-s2 " ] && ok "the serial suite starts after every batch suite ended and ends last" || bad "mark tail: $last3"
[ "$(grep -c '^end-' "$TA_MARK")" = 4 ] && ok "all four ran" || bad "marks: $(cat "$TA_MARK")"

echo "== 7. job count: shared default, halved above the load threshold, explicit number kept =="
. "$KIT_DIR/tests/lib/job-count.sh"
AUTO="$(job_count auto)"
fresh; reset_suites
err="$(TEST_AFFECTED_JOBS=auto KIT_LOAD_WARN=16 KIT_LOAD_STUB=3 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
has   "$err" "4 to run, $AUTO at a time" "quiet host: the full job count ($AUTO)"
hasnt "$err" "halved" "quiet host: not halved"
if [ "$AUTO" -gt 1 ]; then
  HALF=$((AUTO / 2))
  fresh; reset_suites
  err="$(TEST_AFFECTED_JOBS=auto KIT_LOAD_WARN=16 KIT_LOAD_STUB=50 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
  has "$err" "4 to run, $HALF at a time (halved" "load 50 over the threshold 16: $AUTO halves to $HALF"
  fresh; reset_suites
  err="$(TEST_AFFECTED_JOBS=auto KIT_LOAD_WARN=60 KIT_LOAD_STUB=50 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
  has "$err" "4 to run, $AUTO at a time" "load 50 under a threshold of 60: not halved (the threshold is load-warn's)"
else
  ok "single-core default: nothing to halve (cases skipped)"; ok "single-core default: nothing to halve (cases skipped)"
fi
fresh; reset_suites
err="$(TEST_AFFECTED_JOBS=3 KIT_LOAD_WARN=16 KIT_LOAD_STUB=50 bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
has   "$err" "4 to run, 3 at a time" "an explicit number is the operator's and is not halved"
hasnt "$err" "halved" "explicit number: no halving note"
fresh; reset_suites
err="$(TEST_AFFECTED_JOBS=zero bash "$TA2" --base "$BASE" --no-cache 2>&1 >/dev/null)"
has   "$err" "4 to run, 1 at a time" "a junk job count falls back to one at a time"
[ "$(KIT_LOAD_STUB=3 bash "$KIT_DIR/lib/host/load-warn.sh" --over; echo $?)" = 1 ] && ok "load-warn --over is silent and exits 1 on a quiet host" || bad "--over quiet"
[ "$(KIT_LOAD_STUB=99 KIT_LOAD_WARN=16 bash "$KIT_DIR/lib/host/load-warn.sh" --over 2>&1; echo $?)" = 0 ] && ok "load-warn --over is silent and exits 0 over the threshold" || bad "--over loaded"

echo "== 8. cache and history are unchanged by the batch =="
fresh; reset_suites
printf '#!/bin/bash\nbash lib/x/m3.sh >/dev/null\nexit 1\n' > tests/test-s3.sh
TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" >/dev/null 2>&1
SUITE_ROWS="$(awk -F'\t' '$3 !~ /^run:/' "$W/hist.tsv" | wc -l | tr -d ' ')"
RUN_ROW="$(awk -F'\t' '$3 == "run:test-affected"' "$W/hist.tsv")"
[ "$SUITE_ROWS" = 4 ] && ok "one history row per suite that ran (4)" || bad "suite rows=$SUITE_ROWS"
if grep -q 'selected=4' <<<"$RUN_ROW" && [ "$(cut -f5 <<<"$RUN_ROW")" = 1 ]; then ok "one run row: selected=4, exit 1"; else bad "run row: $RUN_ROW"; fi
out="$(TEST_AFFECTED_JOBS=4 bash "$TA2" --base "$BASE" 2>/dev/null)"
has   "$out" "CACHED tests/test-s1.sh" "a passed suite is cached by its worker"
has   "$out" "FAIL tests/test-s3.sh" "a failed suite is never cached"
has   "$out" "4 selected, 0 pass, 3 cached, 1 fail" "second run: 3 cached, the red one re-runs"

echo
echo "test-affected-parallel: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
