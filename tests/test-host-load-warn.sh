#!/usr/bin/env bash
# lib/host/load-warn.sh prints ONE warning line when the 1-minute load average is over the
# threshold, and never changes anything else: it exits 0 above and below, reads the threshold
# from KIT_LOAD_WARN, then kit.toml [test].load_warn, then 16, and prints nothing on junk input.
# KIT_LOAD_STUB replaces the real load so the cases run on any host.
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
LW="$DIR/lib/host/load-warn.sh"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# A kit root with no kit.toml and no operator file: the default (16) is the only source.
export KIT_CONFIG_ROOT="$TMP/root" KIT_CONFIG_OPERATOR="$TMP/op" KIT_PROJECT_ROOT="$TMP/proj"
mkdir -p "$KIT_CONFIG_ROOT" "$KIT_CONFIG_OPERATOR" "$KIT_PROJECT_ROOT"
unset KIT_LOAD_WARN

echo "[1] load above the default threshold prints one line and exits 0"
OUT="$(KIT_LOAD_STUB=40.5 bash "$LW" "the big run" 2>&1 >/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ] \
   && grep -q '^load-warn: 1-min load 40.5 is over 16;' <<<"$OUT" && grep -q 'the big run' <<<"$OUT" \
   && grep -q 'Devin or self-hosted CI' <<<"$OUT"; then ok "one line, names the load, the limit, the run and the advice"
else no "rc=$RC out=$OUT"; fi

echo "[2] load below the threshold prints nothing and exits 0"
OUT="$(KIT_LOAD_STUB=3.2 bash "$LW" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "silent"; else no "rc=$RC out=$OUT"; fi

echo "[3] exactly at the threshold is not over it"
OUT="$(KIT_LOAD_STUB=16 bash "$LW" 2>&1)"
[ -z "$OUT" ] && ok "16 vs 16 is silent" || no "out=$OUT"

echo "[4] the warning goes to stderr, stdout stays empty"
OUT="$(KIT_LOAD_STUB=99 bash "$LW" 2>/dev/null)"
[ -z "$OUT" ] && ok "stdout empty" || no "stdout=$OUT"

echo "[5] a caller's exit code is unchanged: a failing command keeps its code through the warning"
(KIT_LOAD_STUB=99 bash "$LW" 2>/dev/null; exit 7); RC=$?
[ "$RC" -eq 7 ] && ok "caller exit 7 survives" || no "rc=$RC"
KIT_LOAD_STUB=99 bash "$LW" 2>/dev/null; RC=$?
[ "$RC" -eq 0 ] && ok "the helper itself exits 0 over the threshold" || no "rc=$RC"

echo "[6] NEGATIVE CONTROL: threshold 0 prints on a quiet host (real load, no stub)"
OUT="$(KIT_LOAD_WARN=0 bash "$LW" 2>&1 >/dev/null)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q '^load-warn: 1-min load .* is over 0;' <<<"$OUT"; then ok "warns at threshold 0"
else no "rc=$RC out=$OUT"; fi
OUT="$(KIT_LOAD_WARN=100000 bash "$LW" 2>&1)"
[ -z "$OUT" ] && ok "and a huge threshold silences the same host" || no "out=$OUT"

echo "[7] the threshold reads kit.toml [test].load_warn, env wins over it"
printf '[test]\nload_warn = 5\n' >"$KIT_CONFIG_ROOT/kit.toml"
OUT="$(KIT_LOAD_STUB=6 bash "$LW" 2>&1 >/dev/null)"
grep -q 'is over 5;' <<<"$OUT" && ok "kit.toml value 5 applies" || no "out=$OUT"
OUT="$(KIT_LOAD_STUB=6 KIT_LOAD_WARN=50 bash "$LW" 2>&1)"
[ -z "$OUT" ] && ok "KIT_LOAD_WARN=50 beats kit.toml" || no "out=$OUT"
command rm -f "$KIT_CONFIG_ROOT/kit.toml" 2>/dev/null || mv -f "$KIT_CONFIG_ROOT/kit.toml" "$TMP/discard"

echo "[8] junk load or junk threshold prints nothing"
OUT="$(KIT_LOAD_STUB=abc bash "$LW" 2>&1)"; [ -z "$OUT" ] && ok "junk load silent" || no "out=$OUT"
OUT="$(KIT_LOAD_STUB=50 KIT_LOAD_WARN=lots bash "$LW" 2>&1)"; [ -z "$OUT" ] && ok "junk threshold silent" || no "out=$OUT"

echo "[9] bin/test-affected calls the helper on a run, not on --list"
grep -q 'lib/host/load-warn.sh' "$DIR/bin/test-affected" && ok "bin/test-affected references it" || no "no reference"
grep -q 'host/load-warn.sh' "$DIR/lib/queue/orchestrate.sh" && ok "orchestrate.sh references it" || no "no reference"

echo
echo "load-warn: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
