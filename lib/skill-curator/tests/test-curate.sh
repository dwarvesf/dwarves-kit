#!/usr/bin/env bash
# TASK-011/012: the curator. propose-only changes nothing; --apply archives via git mv (never rm);
# restore round-trips; pinned skills are protected; non-git host falls back to mv. Mock the curator
# via CC_SI_CURATOR_CMD (no live model). Run: bash tests/test-curate.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$DIR/bin/cc-improve"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export CC_SI_STATE_DIR="$TMP/state" CC_SI_SKILLS_DIR="$TMP/skills"
# NOTE: deliberately do NOT pre-create CC_SI_STATE_DIR , curate_run must create it itself
# (and write its heartbeat) on a fresh host. test [2] asserts the heartbeat lands.

mkskill(){ mkdir -p "$CC_SI_SKILLS_DIR/$1"; printf -- '---\nname: %s\ndescription: %s\n%s---\n# %s\n\n%s\n' \
  "$1" "desc $1" "${3:-}" "$1" "body of $1" > "$CC_SI_SKILLS_DIR/$1/SKILL.md"; }
# git-init skills/ so archive uses git mv.
git -C "$CC_SI_SKILLS_DIR" init -q 2>/dev/null || { mkdir -p "$CC_SI_SKILLS_DIR"; git -C "$CC_SI_SKILLS_DIR" init -q; }
mkskill deploy-aws; mkskill deploy-gcp; mkskill keep-me "" $'pinned: true\n'
git -C "$CC_SI_SKILLS_DIR" add -A 2>/dev/null; git -C "$CC_SI_SKILLS_DIR" -c user.email=t@t -c user.name=t commit -qm init 2>/dev/null
# Mock plan: archive deploy-gcp (absorbed into deploy-aws) + (mis)try to archive the pinned keep-me.
PLAN='{"clusters":[{"umbrella":"deploy","move":"merge","members":["deploy-aws","deploy-gcp"],"rationale":"one deploy umbrella"}],"archive":[{"name":"deploy-gcp","reason":"superseded","absorbed_into":"deploy-aws"},{"name":"keep-me","reason":"x","absorbed_into":null}],"report":"would merge deploy-* and archive deploy-gcp"}'
mkenv(){ jq -nc --arg r "$PLAN" '{type:"result",total_cost_usd:0.002,result:$r,usage:{input_tokens:50,output_tokens:20}}' > "$TMP/env.json"; }
mkenv
export CC_SI_CURATOR_CMD="cat $TMP/env.json"

echo "[1] inventory marks the pinned skill"
. "$DIR/lib/curate.sh"
inv="$(curate_inventory)"
if jq -e '[.[]|select(.name=="keep-me" and .pinned==true)]|length==1' <<<"$inv" >/dev/null && jq -e 'length==3' <<<"$inv" >/dev/null; then ok "3 skills, keep-me pinned"; else no "inventory wrong: $inv"; fi

echo "[2] curate (propose-only) writes a report + heartbeat, changes NOTHING (negative control)"
err="$("$CLI" curate 2>&1 >/dev/null)"   # capture stderr: must be clean (no fresh-dir heartbeat error)
if [[ -n "$(find "$CC_SI_STATE_DIR" -name 'curator-report-*.md' 2>/dev/null)" && -f "$CC_SI_STATE_DIR/curator.heartbeat" && -d "$CC_SI_SKILLS_DIR/deploy-gcp" && ! -d "$CC_SI_SKILLS_DIR/_archive" && -z "$err" ]]; then
  ok "report + heartbeat written on a fresh state dir, no skill moved, no stderr"; else no "propose-only wrong (err='$err')"; fi

echo "[3] curate --apply archives deploy-gcp via git mv to _archive/ (skill content preserved)"
"$CLI" curate --apply >/dev/null
if [[ ! -d "$CC_SI_SKILLS_DIR/deploy-gcp" && -f "$CC_SI_SKILLS_DIR/_archive/deploy-gcp/SKILL.md" ]] && grep -q 'body of deploy-gcp' "$CC_SI_SKILLS_DIR/_archive/deploy-gcp/SKILL.md"; then
  ok "deploy-gcp archived (moved, not deleted)"; else no "apply did not archive correctly"; fi

echo "[4] the pinned skill was NOT archived (wrapper guard)"
if [[ -d "$CC_SI_SKILLS_DIR/keep-me" && ! -d "$CC_SI_SKILLS_DIR/_archive/keep-me" ]]; then ok "pinned keep-me protected"; else no "pinned skill archived"; fi

echo "[5] archive recorded absorbed_into in the manifest"
if grep -qE '^deploy-gcp	.*	deploy-aws$' "$CC_SI_SKILLS_DIR/_archive/manifest.tsv" 2>/dev/null; then ok "manifest records absorbed_into=deploy-aws"; else no "manifest wrong: $(cat "$CC_SI_SKILLS_DIR/_archive/manifest.tsv" 2>/dev/null)"; fi

echo "[6] the archive code path contains no 'rm' COMMAND (never deletes; comments excluded)"
if ! sed 's/#.*//' "$DIR/lib/curate.sh" | grep -qE '\brm\b'; then ok "no rm command in curate.sh code"; else no "rm command present: $(sed 's/#.*//' "$DIR/lib/curate.sh" | grep -nE '\brm\b')"; fi

echo "[7] restore round-trips deploy-gcp back from _archive/"
"$CLI" restore deploy-gcp >/dev/null
if [[ -d "$CC_SI_SKILLS_DIR/deploy-gcp" && ! -d "$CC_SI_SKILLS_DIR/_archive/deploy-gcp" ]] && grep -q 'body of deploy-gcp' "$CC_SI_SKILLS_DIR/deploy-gcp/SKILL.md"; then
  ok "restore moved it back, content intact"; else no "restore failed"; fi

echo "[8] non-git skills/ falls back to mv + manifest (still no rm), archives + warns"
NG="$TMP/nogit"; mkdir -p "$NG"; export CC_SI_SKILLS_DIR="$NG"
mkdir -p "$NG/old-skill"; printf -- '---\nname: old-skill\n---\n# x\nbody\n' > "$NG/old-skill/SKILL.md"
mkenv2(){ jq -nc --arg r '{"clusters":[],"archive":[{"name":"old-skill","reason":"stale","absorbed_into":null}],"report":"archive old-skill"}' '{type:"result",total_cost_usd:0.001,result:$r}' > "$TMP/env2.json"; }
mkenv2
CC_SI_CURATOR_CMD="cat $TMP/env2.json" "$CLI" curate --apply >/dev/null
if [[ ! -d "$NG/old-skill" && -f "$NG/_archive/old-skill/SKILL.md" ]]; then ok "non-git archive via mv worked"; else no "non-git fallback failed"; fi

echo "[9] curator unavailable (non-zero) -> nothing changed, no crash (negative control)"
export CC_SI_SKILLS_DIR="$TMP/skills"
before="$(find "$CC_SI_SKILLS_DIR" -name SKILL.md | wc -l | tr -d ' ')"
CC_SI_CURATOR_CMD="false" "$CLI" curate --apply >/dev/null 2>&1; rc=$?
after="$(find "$CC_SI_SKILLS_DIR" -name SKILL.md | wc -l | tr -d ' ')"
if [[ $rc -eq 0 && "$before" -eq "$after" ]]; then ok "curator-unavailable -> no change, exit 0"; else no "unavailable handling wrong (rc=$rc $before->$after)"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-curate: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-curate: all $pass passed"
