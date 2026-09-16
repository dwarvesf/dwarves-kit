#!/usr/bin/env bash
# test-gate-opt-out.sh
# The [gate] block switches a quality gate off per project. For each gate: the hook
# BLOCKS with no config (negative control, the behavior before the key existed), then
# ALLOWS once `<key> = false` sits in a COMMITTED, clean .kit.toml, and logs the skip.
# Plus: an uncommitted opt-out does not apply, a broken policy reader means ON (only exit 1
# is off), the operator overlay switches a gate off for every repo, adopt seeds the block
# commented out, a .kit.toml-only diff is inert for the proof classifier, an unknown key is
# on, and the safety gate ignores the block entirely. Runs the REAL hooks with
# CLAUDE_PLUGIN_ROOT pointed at this checkout, the same path a live push/commit/stop hits.
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
gitc() { git -C "$1" init -q -b main; git -C "$1" config user.email t@t; git -C "$1" config user.name t; }
bare() { rm -rf "$1"; mkdir -p "$1"; gitc "$1"; git -C "$1" commit -q --allow-empty -m base; }
repo() { # $1 dir: adopted repo (proof marker) on feat/x, no proof
  rm -rf "$1"; mkdir -p "$1/docs/verification" "$1/src"; gitc "$1"
  echo "# Verification (proof-of-done marker)" > "$1/docs/verification/README.md"
  echo baseline > "$1/src/code.sh"; git -C "$1" add -A; git -C "$1" commit -qm base
  git -C "$1" checkout -qb feat/x
}
write_off() { printf '[gate]\n%s = false\n' "$2" > "$1/.kit.toml"; }
off() { write_off "$1" "$2"; git -C "$1" add .kit.toml; git -C "$1" commit -qm "chore: gate config"; }
PUSH='{"tool_input":{"command":"git push origin feat/x"}}'

echo "== proof_of_done =="
R="$TMP/proof"; repo "$R"; echo change >> "$R/src/code.sh"; git -C "$R" commit -qam "feat: change"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 2 ] && pass "NC: behavioral diff, no proof, no config -> ship-gate BLOCKS" || fail "NC: expected block, got rc=$rc"
printf '%s' "$ERR" | grep -q "proof_of_done = false" && pass "the BLOCKED message names the opt-out key" || fail "BLOCKED message has no opt-out pointer"
write_off "$R" proof_of_done
hook ship-gate.sh "$R" "$PUSH"; rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$ERR" | grep -q "not applied until the file is committed"; } && pass "NC: uncommitted .kit.toml false -> still BLOCKS, with the commit hint" || fail "uncommitted opt-out applied or no hint (rc=$rc): $ERR"
git -C "$R" add .kit.toml; git -C "$R" commit -qm "chore: gate config"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "committed proof_of_done = false -> ship-gate ALLOWS the same push" || fail "proof_of_done=false still blocked (rc=$rc): $ERR"
grep -q 'OFF-BY-CONFIG | proof-gate | x' "$DWARVES_KIT_LOG_DIR/ship-gate.log" && pass "the skip leaves an OFF-BY-CONFIG line in ship-gate.log" || fail "no OFF-BY-CONFIG log line"
echo edited >> "$R/.kit.toml"
hook ship-gate.sh "$R" "$PUSH"; rc=$?
[ $rc -eq 2 ] && pass "NC: a dirty edit on the committed .kit.toml -> gate back ON" || fail "dirty .kit.toml still switched the gate off (rc=$rc)"
git -C "$R" checkout -q -- .kit.toml

echo "== broken policy reader (only exit 1 means off) =="
BK="$TMP/brokenkit"; mkdir -p "$BK"; cp -R "$KIT_DIR/lib" "$BK/lib"; printf 'if fi\n' > "$BK/lib/gate/gate-policy.sh"
ERR="$( cd "$R" && printf '%s' "$PUSH" | CLAUDE_PLUGIN_ROOT="$BK" bash "$KIT_DIR/hooks/ship-gate.sh" 2>&1 >/dev/null )"; rc=$?
[ $rc -eq 2 ] && pass "NC: syntax-broken gate-policy.sh (exit 2) -> ship-gate treats the gate as ON and BLOCKS" || fail "broken reader read as off (rc=$rc)"
ERR="$( cd "$R" && printf '%s' "$PUSH" | CLAUDE_PLUGIN_ROOT="$TMP/nokit" bash "$KIT_DIR/hooks/ship-gate.sh" 2>&1 >/dev/null )"; rc=$?
[ $rc -eq 0 ] && pass "no kit lib at all -> proof gate fails open (pre-existing contract, unchanged)" || fail "missing lib changed the fail-open contract (rc=$rc)"

echo "== lane_gates (no-Lane refusal in an adopted repo) =="
L="$TMP/lane"; repo "$L"; mkdir -p "$L/docs/specs"
printf '# SPEC-001 x\n\nno lane header here\n' > "$L/docs/specs/SPEC-001-x.md"
git -C "$L" add -A; git -C "$L" commit -qm "docs: spec without lane"
hook ship-gate.sh "$L" "$PUSH"; rc=$?
{ [ $rc -eq 2 ] && printf '%s' "$ERR" | grep -q "no 'Lane:' header" && printf '%s' "$ERR" | grep -q "lane_gates = false"; } && pass "NC: spec with no Lane, no config -> BLOCKS on the lane gate, message names lane_gates" || fail "NC lane: rc=$rc: $ERR"
off "$L" lane_gates
hook ship-gate.sh "$L" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "committed lane_gates = false (proof gate still on) -> ship-gate ALLOWS the lane-less spec" || fail "lane_gates=false still blocked (rc=$rc): $ERR"
[ "$(grep -c 'OFF-BY-CONFIG | lane-gate | x' "$DWARVES_KIT_LOG_DIR/ship-gate.log")" -eq 1 ] && pass "exactly one lane-gate OFF-BY-CONFIG line per push" || fail "lane-gate skip logged $(grep -c 'lane-gate' "$DWARVES_KIT_LOG_DIR/ship-gate.log") times"

echo "== proof classifier: .kit.toml is harness config =="
PL="$KIT_DIR/lib/gate/proof-ledger.sh"; BASE="$(git -C "$L" merge-base HEAD main)"
[ "$(bash "$PL" classify "$L" "$BASE")" = inert ] && pass "spec.md + .kit.toml diff -> inert" || fail "docs + .kit.toml diff classified $(bash "$PL" classify "$L" "$BASE")"
echo change >> "$L/src/code.sh"; git -C "$L" commit -qam "feat: code too"
[ "$(bash "$PL" classify "$L" "$BASE")" = behavioral ] && pass "add a code change -> behavioral again" || fail "code + .kit.toml classified $(bash "$PL" classify "$L" "$BASE")"

echo "== understanding_gate (anti-rationalization Stop hook) =="
U="$TMP/understand"; bare "$U"
STOP='{"assistant_response":"I will handle the rest in a follow-up PR.","stop_hook_active":false}'
hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 2 ] && pass "NC: rationalization phrase, no config -> Stop hook BLOCKS" || fail "NC anti-rat: rc=$rc"
off "$U" understanding_gate
hook anti-rationalization.sh "$U" "$STOP"; rc=$?
[ $rc -eq 0 ] && pass "committed understanding_gate = false -> Stop hook ALLOWS" || fail "understanding_gate=false still blocked (rc=$rc)"
grep -q 'OFF-BY-CONFIG | understanding_gate' "$DWARVES_KIT_LOG_DIR/anti-rationalization.log" && pass "the skip is logged in anti-rationalization.log" || fail "no OFF-BY-CONFIG line in anti-rationalization.log"

echo "== commit_format =="
C="$TMP/commit"; bare "$C"
BAD='{"tool_input":{"command":"git commit -m \"updated stuff\""}}'
hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 2 ] && pass "NC: non-conventional subject, no config -> commit-format BLOCKS" || fail "NC commit-format: rc=$rc"
off "$C" commit_format
hook commit-format.sh "$C" "$BAD"; rc=$?
[ $rc -eq 0 ] && pass "committed commit_format = false -> commit-format ALLOWS" || fail "commit_format=false still blocked (rc=$rc)"
grep -q 'OFF-BY-CONFIG | commit_format' "$DWARVES_KIT_LOG_DIR/commit-format.log" && pass "the skip is logged in commit-format.log" || fail "no OFF-BY-CONFIG line in commit-format.log"

echo "== operator overlay + resolver edges =="
O="$TMP/operator-proof"; repo "$O"; echo change >> "$O/src/code.sh"; git -C "$O" commit -qam "feat: change"
mkdir -p "$TMP/operator"; printf '[gate]\nproof_of_done = false\n' > "$TMP/operator/kit.toml"
KIT_CONFIG_OPERATOR="$TMP/operator" hook ship-gate.sh "$O" "$PUSH"; rc=$?
[ $rc -eq 0 ] && pass "operator kit.toml proof_of_done = false -> off for a repo with no .kit.toml, no commit check" || fail "operator overlay ignored (rc=$rc): $ERR"
P="$KIT_DIR/lib/gate/gate-policy.sh"
bash "$P" enabled proof_of_done "$TMP/nowhere" && pass "no project config -> on" || fail "missing config read as off"
bash "$P" enabled not_a_gate "$R" && pass "unknown key -> on" || fail "unknown key read as off"
printf '[gate]\nproof_of_done = true\n' > "$R/.kit.toml"
bash "$P" enabled proof_of_done "$R" && pass "explicit true -> on" || fail "explicit true read as off"
bash "$P" >/dev/null 2>&1; rc=$?; [ $rc -eq 64 ] && pass "no verb -> usage, exit 64" || fail "usage exit code $rc"

echo "== adopt seeds the block commented out =="
A="$TMP/adopt"; bare "$A"
bash "$KIT_DIR/lib/adopt.sh" "$A" >/dev/null 2>&1
{ grep -q '^\[gate\]' "$A/.kit.toml" && grep -q '^# proof_of_done = true' "$A/.kit.toml" && ! grep -q '^proof_of_done' "$A/.kit.toml"; } && pass "fresh adopt seeds [gate] with every key commented (operator overlay still reaches the repo)" || fail "adopt seed shape wrong: $(grep -n 'gate\|proof_of_done' "$A/.kit.toml" 2>&1 | head -3)"

echo "== safety gate has no key =="
S="$TMP/safety"; bare "$S"
printf '[gate]\nproof_of_done = false\nlane_gates = false\nunderstanding_gate = false\ncommit_format = false\n' > "$S/.kit.toml"
git -C "$S" add .kit.toml; git -C "$S" commit -qm "chore: all off"
hook safety-gate.sh "$S" '{"tool_input":{"command":"git push --force origin main"}}'; rc=$?
[ $rc -eq 2 ] && pass "every gate key false, committed -> safety-gate still BLOCKS a force push to main" || fail "safety-gate honoured the gate block (rc=$rc)"

echo "== lint: hooks still never read the config files themselves =="
LEAK="$(grep -rl 'kit\.toml' "$KIT_DIR/hooks" 2>/dev/null || true)"
[ -z "$LEAK" ] && pass "no hooks/*.sh names the config file (leaked: none)" || fail "hook reads config: $LEAK"

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
