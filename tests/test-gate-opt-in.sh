#!/usr/bin/env bash
# test-gate-opt-in.sh
# The quality gates are OPT-IN: with only the kit root's kit.toml (every key false) and no
# operator overlay, each blocking hook PASSES and logs OFF-BY-CONFIG. A project `true` turns
# a gate on, committed or not (turning a gate on is never a bypass). adopt seeds the [gate]
# block with explicit resolved values: false from the kit default, true under a gates-on
# overlay. Sibling: test-gate-opt-out.sh runs the same hooks with the gates ON.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_ROOT="$KIT_DIR" KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$TMP/no-operator"
export DWARVES_KIT_LOG_DIR="$TMP/logs" KIT_LEDGER_DIR="$TMP/ledger"
mkdir -p "$DWARVES_KIT_LOG_DIR" "$KIT_LEDGER_DIR"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }
hook() { ERR="$( cd "$2" && printf '%s' "$3" | bash "$KIT_DIR/hooks/$1" 2>&1 >/dev/null )"; }
gitc() { git -C "$1" init -q -b main; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }
bare() { rm -rf "$1"; mkdir -p "$1"; gitc "$1"; git -C "$1" commit -q --allow-empty -m base; }
repo() { rm -rf "$1"; mkdir -p "$1/docs/verification" "$1/src"; gitc "$1"
  echo "# Verification (proof-of-done marker)" > "$1/docs/verification/README.md"
  echo baseline > "$1/src/code.sh"; git -C "$1" add -A; git -C "$1" commit -qm base
  git -C "$1" checkout -qb feat/x; echo change >> "$1/src/code.sh"; git -C "$1" commit -qam "feat: change"; }
PUSH='{"tool_input":{"command":"git push origin feat/x"}}'
STOP='{"assistant_response":"I will handle the rest in a follow-up PR.","stop_hook_active":false}'
BAD='{"tool_input":{"command":"git commit -m \"updated stuff\""}}'

echo "== kit defaults: every quality gate off =="
for k in proof_of_done lane_gates understanding_gate commit_format; do
  bash "$KIT_DIR/lib/gate/gate-policy.sh" enabled "$k" "$TMP/nowhere"; rc=$?
  [ $rc -eq 1 ] && pass "kit root only: $k resolves off (exit 1)" || fail "$k defaulted on (rc=$rc)"
done
R="$TMP/proof"; repo "$R"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "adopted repo, behavioral diff, no proof, no config -> ship-gate PASSES" || fail "default blocked (rc=$rc): $ERR"
grep -q 'OFF-BY-CONFIG | proof-gate | x' "$DWARVES_KIT_LOG_DIR/ship-gate.log" && pass "and logs OFF-BY-CONFIG" || fail "no OFF-BY-CONFIG line"
U="$TMP/understand"; bare "$U"; hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 0 ] && pass "Stop hook passes a rationalization phrase by default" || fail "Stop hook blocked by default (rc=$rc)"
C="$TMP/commit"; bare "$C"; hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 0 ] && pass "commit-format passes a bad subject by default" || fail "commit-format blocked by default (rc=$rc)"

echo "== a project true turns a gate on =="
printf '[gate]\nproof_of_done = true\n' > "$R/.kit.toml"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 2 ] && pass "uncommitted proof_of_done = true -> ship-gate BLOCKS (turning on is never commit-gated)" || fail "project true ignored (rc=$rc)"
git -C "$R" add .kit.toml; git -C "$R" commit -qm "chore: gates on"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 2 ] && pass "committed proof_of_done = true -> ship-gate BLOCKS, message names the key" || fail "committed true ignored (rc=$rc)"
printf '%s' "$ERR" | grep -q "proof_of_done = false" && pass "BLOCKED text still shows the opt-out pointer" || fail "no pointer in BLOCKED text"
printf '[gate]\nunderstanding_gate = true\n' > "$U/.kit.toml"; hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 2 ] && pass "understanding_gate = true -> Stop hook BLOCKS" || fail "Stop hook stayed off (rc=$rc)"
printf '[gate]\ncommit_format = true\n' > "$C/.kit.toml"; hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 2 ] && pass "commit_format = true -> commit-format BLOCKS" || fail "commit-format stayed off (rc=$rc)"

echo "== adopt seeds explicit resolved values =="
A="$TMP/adopt-default"; bare "$A"; bash "$KIT_DIR/lib/adopt.sh" "$A" >/dev/null 2>&1
{ grep -q '^\[gate\]' "$A/.kit.toml" && grep -q '^proof_of_done = false$' "$A/.kit.toml" && grep -q '^commit_format = false$' "$A/.kit.toml" && grep -q 'understanding_gate .*Stop hook' "$A/.kit.toml"; } \
  && pass "no overlay: adopt seeds every key = false, each explained in a comment" || fail "default seed wrong: $(grep -n 'gate\|_gate\|proof' "$A/.kit.toml" | head -4)"
B="$TMP/adopt-on"; bare "$B"; KIT_CONFIG_OPERATOR="$KIT_DIR/tests/fixtures/gates-on" bash "$KIT_DIR/lib/adopt.sh" "$B" >/dev/null 2>&1
grep -q '^proof_of_done = true$' "$B/.kit.toml" && pass "gates-on overlay: adopt seeds proof_of_done = true (the preset follows the operator)" || fail "overlay not reflected in seed"

echo "== install prints the how-to =="
grep -q "OFF by default. Turn one on per repo" "$KIT_DIR/install.sh" && pass "install.sh ends with the gates how-to tip" || fail "install tip missing"

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
