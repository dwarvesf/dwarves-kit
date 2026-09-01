#!/usr/bin/env bash
# TASK-007: the /skill-review promote gate (bin/skill-review). promote moves, reject discards (to
# _rejected, never rm), refuse-overwrite, secret-refuse, unrelated skills untouched, auto-promote
# eligibility. Run: bash tests/test-promote.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$DIR/bin/skill-review"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export SKILL_CURATOR_STATE_DIR="$TMP/state" SKILL_CURATOR_PROPOSALS_DIR="$TMP/proposals" SKILL_CURATOR_SKILLS_DIR="$TMP/skills"

mkdraft(){ mkdir -p "$SKILL_CURATOR_PROPOSALS_DIR/$1"; printf '%s\n' "$2" > "$SKILL_CURATOR_PROPOSALS_DIR/$1/SKILL.md"; }
GOOD='---
name: deploy-via-wrangler
description: deploy a worker
---
# body'
FAKE_SECRET="sk-ant-$(printf 'api03'; printf 'X%.0s' $(seq 1 30))"
SECRET="---
name: bad
---
export T=$FAKE_SECRET"

echo "[1] list shows staged drafts"
mkdraft deploy-via-wrangler "$GOOD"; mkdraft other-skill "$GOOD"
lst="$("$CLI" list)"   # capture first: `producer | grep -q` would SIGPIPE the producer under pipefail
if grep -q '^deploy-via-wrangler' <<<"$lst" && grep -q '^other-skill' <<<"$lst"; then ok "list shows both"; else no "list wrong: $lst"; fi

echo "[2] promote moves proposals/<slug> -> skills/<slug>, proposal gone"
"$CLI" promote deploy-via-wrangler >/dev/null
if [[ -f "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/SKILL.md" && ! -d "$SKILL_CURATOR_PROPOSALS_DIR/deploy-via-wrangler" ]]; then ok "promoted + proposal removed"; else no "promote did not move"; fi

echo "[3] promote refuses to overwrite a live skill without --force"
mkdraft deploy-via-wrangler "$GOOD"     # stage again; skills/ already has it
"$CLI" promote deploy-via-wrangler >/dev/null 2>&1; rc=$?
if [[ $rc -eq 4 && -d "$SKILL_CURATOR_PROPOSALS_DIR/deploy-via-wrangler" ]]; then ok "refused overwrite (rc=4), draft still staged"; else no "did not refuse overwrite (rc=$rc)"; fi

echo "[4] promote --force replaces but backs up the old (never rm)"
printf 'LIVE-MARKER\n' >> "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/SKILL.md"
"$CLI" promote deploy-via-wrangler --force >/dev/null 2>&1
if [[ -f "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/SKILL.md" ]] && ! grep -q LIVE-MARKER "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/SKILL.md" && [[ -n "$(find "$SKILL_CURATOR_PROPOSALS_DIR/_replaced" -name SKILL.md 2>/dev/null)" ]] && grep -rq LIVE-MARKER "$SKILL_CURATOR_PROPOSALS_DIR/_replaced" 2>/dev/null; then
  ok "force replaced; old skill backed up to _replaced/"; else no "force/backup wrong"; fi

echo "[5] promote refuses a draft that still contains a secret"
mkdraft secret-draft "$SECRET"
"$CLI" promote secret-draft >/dev/null 2>&1; rc=$?
if [[ $rc -eq 3 && ! -d "$SKILL_CURATOR_SKILLS_DIR/secret-draft" && -d "$SKILL_CURATOR_PROPOSALS_DIR/secret-draft" ]]; then ok "secret draft refused (rc=3), not promoted"; else no "secret promote not refused (rc=$rc)"; fi

echo "[6] reject moves to _rejected/ (recoverable, not deleted)"
"$CLI" reject other-skill >/dev/null
if [[ ! -d "$SKILL_CURATOR_PROPOSALS_DIR/other-skill" && -f "$SKILL_CURATOR_PROPOSALS_DIR/_rejected/other-skill/SKILL.md" ]]; then ok "rejected -> _rejected/ (recoverable)"; else no "reject did not move to _rejected"; fi

echo "[7] reject/promote left unrelated live skills untouched"
mkdir -p "$SKILL_CURATOR_SKILLS_DIR/unrelated"; printf 'KEEP\n' > "$SKILL_CURATOR_SKILLS_DIR/unrelated/SKILL.md"
"$CLI" reject secret-draft >/dev/null
if grep -q KEEP "$SKILL_CURATOR_SKILLS_DIR/unrelated/SKILL.md"; then ok "unrelated skill untouched"; else no "unrelated skill changed"; fi

echo "[8] auto-promote OFF by default -> promotes nothing even for an eligible draft"
rm -rf "$SKILL_CURATOR_PROPOSALS_DIR" 2>/dev/null
mkdir -p "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler"   # umbrella exists
mkdraft refadd "$(printf -- '---\nname: refadd\ncc-si-kind: references-add\ncc-si-umbrella: deploy-via-wrangler\ncc-si-path: references/extra.md\n---\n# add')"
out_off="$(SKILL_CURATOR_AUTO_PROMOTE=false "$CLI" auto 2>&1)"
if grep -q 'disabled' <<<"$out_off" && [[ ! -f "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/references/extra.md" ]]; then ok "auto off -> nothing promoted"; else no "auto promoted while off"; fi

echo "[9] auto-promote ON -> promotes ONLY the references-add to an existing umbrella"
mkdraft newskill "$GOOD"    # a NEW skill draft must NOT be auto-promoted
out_on="$(SKILL_CURATOR_AUTO_PROMOTE=true "$CLI" auto 2>&1)"
if [[ -f "$SKILL_CURATOR_SKILLS_DIR/deploy-via-wrangler/references/extra.md" && ! -d "$SKILL_CURATOR_SKILLS_DIR/newskill" && -d "$SKILL_CURATOR_PROPOSALS_DIR/newskill" ]]; then
  ok "auto on -> references-add promoted, new skill left staged"; else no "auto-promote eligibility wrong: $out_on"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-promote: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-promote: all $pass passed"
