#!/usr/bin/env bash
# test-orchestrate-serial-join.sh -- the serial path of a tiered mega-goal joins once per DAG level
# (docs/specs/SPEC-421-tiered-verification.md rule 4; docs/implementation-notes/serial-path-join.md).
# Offline: a throwaway repo from tests/lib/node-fixture.sh and a mock `claude` that merges the node's
# branch into origin main and flips the box, the way a serial worker merges its own PR.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$KIT/lib/queue/orchestrate.sh"
# shellcheck source=tests/lib/node-fixture.sh
. "$KIT/tests/lib/node-fixture.sh"

fails=0
pass() { echo "PASS $*"; }
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export STUB_LOG="$TMP/stub.log" PANE_VIEWER=none WAVE_CAP=1 WAVE_ROLLING=0 TIER4_CLOSE=0 ORCH

runs() { grep -c '^suite' "$STUB_LOG" 2>/dev/null || true; }
dispatched() { tr '\n' ' ' < "$1/dispatch.log" 2>/dev/null; }
events() { cut -f2,3 "$1/work/mega/.orchestrate/events.log" 2>/dev/null | grep -E 'blocked' | tr '\t\n' ': '; }

# The mock claude: merges the sub-goal's branch into origin main (the worker's own merge), then flips its box.
mk_claude() {
  local d="$1"
  cat > "$d/claude" <<'EOF'
#!/usr/bin/env bash
prompt=$(cat)
id=$(printf '%s\n' "$prompt" | sed -n 's/^NEXT SUB-GOAL: //p' | head -1)
echo "$id" >> "$CASE_DIR/dispatch.log"
br=$(awk -v i="$id" '$1 == i {print $2}' "$CASE_DIR/map")
if [ -n "$br" ]; then
  git -C "$CASE_DIR/push" checkout -q main 2>/dev/null
  git -C "$CASE_DIR/push" pull -q origin main 2>/dev/null
  git -C "$CASE_DIR/push" -c user.email=t@example.com -c user.name=test merge -q --no-edit "$br" >/dev/null 2>&1
  git -C "$CASE_DIR/push" push -q origin main 2>/dev/null
fi
bash "$ORCH" flip "$CASE_DIR/work/mega" "$id" >/dev/null
EOF
  chmod +x "$d/claude"
}

# mk_case <name> <verify> : SG-01 (a.txt) and SG-02 (b.txt) at level 0, SG-03 (c.txt) depending on both at level 1.
mk_case() {
  local d="$TMP/$1"
  nf_init "$d"
  if [ "$2" = off ]; then
    sed 's/^verify = "tiered"/verify = "off"/' "$d/push/.kit.toml" > "$d/kit.off"; cp "$d/kit.off" "$d/push/.kit.toml"
    nf_git "$d/push" commit -q -am "chore: verify off"; git -C "$d/push" push -q origin main 2>/dev/null
    git -C "$d/work" fetch -q origin 2>/dev/null
  fi
  nf_node "$d" feat/node-a a.txt one
  nf_node "$d" feat/node-b b.txt two
  nf_node "$d" feat/node-c c.txt three
  nf_node "$d" feat/node-a2 a2.txt one; nf_node "$d" feat/node-b2 b2.txt two
  nf_mega "$d" SG-01:feat/node-a:11 SG-02:feat/node-b:12 SG-03:feat/node-c:13
  sed -i.bak 's/^- \[ \] SG-03 node , auto ,/- [ ] SG-03 node , auto , depends SG-01 SG-02 ,/' "$d/work/mega/ROADMAP.md"; rm -f "$d/work/mega/ROADMAP.md.bak"
  printf 'SG-01 feat/node-a2\nSG-02 feat/node-b2\nSG-03 feat/node-c\n' > "$d/map"
  nf_heads "$d" 11:feat/node-a 12:feat/node-b 13:feat/node-c
  nf_env "$d"
  mk_claude "$d"
  : > "$STUB_LOG"; : > "$d/dispatch.log"
  export CASE_DIR="$d"
  CLAUDE_CMD="$d/claude"; export CLAUDE_CMD
}

run_serial() {  # dir
  ( bash "$ORCH" run "$1/work/mega" ) >| "$1/out.txt" 2>&1
}

# ---- levels: no deps is 0, a dependent is one deeper than its deepest dependency, a cycle is capped
mk_case levels tiered; D=$CASE_DIR
lv() { bash -c 'source "$1"; _sg_level "$2" "$3"' _ "$ORCH" "$D/work/mega/ROADMAP.md" "$1"; }
[ "$(lv SG-01)" = 0 ] && [ "$(lv SG-02)" = 0 ] && [ "$(lv SG-03)" = 1 ] && pass "level: independent sub-goals are level 0, a dependent of both is level 1" || fail "level: $(lv SG-01) $(lv SG-02) $(lv SG-03)"
printf -- '- [ ] SG-01 node , auto , depends SG-02 , PR #11\n- [ ] SG-02 node , auto , depends SG-01 , PR #12\n' > "$D/cycle.md"
[ "$(bash -c 'source "$1"; _sg_level "$2" SG-01' _ "$ORCH" "$D/cycle.md")" -ge 1 ] && pass "level: a dependency cycle ends (capped), never loops" || fail "level: cycle did not end"

# ---- green: one suite run per level, after the level's last sub-goal; every sub-goal dispatches
mk_case green tiered; D=$CASE_DIR
run_serial "$D"; rc=$?
if [ "$rc" = 0 ] && [ "$(runs)" = 2 ] && [ "$(dispatched "$D")" = "SG-01 SG-02 SG-03 " ]; then pass "serial join: three sub-goals in two levels run the suite twice, once per level, and all dispatch"
else fail "serial green: rc=$rc runs=$(runs) dispatched='$(dispatched "$D")' out: $(tr '\n' ' ' < "$D/out.txt")"; fi
if [ "$(grep '^suite' "$STUB_LOG" | grep -c 'cwd=.*/base$')" = 2 ] && grep -q 'level 0 complete' "$D/out.txt" && grep -q 'level 1 complete' "$D/out.txt"; then pass "serial join: each run is on the base tree in a throwaway worktree, level 0 then level 1"
else fail "serial green: log: $(cat "$STUB_LOG") out: $(tr '\n' ' ' < "$D/out.txt")"; fi
[ "$(git -C "$D/work" worktree list | grep -c kit-join || true)" = 0 ] && pass "serial join: no throwaway worktree is left" || fail "serial join: a worktree is left"

# ---- red: the level's merges break the suite; the next level never dispatches
mk_case red tiered; D=$CASE_DIR
printf 'SG-01 feat/node-a\nSG-02 feat/node-b\nSG-03 feat/node-c\n' > "$D/map"
run_serial "$D"; rc=$?
if [ "$rc" = 1 ] && [ "$(runs)" = 1 ] && [ "$(dispatched "$D")" = "SG-01 SG-02 " ] && grep -q 'RED' "$D/out.txt" && grep -q 'new failure: a and b conflict' "$D/out.txt"; then pass "serial join: a red level join halts the loop before the next level dispatches, naming the new failure"
else fail "serial red: rc=$rc runs=$(runs) dispatched='$(dispatched "$D")' out: $(tr '\n' ' ' < "$D/out.txt")"; fi
[ "$(events "$D")" = "-:blocked " ] && pass "serial join: one blocked event for the level" || fail "serial red: events '$(events "$D")'"

# ---- the join is not run while the level still has an unchecked sub-goal
if [ "$(grep -c 'level 0 complete' "$D/out.txt")" = 1 ] && [ "$(grep -n 'running SG-02' "$D/out.txt" | cut -d: -f1)" -lt "$(grep -n 'level 0 complete' "$D/out.txt" | cut -d: -f1)" ]; then pass "serial join: level 0 is joined once, after SG-02, not after SG-01"
else fail "serial red: order: $(grep -n 'running\|level 0' "$D/out.txt" | tr '\n' ' ')"; fi

# ---- a failure on the lead's known list does not stop the loop
mk_case known tiered; D=$CASE_DIR
STUB_FAIL="Skim settings panel wrong" run_serial "$D"; rc=$?
[ "$rc" = 0 ] && [ "$(dispatched "$D")" = "SG-01 SG-02 SG-03 " ] && pass "serial join: a failure the known-failures list names does not stop the loop" || fail "serial known: rc=$rc dispatched='$(dispatched "$D")' out: $(tr '\n' ' ' < "$D/out.txt")"
mk_case crash tiered; D=$CASE_DIR
STUB_CRASH=1 run_serial "$D"; rc=$?
[ "$rc" = 1 ] && [ "$(dispatched "$D")" = "SG-01 SG-02 " ] && pass "serial join: a crash with no parsed failure is red, never read as known" || fail "serial crash: rc=$rc dispatched='$(dispatched "$D")'"

# ---- no join_cmd at the base: fails closed
mk_case nocmd tiered; D=$CASE_DIR
sed -i.bak '/^join_cmd/d' "$D/push/.kit.toml"; rm -f "$D/push/.kit.toml.bak"; nf_git "$D/push" commit -q -am "chore: no join_cmd"; git -C "$D/push" push -q origin main 2>/dev/null
run_serial "$D"; rc=$?
[ "$rc" = 1 ] && grep -q 'join_cmd is not set' "$D/out.txt" && [ "$(runs)" = 0 ] && pass "serial join: a tiered run with no join_cmd halts at the first level close" || fail "serial nocmd: rc=$rc runs=$(runs) out: $(tr '\n' ' ' < "$D/out.txt")"

# ---- an interrupt mid-join removes the throwaway worktree and stops the loop
mk_case interrupt tiered; D=$CASE_DIR
STUB_SLEEP=30 bash "$ORCH" run "$D/work/mega" >| "$D/out.txt" 2>&1 &
jpid=$!
n=0; until grep -q '^suite' "$STUB_LOG" 2>/dev/null || [ "$n" -ge 150 ]; do sleep 0.2; n=$((n + 1)); done
kill -TERM "$jpid" 2>/dev/null; wait "$jpid" 2>/dev/null; rc=$?
left=$(git -C "$D/work" worktree list | grep -c 'kit-join' || true)
if [ "$rc" = 143 ] && [ "$left" = 0 ] && [ "$(events "$D")" = "-:blocked " ] && grep -q 'interrupted' "$D/out.txt" && [ "$(dispatched "$D")" = "SG-01 SG-02 " ]; then pass "serial join: SIGTERM mid-join removes the worktree, marks the level blocked and starts nothing more (exit 143)"
else fail "serial interrupt: rc=$rc left=$left events '$(events "$D")' dispatched='$(dispatched "$D")' out: $(tr '\n' ' ' < "$D/out.txt")"; fi
pkill -f "$D/work" 2>/dev/null || true

# ---- verify = off: no suite run, no change in what dispatches
mk_case off off; D=$CASE_DIR
run_serial "$D"; rc=$?
[ "$rc" = 0 ] && [ "$(runs)" = 0 ] && [ "$(dispatched "$D")" = "SG-01 SG-02 SG-03 " ] && ! grep -q '\[join\]' "$D/out.txt" && pass "serial join: with verify = off no suite runs and nothing about a join is printed" || fail "serial off: rc=$rc runs=$(runs) out: $(tr '\n' ' ' < "$D/out.txt")"

echo "---"; [ "$fails" = 0 ] && echo "All serial join tests passed." || echo "$fails failed."
exit "$fails"
