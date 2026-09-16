#!/usr/bin/env bash
# test-gate-opt-out.sh
# The [gate] block switches a quality gate off per project. For each gate: the hook
# BLOCKS with no config (negative control, the behavior before the key existed), then
# ALLOWS once `<key> = false` sits in the project's .kit.toml. Plus: the operator overlay
# switches a gate off for every repo, an unknown key is on, a missing config is on, and
# the safety gate ignores the block entirely. Runs the REAL hooks with CLAUDE_PLUGIN_ROOT
# pointed at this checkout, the same path a live push/commit/stop hits.
set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export CLAUDE_PLUGIN_ROOT="$KIT_DIR" KIT_CONFIG_ROOT="$KIT_DIR" KIT_CONFIG_OPERATOR="$TMP/no-operator"
export DWARVES_KIT_LOG_DIR="$TMP/logs" KIT_LEDGER_DIR="$TMP/ledger"
mkdir -p "$DWARVES_KIT_LOG_DIR" "$KIT_LEDGER_DIR"
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# hook <hook.sh> <fixture-dir> <stdin-json> -> the hook's exit code, stderr in $ERR
hook() { ERR="$( cd "$2" && printf '%s' "$3" | bash "$KIT_DIR/hooks/$1" 2>&1 >/dev/null )"; }
off() { printf '[gate]\n%s = false\n' "$2" > "$1/.kit.toml"; }

repo() { # $1 dir: adopted repo (proof marker) on feat/x with a behavioral diff and NO proof
  rm -rf "$1"; mkdir -p "$1/docs/verification" "$1/src"
  git -C "$1" init -q -b main; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo "# Verification (proof-of-done marker)" > "$1/docs/verification/README.md"
  echo baseline > "$1/src/code.sh"; git -C "$1" add -A; git -C "$1" commit -qm base
  git -C "$1" checkout -qb feat/x
}
PUSH='{"tool_input":{"command":"git push origin feat/x"}}'

echo "== proof_of_done =="
R="$TMP/proof"; repo "$R"; echo change >> "$R/src/code.sh"; git -C "$R" commit -qam "feat: change"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 2 ] && pass "NC: behavioral diff, no proof, no config -> ship-gate BLOCKS" || fail "NC: expected block, got rc=$rc"
off "$R" proof_of_done
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "proof_of_done = false -> ship-gate ALLOWS the same push" || fail "proof_of_done=false still blocked (rc=$rc): $ERR"
grep -q 'OFF-BY-CONFIG | proof-gate | x' "$DWARVES_KIT_LOG_DIR/ship-gate.log" && pass "the skip leaves an OFF-BY-CONFIG line in ship-gate.log" || fail "no OFF-BY-CONFIG log line"

echo "== lane_gates (no-Lane refusal in an adopted repo) =="
L="$TMP/lane"; repo "$L"; mkdir -p "$L/docs/specs"
printf '# SPEC-001 x\n\nno lane header here\n' > "$L/docs/specs/SPEC-001-x.md"
git -C "$L" add -A; git -C "$L" commit -qm "docs: spec without lane"
hook ship-gate.sh "$L" "$PUSH"; rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$ERR" | grep -q "no 'Lane:' header"; } && pass "NC: spec with no Lane, no config -> ship-gate BLOCKS on the lane gate" || fail "NC lane: rc=$rc: $ERR"
off "$L" lane_gates; git -C "$L" add -A; git -C "$L" commit -qm "chore: switch the lane gate off"
hook ship-gate.sh "$L" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "lane_gates = false (committed .kit.toml, proof gate still on) -> ship-gate ALLOWS" || fail "lane_gates=false still blocked (rc=$rc): $ERR"

echo "== understanding_gate (anti-rationalization Stop hook) =="
U="$TMP/understand"; mkdir -p "$U"; git -C "$U" init -q
STOP='{"assistant_response":"I will handle the rest in a follow-up PR.","stop_hook_active":false}'
hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 2 ] && pass "NC: rationalization phrase, no config -> Stop hook BLOCKS" || fail "NC anti-rat: rc=$rc"
off "$U" understanding_gate
hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 0 ] && pass "understanding_gate = false -> Stop hook ALLOWS" || fail "understanding_gate=false still blocked (rc=$rc)"

echo "== commit_format =="
C="$TMP/commit"; mkdir -p "$C"; git -C "$C" init -q
BAD='{"tool_input":{"command":"git commit -m \"updated stuff\""}}'
hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 2 ] && pass "NC: non-conventional subject, no config -> commit-format BLOCKS" || fail "NC commit-format: rc=$rc"
off "$C" commit_format
hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 0 ] && pass "commit_format = false -> commit-format ALLOWS" || fail "commit_format=false still blocked (rc=$rc)"

echo "== operator overlay + resolver edges =="
O="$TMP/operator-proof"; repo "$O"; echo change >> "$O/src/code.sh"; git -C "$O" commit -qam "feat: change"
mkdir -p "$TMP/operator"; printf '[gate]\nproof_of_done = false\n' > "$TMP/operator/kit.toml"
KIT_CONFIG_OPERATOR="$TMP/operator" hook ship-gate.sh "$O" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "operator kit.toml proof_of_done = false -> off for a repo with no .kit.toml" || fail "operator overlay ignored (rc=$rc): $ERR"
P="$KIT_DIR/lib/gate/gate-policy.sh"
bash "$P" enabled proof_of_done "$TMP/nowhere" && pass "no project config -> on" || fail "missing config read as off"
bash "$P" enabled not_a_gate "$R" && pass "unknown key -> on" || fail "unknown key read as off"
printf '[gate]\nproof_of_done = true\n' > "$R/.kit.toml"
bash "$P" enabled proof_of_done "$R" && pass "explicit true -> on" || fail "explicit true read as off"
bash "$P" enabled bogus 2>/dev/null; bash "$P" >/dev/null 2>&1; [ $? -eq 64 ] && pass "no verb -> usage, exit 64" || fail "usage exit code"

echo "== safety gate has no key =="
S="$TMP/safety"; mkdir -p "$S"; git -C "$S" init -q
printf '[gate]\nproof_of_done = false\nlane_gates = false\nunderstanding_gate = false\ncommit_format = false\n' > "$S/.kit.toml"
hook safety-gate.sh "$S" '{"tool_input":{"command":"git push --force origin main"}}'; rc=$?
[ $rc -eq 2 ] && pass "every gate key false -> safety-gate still BLOCKS a force push to main" || fail "safety-gate honoured the gate block (rc=$rc)"

echo "== lint: hooks still never read the config files themselves =="
LEAK="$(grep -rl 'kit\.toml' "$KIT_DIR/hooks" 2>/dev/null || true)"
[ -z "$LEAK" ] && pass "no hooks/*.sh names the config file (leaked: none)" || fail "hook reads config: $LEAK"

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
