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

# 7. triage: report with a machine-triage json footer -> kanban proposal rows
mkdir -p "$TMP/triage"
cat > "$TMP/triage/audit-2026-03-01.md" <<'EOF'
## Report body
Some findings prose with an unrelated fenced block:
```json
{"not": "the footer"}
```
More prose.
```json
[{"change":"route Explore subagents to haiku","owner":"kit","finding":"237/982 on opus",
  "effect":"cuts subagent opus spend","confidence":"medium","falsifier":"still lands on opus",
  "metric":{"name":"subagent_opus_share","current":"24.1%","rerun":"jq cross-tab"}},
 {"change":"clear mega-sessions at boundaries","owner":"user-habit","finding":"694:1 ratio",
  "effect":"cuts cache-read","confidence":"medium","falsifier":"share does not drop",
  "metric":{"name":"top10_cache_read_share","current":"76.3%","rerun":"jq group-sum"}}]
```
EOF
out="$("$SA" triage --out "$TMP/triage")"
echo "$out" | grep -c "^| ?? |" | grep -q "^2$" && ok "triage: 2 proposal rows" || no "triage rows wrong: $out"
echo "$out" | grep -q "owner:kit · metric subagent_opus_share=24.1%" && ok "triage: notes carry owner+metric" || no "triage notes wrong"
echo "$out" | grep -q "PROPOSALS ONLY" && ok "triage: propose-only banner" || no "triage banner missing"

# 8. triage: last-json-block wins (the decoy above is ignored)
echo "$out" | grep -q "not.*the footer" && no "triage: decoy block leaked" || ok "triage: decoy block ignored"

# 9. triage degrade: report without the footer -> _none_
cat > "$TMP/triage/audit-2026-03-08.md" <<'EOF'
## Older-format report, no machine block
EOF
out="$("$SA" triage --out "$TMP/triage")"
echo "$out" | grep -q "_none_" && ok "triage: no-block degrades" || no "triage no-block wrong: $out"

# 10. triage degrade: no reports at all -> empty
out="$("$SA" triage --out "$TMP/empty-dir")"
echo "$out" | grep -q "no audit report found" && ok "triage: empty degrades" || no "triage empty wrong: $out"

echo "smoke: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
