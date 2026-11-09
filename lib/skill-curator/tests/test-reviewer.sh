#!/usr/bin/env bash
# TASK-004/005: the trusted reviewer wrapper. Mock the claude call via SKILL_CURATOR_REVIEWER_CMD (emits a
# claude -p --output-format json ENVELOPE), so the parse / secret-drop / staging / ledger logic is
# tested with no live model. Run: bash tests/test-reviewer.sh  Pass: "...: all N passed", exit 0.
set -uo pipefail
export SKILL_CURATOR_SIGNAL_GATE=false   # tests the reviewer pipeline on marker-free fixtures; the gate itself is test-signal-gate.sh
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$DIR/lib/reviewer-run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }

export SKILL_CURATOR_STATE_DIR="$TMP/state"
export KIT_LEDGER_DIR="$TMP/ledger"   # a failed model call is ledgered (lib/telemetry/egress-fail.sh); keep it in the sandbox
export SKILL_CURATOR_PROPOSALS_DIR="$TMP/proposals"
export SKILL_CURATOR_SKILLS_DIR="$TMP/skills"; mkdir -p "$SKILL_CURATOR_SKILLS_DIR"
LEDGER="$SKILL_CURATOR_STATE_DIR/ledger.jsonl"
PAY="$TMP/payload.json"
jq -n --arg tp "$DIR/tests/fixtures/sample-transcript.jsonl" '{session_id:"sess-test",transcript_path:$tp}' > "$PAY"

mk_env(){ jq -nc --arg r "$1" --argjson c "${2:-0.001}" \
  '{type:"result",subtype:"success",total_cost_usd:$c,result:$r,usage:{input_tokens:1000,output_tokens:200}}'; }
reset(){ rm -rf "$SKILL_CURATOR_PROPOSALS_DIR" "$SKILL_CURATOR_STATE_DIR" 2>/dev/null; }
ledger_has(){ [ -f "$LEDGER" ] && jq -e "$1" "$LEDGER" >/dev/null 2>&1; }

GOOD_BODY='---
name: deploy-via-wrangler
description: Deploy a Cloudflare Worker via wrangler; use when shipping worker changes.
disable-model-invocation: true
---
# Deploy via wrangler
1. wrangler deploy
2. verify with wrangler tail
'
# Build a synthetic secret at RUNTIME so no literal credential lives in this file (secret-guard).
FAKE_SECRET="sk-ant-$(printf 'api03'; printf 'X%.0s' $(seq 1 30))"
SECRET_BODY="---
name: deploy-bad
---
# Deploy
export TOKEN=$FAKE_SECRET
"

echo "[1] a returned draft is staged under proposals/<slug>/SKILL.md (and ONLY there)"
reset
draft="$(jq -nc --arg b "$GOOD_BODY" '{draft:{slug:"deploy-via-wrangler",name:"deploy-via-wrangler",description:"deploy a CF worker",body:$b},reason:"repeated workflow"}')"
mk_env "$draft" 0.0012 > "$TMP/env1.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env1.json" bash "$RUN" "$PAY"; rc=$?
if [[ -f "$SKILL_CURATOR_PROPOSALS_DIR/deploy-via-wrangler/SKILL.md" ]] && grep -q 'Deploy via wrangler' "$SKILL_CURATOR_PROPOSALS_DIR/deploy-via-wrangler/SKILL.md" && [[ $rc -eq 0 ]]; then
  ok "draft staged under proposals/"; else no "draft not staged (rc=$rc)"; fi

echo "[2] the wrapper wrote NOTHING under skills/ (model-has-no-write boundary)"
if [[ -z "$(find "$SKILL_CURATOR_SKILLS_DIR" -type f 2>/dev/null)" ]]; then ok "skills/ untouched"; else no "wrote under skills/"; fi

echo "[3] cost ledger: a staged run logs total_cost_usd + slug (cost observability AC)"
if ledger_has 'select(.staged==true and .slug=="deploy-via-wrangler" and .total_cost_usd==0.0012 and .kind=="skill-review")'; then
  ok "ledger line with cost"; else no "ledger missing cost line: $(cat "$LEDGER" 2>/dev/null)"; fi

echo "[4] null draft -> nothing staged, ledger staged:false (negative control)"
reset
mk_env '{"draft":null,"reason":"no signal"}' 0.0009 > "$TMP/env2.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env2.json" bash "$RUN" "$PAY"
if [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]] && ledger_has 'select(.staged==false and .note=="null-draft")'; then
  ok "null draft staged nothing, ledger note=null-draft"; else no "null-draft handling wrong"; fi

echo "[5] a draft carrying a secret is DROPPED, not staged (negative control)"
reset
sdraft="$(jq -nc --arg b "$SECRET_BODY" '{draft:{slug:"deploy-bad",name:"deploy-bad",description:"x",body:$b},reason:"has secret"}')"
mk_env "$sdraft" 0.001 > "$TMP/env3.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env3.json" bash "$RUN" "$PAY"
if [[ ! -f "$SKILL_CURATOR_PROPOSALS_DIR/deploy-bad/SKILL.md" ]] && ledger_has 'select(.staged==false and .note=="dropped-secret")'; then
  ok "secret draft dropped (not staged), ledger note=dropped-secret"; else no "secret leaked into a proposal"; fi

echo "[6] claude missing / non-zero exit -> exit 0, no draft, ledger note=no-output (safe-to-wire)"
reset
SKILL_CURATOR_REVIEWER_CMD="false" bash "$RUN" "$PAY"; rc=$?
if [[ $rc -eq 0 ]] && [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]] && ledger_has 'select(.note=="no-output")'; then
  ok "claude-unavailable -> exit 0, no draft"; else no "unavailable handling wrong (rc=$rc)"; fi

echo "[7] malformed model JSON -> no draft, ledger note=bad-json (negative control)"
reset
mk_env 'this is not json at all' 0.001 > "$TMP/env4.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env4.json" bash "$RUN" "$PAY"
if [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]] && ledger_has 'select(.note=="bad-json")'; then
  ok "malformed JSON -> no draft, logged"; else no "bad-json handling wrong"; fi

echo "[8] single-flight: an in-flight reviewer (lock held) skips, stages nothing (negative control)"
reset
mkdir -p "$SKILL_CURATOR_STATE_DIR/state/reviewer.lock.d"
sleep 30 & HOLDER=$!; echo "$HOLDER" > "$SKILL_CURATOR_STATE_DIR/state/reviewer.lock.d/pid"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env1.json" bash "$RUN" "$PAY"
if [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]]; then ok "lock held -> skipped, nothing staged"; else no "single-flight failed"; fi
kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true

echo "[9] empty transcript -> reviewer not even invoked, nothing staged (no-op pass)"
reset
PE="$TMP/payload-empty.json"; jq -n '{session_id:"s",transcript_path:"/nonexistent.jsonl"}' > "$PE"
SKILL_CURATOR_REVIEWER_CMD="touch $TMP/INVOKED; cat $TMP/env1.json" bash "$RUN" "$PE"
if [[ ! -e "$TMP/INVOKED" ]] && [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]]; then
  ok "empty transcript -> reviewer not called"; else no "reviewer ran on empty transcript"; fi

echo "[10] the default reviewer invocation pins --allowedTools \"\" (model-no-write, DEC-008)"
if grep -Eq -- '--allowedTools[[:space:]]+""' "$RUN"; then ok "reviewer pins --allowedTools \"\""; else no "reviewer does not pin empty allowedTools"; fi

echo "[11] envelope with is_error:true (e.g. not logged in) -> no draft, ledger note=api-error, not bad-json"
reset
jq -nc '{type:"result",subtype:"success",is_error:true,total_cost_usd:0,result:"Not logged in",usage:{input_tokens:0,output_tokens:0}}' > "$TMP/env5.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env5.json" bash "$RUN" "$PAY"
if [[ -z "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]] && ledger_has 'select(.note=="api-error")' && ! ledger_has 'select(.note=="bad-json")'; then
  ok "is_error envelope -> api-error"; else no "is_error envelope misledgered: $(cat "$LEDGER" 2>/dev/null)"; fi

echo "[12] real claude path: a CLI that refuses --bare (OAuth login, the live host) still stages a draft"
reset
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<STUB
#!/usr/bin/env bash
cat >/dev/null
for a in "\$@"; do
  if [ "\$a" = "--bare" ]; then cat "$TMP/env-notloggedin.json"; exit 1; fi
done
cat "$TMP/env1.json"
STUB
chmod +x "$TMP/bin/claude"
cp "$TMP/env5.json" "$TMP/env-notloggedin.json"
PATH="$TMP/bin:$PATH" bash "$RUN" "$PAY"
if [[ -f "$SKILL_CURATOR_PROPOSALS_DIR/deploy-via-wrangler/SKILL.md" ]] && ledger_has 'select(.staged==true)'; then
  ok "default invocation survives a --bare-hostile CLI"; else no "default invocation uses --bare: $(cat "$LEDGER" 2>/dev/null)"; fi

echo "[13] curate.sh default invocation does not use --bare either"
if ! grep -Eq -- 'claude -p[^#]*--bare' "$DIR/lib/curate.sh" "$RUN"; then ok "no --bare in the claude -p calls"; else no "--bare still in a claude -p call"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-reviewer: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-reviewer: all $pass passed"
