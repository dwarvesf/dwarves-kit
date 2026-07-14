#!/usr/bin/env bash
# smoke: session-audit render + report-write + PREV chaining + degrade paths.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SA="$DIR/bin/session-audit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "  ok: $1"; }
no() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

# fixture: object-form runtime output
cat > "$TMP/obj.json" <<'EOF'
{"type":"result","subtype":"success","is_error":false,"result":"## Audit body OBJ","total_cost_usd":1.23,"duration_ms":4500}
EOF
# fixture: array-form runtime output (observed from some CLI versions)
cat > "$TMP/arr.json" <<'EOF'
[{"type":"system"},{"type":"result","subtype":"success","is_error":false,"result":"## Audit body ARR","total_cost_usd":2.5,"duration_ms":9000}]
EOF
# capture helper: saves the rendered prompt, then answers with the fixture
cat > "$TMP/capture" <<EOF
#!/usr/bin/env bash
cat > "$TMP/prompt-seen.txt"
cat "$TMP/obj.json"
EOF
chmod +x "$TMP/capture"

# 1. run writes a dated report containing the result body
out="$(SESSION_AUDIT_CMD="$TMP/capture" SESSION_AUDIT_DATE=2026-01-01 "$SA" run --out "$TMP/intel" --root /nonexistent --days 3)"
[ -f "$TMP/intel/audit-2026-01-01.md" ] && ok "report written" || no "report missing: $out"
grep -q "Audit body OBJ" "$TMP/intel/audit-2026-01-01.md" && ok "body present" || no "body missing"
grep -q "days 3" "$TMP/intel/audit-2026-01-01.md" && ok "header params" || no "header params missing"

# 2. prompt render: params substituted, no unresolved placeholders
grep -q "/nonexistent" "$TMP/prompt-seen.txt" && ok "ROOT substituted" || no "ROOT not substituted"
if grep -qE '\{(ROOT|DAYS|K|PRICING|PREV)\}' "$TMP/prompt-seen.txt"; then no "unresolved placeholder"; else ok "all placeholders resolved"; fi
grep -q "none provided for this run" "$TMP/prompt-seen.txt" && ok "PREV=none on first run" || no "PREV wrong on first run"

# 3. second run receives the first report as PREV
SESSION_AUDIT_CMD="$TMP/capture" SESSION_AUDIT_DATE=2026-01-08 "$SA" run --out "$TMP/intel" --root /nonexistent >/dev/null
grep -q "audit-2026-01-01.md" "$TMP/prompt-seen.txt" && ok "PREV chained" || no "PREV not chained"

# 4. array-form output parsed
out="$(SESSION_AUDIT_CMD="cat $TMP/arr.json" SESSION_AUDIT_DATE=2026-01-15 "$SA" run --out "$TMP/intel" --json)"
echo "$out" | grep -q '"status": "ok"' && ok "array-form parsed" || no "array-form not parsed: $out"
grep -q "Audit body ARR" "$TMP/intel/audit-2026-01-15.md" && ok "array body written" || no "array body missing"

# 5. degrade: failing command -> _unavailable_, exit 0, no report
out="$(SESSION_AUDIT_CMD="false" SESSION_AUDIT_DATE=2026-02-01 "$SA" run --out "$TMP/intel")"; rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "_unavailable_" && ok "degrades on failure" || no "degrade wrong: rc=$rc $out"
[ ! -f "$TMP/intel/audit-2026-02-01.md" ] && ok "no report on failure" || no "report written on failure"

# 6. degrade: garbage output -> _unavailable_
out="$(SESSION_AUDIT_CMD="echo not-json" SESSION_AUDIT_DATE=2026-02-02 "$SA" run --out "$TMP/intel")"
echo "$out" | grep -q "_unavailable_" && ok "degrades on garbage" || no "garbage not degraded: $out"

echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
