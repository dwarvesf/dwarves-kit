#!/usr/bin/env bash
# run-all.sh --time must report each suite's elapsed seconds and the slowest ten.
#
# A slow local run used to say nothing about WHERE the time went, so finding the heavy
# suite meant timing them by hand. --time answers that in the report itself. The flag is
# also a promise: without it the output stays byte-identical, so nobody's grep breaks.
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

mkkit() {  # $1 = dir ; $2 = the run-all.sh to install ; plus the two fixture suites
  mkdir -p "$1/tests"
  cp "$2" "$1/tests/run-all.sh"
  printf '#!/usr/bin/env bash\nsleep 2\nexit 0\n' > "$1/tests/test-slowfixture.sh"
  printf '#!/usr/bin/env bash\nsleep 0\nexit 0\n' > "$1/tests/test-quickfixture.sh"
}

K="$TMP/k1"; mkkit "$K" "$RA"
OUT="$(bash "$K/tests/run-all.sh" --all --time 2>/dev/null)"; RC=$?

echo "[1] each suite line carries its own elapsed seconds"
if [ "$RC" -eq 0 ] \
   && grep -qE '^test-slowfixture +ok \(2s\)$' <<<"$OUT" \
   && grep -qE '^test-quickfixture +ok \(0s\)$' <<<"$OUT"; then
  ok "2s and 0s reported against the right suites"
else no "rc=$RC out=$OUT"; fi

echo "[2] a slowest block follows the report, worst first"
SLOW="$(sed -n '/^run-all: slowest:/,$p' <<<"$OUT" | sed -n '2,3p')"
if grep -q '^run-all: slowest:$' <<<"$OUT" \
   && [ "$(sed -n 1p <<<"$SLOW")" = "  2s test-slowfixture" ] \
   && [ "$(sed -n 2p <<<"$SLOW")" = "  0s test-quickfixture" ]; then
  ok "descending by seconds, not glob order"
else no "block=$SLOW out=$OUT"; fi

echo "[3] --time combines with --only"
OUT2="$(bash "$K/tests/run-all.sh" --only slowfixture --time 2>/dev/null)"; RC2=$?
if [ "$RC2" -eq 0 ] \
   && grep -qE '^test-slowfixture +ok \(2s\)$' <<<"$OUT2" \
   && grep -q '^  2s test-slowfixture$' <<<"$OUT2" \
   && ! grep -q 'quickfixture' <<<"$OUT2"; then
  ok "the pattern still narrows the run and the timing follows it"
else no "rc=$RC2 out=$OUT2"; fi

echo "[4] without --time the output is byte-identical to the version before the flag"
BASE="$TMP/base-run-all.sh"
if git -C "$DIR" show origin/master:tests/run-all.sh >"$BASE" 2>/dev/null; then
  K2="$TMP/k2"; mkkit "$K2" "$BASE"
  A="$(bash "$K/tests/run-all.sh" --all 2>/dev/null)"
  B="$(bash "$K2/tests/run-all.sh" --all 2>/dev/null)"
  if [ "$A" = "$B" ]; then
    ok "no --time, no change"
  else no "diff: $(diff <(echo "$B") <(echo "$A"))"; fi
else
  no "cannot read origin/master:tests/run-all.sh to compare against"
fi

if [ "$fail" -gt 0 ]; then echo "test-run-all-time: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-run-all-time: all $pass passed"
