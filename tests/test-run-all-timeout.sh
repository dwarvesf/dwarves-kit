#!/usr/bin/env bash
# requires: timeout
# run-all.sh must report a per-suite TIMEOUT as a DIFFERENT fact from a red assertion.
#
# Both still exit 1, but they mean different things: a ceiling hit under load is not a broken
# suite. Before this, both landed in one `run-all: FAILED ->` line, and on 2026-09-12 a green
# test-meta (142s at low load, over the 300s cap at load 26-55) read as broken and cost two
# full re-runs to tell apart.
#
# Each case builds a throwaway kit dir (tests/run-all.sh plus fixture suites) and runs the
# REAL script against it, so nothing here touches the repo's own tests/.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RA="$DIR/tests/run-all.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkkit() {  # $1 = dir ; a kit-shaped tree holding the real run-all.sh
  mkdir -p "$1/tests/lib"
  cp "$RA" "$1/tests/run-all.sh"; cp "$DIR/tests/lib/job-count.sh" "$1/tests/lib/"
}
slow() { printf '#!/usr/bin/env bash\nsleep 30\n' > "$1/tests/test-slowpoke.sh"; }
red()  { printf '#!/usr/bin/env bash\necho "FAIL: a real assertion"\nexit 1\n' > "$1/tests/test-redherring.sh"; }
green(){ printf '#!/usr/bin/env bash\nexit 0\n' > "$1/tests/test-allgood.sh"; }

echo "[1] a suite over the ceiling is TIMED OUT, never folded into FAILED"
K="$TMP/k1"; mkkit "$K"; slow "$K"
OUT="$(RUN_ALL_TIMEOUT_SECS=1 bash "$K/tests/run-all.sh" --only slowpoke 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] \
   && grep -q 'TIMEOUT (1s)' <<<"$OUT" \
   && grep -q '^run-all: TIMED OUT at 1s ->.*test-slowpoke' <<<"$OUT" \
   && ! grep -q '^run-all: FAILED ->' <<<"$OUT"; then
  ok "timeout named on its own line, no FAILED line"
else no "rc=$RC out=$OUT"; fi

echo "[2] the timeout line says what to do instead of treating it as broken"
if grep -qi 'NOT an assertion failure' <<<"$OUT" && grep -q 'RUN_ALL_TIMEOUT_SECS' <<<"$OUT"; then
  ok "hint names the knob and the distinction"
else no "no actionable hint: $OUT"; fi

echo "[3] a killed suite says it ran out of time rather than showing no assertion"
if grep -q 'killed at 1s; no assertion failed' <<<"$OUT"; then
  ok "the empty-FAIL-grep confusion is named"
else no "out=$OUT"; fi

echo "[4] a genuinely red suite is still FAILED, never TIMED OUT"
K2="$TMP/k2"; mkkit "$K2"; red "$K2"
OUT2="$(RUN_ALL_TIMEOUT_SECS=60 bash "$K2/tests/run-all.sh" --only redherring 2>&1)"; RC2=$?
if [ "$RC2" -eq 1 ] \
   && grep -q '^run-all: FAILED ->.*test-redherring' <<<"$OUT2" \
   && ! grep -q 'TIMED OUT' <<<"$OUT2"; then
  ok "a real failure is untouched by this change"
else no "rc=$RC2 out=$OUT2"; fi

echo "[5] both at once are reported as two separate facts"
K3="$TMP/k3"; mkkit "$K3"; slow "$K3"; red "$K3"
OUT3="$(RUN_ALL_TIMEOUT_SECS=1 bash "$K3/tests/run-all.sh" 2>&1)"; RC3=$?
if [ "$RC3" -eq 1 ] \
   && grep -q '^run-all: FAILED ->.*test-redherring' <<<"$OUT3" \
   && grep -q '^run-all: TIMED OUT at 1s ->.*test-slowpoke' <<<"$OUT3"; then
  ok "one line each, neither swallows the other"
else no "rc=$RC3 out=$OUT3"; fi

echo "[6] the all-green summary is unchanged (no new line on the happy path)"
K4="$TMP/k4"; mkkit "$K4"; green "$K4"
OUT4="$(bash "$K4/tests/run-all.sh" --only allgood 2>&1)"; RC4=$?
if [ "$RC4" -eq 0 ] \
   && grep -q '^run-all: all 1 suites passed' <<<"$OUT4" \
   && ! grep -qi 'TIMED OUT\|FAILED' <<<"$OUT4"; then
  ok "green path byte-identical"
else no "rc=$RC4 out=$OUT4"; fi

echo "[7] a listed suite takes its ceiling from bin/test-affected.timeouts; unlisted suites and an explicit env keep the global one"
K5="$TMP/k5"; mkkit "$K5"; mkdir -p "$K5/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$K5/tests/test-heavy.sh"; green "$K5"
printf '# header\ntest-heavy 900\n' > "$K5/bin/test-affected.timeouts"
lim() { # $1 = suite ; $2 = RUN_ALL_TIMEOUT_SECS or empty ; prints the ceiling the worker applied
  local od; od="$(mktemp -d "$TMP/od.XXXXXX")"
  ( cd "$K5" && if [ -n "$2" ]; then RUN_ALL_TIMEOUT_SECS="$2"; export RUN_ALL_TIMEOUT_SECS; else unset RUN_ALL_TIMEOUT_SECS; fi
    bash tests/run-all.sh --run-one "tests/$1.sh" "$od" >/dev/null 2>&1 )
  cat "$od/$1.limit" 2>/dev/null
}
if [ "$(lim test-heavy "")" = 900 ] && [ "$(lim test-allgood "")" = 300 ] \
   && [ "$(lim test-heavy 7)" = 7 ] && [ "$(lim test-allgood 7)" = 7 ]; then
  ok "listed suite 900, unlisted 300, explicit RUN_ALL_TIMEOUT_SECS wins for all"
else no "heavy=$(lim test-heavy "") allgood=$(lim test-allgood "") heavy+env=$(lim test-heavy 7) allgood+env=$(lim test-allgood 7)"; fi

echo "[8] a suite over its listed ceiling prints TIMEOUT with that limit, not the global one"
K6="$TMP/k6"; mkkit "$K6"; mkdir -p "$K6/bin"; slow "$K6"
printf '# header\ntest-slowpoke 1\n' > "$K6/bin/test-affected.timeouts"
OUT6="$(env -u RUN_ALL_TIMEOUT_SECS bash "$K6/tests/run-all.sh" --only slowpoke 2>&1)"; RC6=$?
if [ "$RC6" -eq 1 ] && grep -q 'test-slowpoke.*TIMEOUT (1s)' <<<"$OUT6" && ! grep -q '^run-all: FAILED ->' <<<"$OUT6"; then
  ok "TIMEOUT (1s) from the data file, no FAILED line"
else no "rc=$RC6 out=$OUT6"; fi

if [ "$fail" -gt 0 ]; then echo "test-run-all-timeout: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-timeout: all $pass passed"
