#!/usr/bin/env bash
# money-gate hook (hooks/money-gate.sh + money-gate.py): fires only for
# money-touching edits inside a CONSUMER-NAMED financial repo (CC_MONEY_REPOS);
# strict mode asks, default mode logs; with CC_MONEY_REPOS unset the gate is
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
out="$(printf '%s' "$fin_money" | CC_MONEY_REPOS=acme-books CC_MONEY_STRICT=1 CC_MONEY_LOG="$LOG" bash "$SHIM")"
if grep -q '"permissionDecision": "ask"' <<<"$out"; then ok "ask emitted"; else no "got: $out"; fi

echo "[2] ask JSON is valid + names the matched terms"
if python3 -c 'import json,sys; d=json.load(sys.stdin); r=d["hookSpecificOutput"]["permissionDecisionReason"]; sys.exit(0 if "transfer" in r or "wallet" in r else 1)' <<<"$out"; then ok "valid ask JSON with reason"; else no "json/reason wrong"; fi

echo "[3] default (non-strict) mode logs but does not ask"
out="$(printf '%s' "$fin_money" | CC_MONEY_REPOS=acme-books CC_MONEY_LOG="$LOG" bash "$SHIM")"
if [[ -z "$out" ]] && grep -q 'transactions.csv' "$LOG"; then ok "logged, no block"; else no "out=[$out]"; fi

echo "[4] NC: named repo + non-money content -> silent"
out="$(printf '%s' "$fin_plain" | CC_MONEY_REPOS=acme-books CC_MONEY_STRICT=1 CC_MONEY_LOG="$TMP/l2" bash "$SHIM")"
if [[ -z "$out" ]]; then ok "no fire on plain edit"; else no "false fire: $out"; fi

echo "[5] NC: money content OUTSIDE a named repo -> silent"
out="$(printf '%s' "$other_money" | CC_MONEY_REPOS=acme-books CC_MONEY_STRICT=1 CC_MONEY_LOG="$TMP/l3" bash "$SHIM")"
if [[ -z "$out" ]]; then ok "no fire outside named repos"; else no "false fire: $out"; fi

echo "[6] NC: CC_MONEY_REPOS unset -> inert even on money content (kit default)"
out="$(printf '%s' "$fin_money" | env -u CC_MONEY_REPOS CC_MONEY_STRICT=1 CC_MONEY_LOG="$TMP/l4" bash "$SHIM")"
rc=$?
if [[ $rc -eq 0 && -z "$out" && ! -s "$TMP/l4" ]]; then ok "inert without consumer config"; else no "rc=$rc out=$out"; fi

echo "[7] junk payload -> exit 0, silent"
set +e; out="$(echo '{}' | CC_MONEY_REPOS=acme-books bash "$SHIM")"; rc=$?; set -e
if [[ $rc -eq 0 && -z "$out" ]]; then ok "junk safe"; else no "rc=$rc out=$out"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-money-gate: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-money-gate: all $pass passed"
