#!/usr/bin/env bash
# money-gate hook (hooks/money-gate.sh + money-gate.py): fires only for
# money-touching edits inside a CONSUMER-NAMED financial repo (MONEY_GATE_REPOS);
# strict mode asks, default mode logs; with MONEY_GATE_REPOS unset the gate is
# INERT (adapter-default invariant: the kit ships no tenant repo names).
set -euo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SHIM="$KIT_DIR/hooks/money-gate.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/gate.log"
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

fin_money='{"tool_input":{"file_path":"/home/u/work/acme-books/tracking/transactions.csv","new_string":"transfer 500 USD to wallet 0xabc"},"cwd":"/home/u/work/acme-books"}'
fin_plain='{"tool_input":{"file_path":"/home/u/work/acme-books/README.md","new_string":"notes about the repo layout and how to run things"},"cwd":"/home/u/work/acme-books"}'
other_money='{"tool_input":{"file_path":"/home/u/work/other-repo/foo.py","new_string":"transfer balance payout amount"},"cwd":"/home/u/work/other-repo"}'

echo "[1] strict + named repo + money content -> asks to confirm"
out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$LOG" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out"; then ok "ask emitted"; else no "got: $out"; fi

echo "[2] ask JSON is valid + names the matched terms"
if python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["hookSpecificOutput"]["permissionDecisionReason"]; sys.exit(0 if "transfer" in r or "wallet" in r else 1)' <<<"$out"; then ok "valid ask JSON with reason"; else no "json/reason wrong"; fi

echo "[3] default (non-strict) mode logs but does not ask"
out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_LOG="$LOG" bash "$SHIM")"
if [[ -z "$out" ]] && grep -q 'transactions.csv' "$LOG"; then ok "logged, no block"; else no "out=[$out]"; fi

echo "[4] NC: named repo + non-money content -> silent"
out="$(printf '%s' "$fin_plain" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l2" bash "$SHIM")"
if [[ -z "$out" ]]; then ok "no fire on plain edit"; else no "false fire: $out"; fi

echo "[5] NC: money content OUTSIDE a named repo -> silent"
out="$(printf '%s' "$other_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l3" bash "$SHIM")"
if [[ -z "$out" ]]; then ok "no fire outside named repos"; else no "false fire: $out"; fi

echo "[6] NC: MONEY_GATE_REPOS unset -> inert even on money content (kit default)"
out="$(printf '%s' "$fin_money" | env -u MONEY_GATE_REPOS MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l4" bash "$SHIM")"
rc=$?
if [[ $rc -eq 0 && -z "$out" && ! -s "$TMP/l4" ]]; then ok "inert without consumer config"; else no "rc=$rc out=$out"; fi

echo "[7] junk payload -> exit 0, silent"
set +e; out="$(echo '{}' | MONEY_GATE_REPOS=acme-books bash "$SHIM")"; rc=$?; set -e
if [[ $rc -eq 0 && -z "$out" ]]; then ok "junk safe"; else no "rc=$rc out=$out"; fi

# --- SPEC.md contract pins (added 2026-07-15 with the module's first SPEC) -------------
# The four below assert claims SPEC.md now makes that nothing was testing. The content
# scan is RECURSIVE over the whole tool_input (not just "the new content", as the module
# docstring said), so [8] and [9] pin the two payload shapes that reach only through the
# recursion; [10] pins the literal-"1" strict switch (a footgun: `true` is log-only);
# [11] pins the exit-0-always invariant, which is what keeps a broken gate from wedging
# an edit. A SPEC claim with no test is the thing this repo does not ship.

multiedit='{"tool_input":{"file_path":"/home/u/work/acme-books/pay.py","edits":[{"old_string":"x = 1","new_string":"send payout to wallet 0xabc"}]},"cwd":"/home/u/work/acme-books"}'
del_money='{"tool_input":{"file_path":"/home/u/work/acme-books/pay.py","old_string":"balance = payroll_total","new_string":"pass"},"cwd":"/home/u/work/acme-books"}'

echo "[8] recursive scan reaches the MultiEdit edits[] array"
out="$(printf '%s' "$multiedit" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l5" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out" && grep -q 'payout' <<<"$out"; then ok "MultiEdit edits[] scanned"; else no "got: $out"; fi

echo "[9] recursive scan reaches old_string (DELETING money content trips the gate)"
# The money term lives ONLY in old_string; new_string is "pass". An ask here can only
# come from the old_string scan. (It reports `balance`, not `payroll_total` -- see [12].)
out="$(printf '%s' "$del_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l6" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out" && grep -q 'balance' <<<"$out"; then ok "old_string scanned"; else no "got: $out"; fi

echo "[10] MONEY_GATE_STRICT accepts any truthy spelling ('true' now ARMS the gate)"
# Was: only the literal "1" armed it, so `MONEY_GATE_STRICT=true` left the operator in
# log-only mode believing they were being prompted. A safety knob that silently does
# nothing is worse than no knob (fixed 2026-07-15).
out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=true MONEY_GATE_LOG="$TMP/l7" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out"; then ok "STRICT=true arms the gate"; else no "true did not arm: $out"; fi
out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=on MONEY_GATE_LOG="$TMP/l7b" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out"; then ok "STRICT=on arms the gate"; else no "on did not arm: $out"; fi

echo "[10b] NEGATIVE CONTROL: a FALSY strict value stays log-only (no false ask)"
for v in 0 false no off ""; do
  out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT="$v" MONEY_GATE_LOG="$TMP/l7c" bash "$SHIM")"
  [[ -n "$out" ]] && { no "STRICT='$v' wrongly armed the gate: $out"; break; }
done
[[ -z "$out" ]] && ok "0/false/no/off/empty all stay log-only"

echo "[11] exit 0 ALWAYS, even when emitting an ask (decision travels in JSON, not rc)"
set +e; out="$(printf '%s' "$fin_money" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l8" bash "$SHIM")"; rc=$?; set -e
if [[ $rc -eq 0 ]] && grep -q '"permissionDecision": "ask"' <<<"$out"; then ok "asked and still exit 0"; else no "rc=$rc out=$out"; fi

# The gate's largest hole, closed. It WAS \b-anchored, and `_` is a word character, so a
# snake_case identifier never matched its own money token: `payroll_total = 5000` sailed
# through while `payroll = 5000` fired. Identifier-shaped money code is exactly what an agent
# edits. The characterization test that pinned the gap is now the assertion that proves it shut.
echo "[12] snake_case identifiers and plurals DO trip the gate (the hole is closed)"
snake='{"tool_input":{"file_path":"/home/u/work/acme-books/pay.py","new_string":"payroll_total = 5000; invoice_id = 7; amounts = []"},"cwd":"/home/u/work/acme-books"}'
out="$(printf '%s' "$snake" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l9" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out" && grep -q 'payroll' <<<"$out"; then
  ok "payroll_total / invoice_id / amounts now fire"; else no "still blind to snake_case: $out"; fi

echo "[12b] the leading-underscore and trailing-underscore forms fire too"
under='{"tool_input":{"file_path":"/home/u/work/acme-books/pay.py","new_string":"total_payroll = 1; _balance_ = 2"},"cwd":"/home/u/work/acme-books"}'
out="$(printf '%s' "$under" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l9b" bash "$SHIM")"
grep -q '"permissionDecision": "ask"' <<<"$out" && ok "total_payroll / _balance_ fire" || no "missed: $out"

echo "[12c] NEGATIVE CONTROL: widening did NOT make the gate match inside a longer word"
# `mypayroll`, `payrolling`, `tokenizer` must NOT fire: the boundary treats `_` as a
# separator but still refuses an alphanumeric neighbour. A gate that fires on everything
# is a gate people disable.
nofire='{"tool_input":{"file_path":"/home/u/work/acme-books/x.py","new_string":"mypayroll = 1; payrolling = 2; tokenizer = 3; balanced = 4"},"cwd":"/home/u/work/acme-books"}'
out="$(printf '%s' "$nofire" | MONEY_GATE_REPOS=acme-books MONEY_GATE_STRICT=1 MONEY_GATE_LOG="$TMP/l9c" bash "$SHIM")"
if [[ -z "$out" && ! -s "$TMP/l9c" ]]; then ok "no false fire inside longer words"; else no "FALSE POSITIVE: $out"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-money-gate: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-money-gate: all $pass passed"
