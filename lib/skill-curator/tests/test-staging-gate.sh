#!/usr/bin/env bash
# TASK-006: the staging-by-path gate. A draft lands only under proposals/ (NOT skills/); an
# adversarial path-traversal slug cannot escape proposals/; the reviewer model has no write.
# Run: bash tests/test-staging-gate.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$DIR/lib/reviewer-run.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export SKILL_CURATOR_STATE_DIR="$TMP/state" SKILL_CURATOR_PROPOSALS_DIR="$TMP/proposals" SKILL_CURATOR_SKILLS_DIR="$TMP/skills"
mkdir -p "$SKILL_CURATOR_SKILLS_DIR"
PAY="$TMP/pay.json"; jq -n --arg tp "$DIR/tests/fixtures/sample-transcript.jsonl" '{session_id:"g",transcript_path:$tp}' > "$PAY"
mk_env(){ jq -nc --arg r "$1" '{type:"result",total_cost_usd:0.001,result:$r,usage:{input_tokens:1,output_tokens:1}}'; }

echo "[1] structural gate: proposals dir is NOT the skills dir"
if [[ "$SKILL_CURATOR_PROPOSALS_DIR" != "$SKILL_CURATOR_SKILLS_DIR" ]]; then ok "proposals != skills (CC does not auto-load proposals)"; else no "proposals == skills"; fi

echo "[2] a normal draft lands under proposals/, skills/ stays empty"
draft="$(jq -nc '{draft:{slug:"normal-skill",name:"normal-skill",description:"d",body:"---\nname: normal-skill\n---\n# x\n"},reason:"r"}')"
mk_env "$draft" > "$TMP/env.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/env.json" bash "$RUN" "$PAY"
if [[ -f "$SKILL_CURATOR_PROPOSALS_DIR/normal-skill/SKILL.md" && -z "$(find "$SKILL_CURATOR_SKILLS_DIR" -type f 2>/dev/null)" ]]; then
  ok "draft under proposals/, skills/ empty"; else no "draft escaped to skills/ or not staged"; fi

echo "[3] adversarial path-traversal slug is sanitized; cannot escape proposals/ or reach skills/"
rm -rf "$SKILL_CURATOR_PROPOSALS_DIR" 2>/dev/null
evil="$(jq -nc '{draft:{slug:"../../../skills/evil",name:"e",description:"d",body:"---\nname: e\n---\n# x\n"},reason:"r"}')"
mk_env "$evil" > "$TMP/evil.json"
SKILL_CURATOR_REVIEWER_CMD="cat $TMP/evil.json" bash "$RUN" "$PAY"
escaped="$(find "$SKILL_CURATOR_SKILLS_DIR" -type f 2>/dev/null)"
outside="$(find "$TMP" -name SKILL.md 2>/dev/null | grep -v "$SKILL_CURATOR_PROPOSALS_DIR" || true)"
if [[ -z "$escaped" && -z "$outside" && -n "$(find "$SKILL_CURATOR_PROPOSALS_DIR" -name SKILL.md 2>/dev/null)" ]]; then
  ok "traversal slug sanitized, contained under proposals/"; else no "slug escaped: skills='$escaped' outside='$outside'"; fi

echo "[4] the reviewer model has NO write: source pins --allowedTools \"\""
if grep -Eq -- '--allowedTools[[:space:]]+""' "$DIR/lib/reviewer-run.sh"; then ok "reviewer pins --allowedTools \"\""; else no "reviewer missing empty allowedTools"; fi

echo "[5] the reviewer wrapper never writes under skills/ (only proposals/ + ledger)"
if ! grep -qE '"?\$SKILL_CURATOR_SKILLS_DIR' "$DIR/lib/reviewer-run.sh"; then ok "reviewer-run.sh does not reference skills dir as a target"; else no "reviewer-run.sh references skills dir"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-staging-gate: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-staging-gate: all $pass passed"
