#!/usr/bin/env bash
# test-wrap-land-gate.sh -- `wrap land` (no --draft) runs the ship-gate before its push.
# The PreToolUse hook never sees the push land makes from inside its script, so land calls
# hooks/ship-gate.sh itself; before this, only --draft did, and a stale codex pin or a
# mktemp violation landed unchecked. Shares the harness in tests/lib/wrap-stub.sh.
# modules under test: lib/wrap/wrap-land.sh hooks/ship-gate.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

GATES="$TMPD/gates"; mkdir -p "$GATES"
cat > "$GATES/pass.sh" <<'GATE'
#!/usr/bin/env bash
cat > "$(dirname "$0")/pass.in"
exit 0
GATE
cat > "$GATES/block.sh" <<'GATE'
#!/usr/bin/env bash
cat >/dev/null
echo "BLOCKED: stub gate says no" >&2
exit 2
GATE
chmod +x "$GATES"/*.sh

# nd_build <name> -- a landable worktree (feat/land, one commit ahead of main)
nd_build() {
  build_land "$1"
  ND_WT="$(cd "$TMPD/ld-repo-$1/wt" && pwd -P)"; ND_BARE="$TMPD/ld-bare-$1"
}
nd_pushed() { git -C "$ND_BARE" rev-parse --verify feat/land >/dev/null 2>&1 && echo 0 || echo 1; }
nd_not_pushed() { git -C "$ND_BARE" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0; }
nd_land() { # nd_land [VAR=val ...] -- one non-draft land of $ND_WT
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  env -u CLAUDE_PLUGIN_ROOT -u WRAP_LAND_SHIP_GATE GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 "$@" "$WRAP" land "$ND_WT" --no-pull 2>&1
}

echo "--- land_nondraft_runs_gate: a blocking gate stops a non-draft land before the push"
nd_build ng1
out="$(nd_land WRAP_LAND_SHIP_GATE="$GATES/block.sh")"; rc=$?
chk "land_nondraft_runs_gate: a gate exit 2 refuses with exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land_nondraft_runs_gate: says the gate blocked the push" "$out" "PUSH REFUSED: ship-gate blocked the push"
chk_has "land_nondraft_runs_gate: relays the gate's reason" "$out" "BLOCKED: stub gate says no"
chk "land_nondraft_runs_gate: nothing was pushed" "$(nd_not_pushed)"
chk "land_nondraft_runs_gate: no PR was created" "$([ "$(grep -cE '^pr create' "$GH_STUB_CALLS")" -eq 0 ]; echo $?)"

echo "--- land_nondraft_gate_payload: a passing gate sees the worktree and the push command, then the land goes on"
nd_build ng2
rm -f "$GATES/pass.in"
out="$(nd_land WRAP_LAND_SHIP_GATE="$GATES/pass.sh")"
chk "land_nondraft_gate_payload: the gate got the worktree as .cwd" "$([ "$(jq -r '.cwd' "$GATES/pass.in" 2>/dev/null)" = "$ND_WT" ]; echo $?)"
chk "land_nondraft_gate_payload: the gate got the push command" \
  "$([ "$(jq -r '.tool_input.command' "$GATES/pass.in" 2>/dev/null)" = "git push origin feat/land" ]; echo $?)"
chk "land_nondraft_gate_payload: the branch was pushed" "$(nd_pushed)"

echo "--- land_nondraft_stale_codex_pin: the REAL ship-gate blocks a non-draft land that carries a stale codex pin"
# A kit-shaped branch: a pinned hook, then an edit to it with no repin. Uses the real hook
# (WRAP_LAND_SHIP_GATE unset) so the arm under test is the codex-pin arm itself.
nd_build ng3
# The fixture commits carry t@t, which the real gate's identity arm refuses before it reaches
# the pin arm: give the branch a real identity first.
git -C "$ND_WT" config user.email dev@dwarves.foundation; git -C "$ND_WT" config user.name dev
git -C "$ND_WT" rebase -q main --exec 'git commit -q --amend --no-edit --reset-author' >/dev/null 2>&1
mkdir -p "$ND_WT/lib/codex" "$ND_WT/hooks"
cp "$KIT_DIR/lib/codex/repin.sh" "$ND_WT/lib/codex/repin.sh"
printf '#!/bin/bash\n# demo-hook.sh -- a stub hook\n' > "$ND_WT/hooks/demo-hook.sh"
h="$(shasum -a 256 "$ND_WT/hooks/demo-hook.sh" | awk '{print $1}')"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"hash_file \\"${PLUGIN_ROOT}/hooks/demo-hook.sh\\" | /usr/bin/grep -q '"'"'^%s '"'"' || exit 2"}]}]}}\n' "$h" > "$ND_WT/hooks/codex-hooks.json"
git -C "$ND_WT" add -A; git -C "$ND_WT" commit -qm "chore: pin the demo hook"
printf '# edited\n' >> "$ND_WT/hooks/demo-hook.sh"
git -C "$ND_WT" add -A; git -C "$ND_WT" commit -qm "fix: edit a pinned hook"
out="$(nd_land DWARVES_KIT_LOG_DIR="$TMPD/ng3-log")"; rc=$?
chk "land_nondraft_stale_codex_pin: refuses with exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land_nondraft_stale_codex_pin: says the gate blocked the push" "$out" "PUSH REFUSED: ship-gate blocked the push"
chk_has "land_nondraft_stale_codex_pin: the codex-pin arm is the reason" "$out" "stale pin: hooks/demo-hook.sh"
chk "land_nondraft_stale_codex_pin: nothing was pushed" "$(nd_not_pushed)"

echo "--- land_nondraft_codex_pin_escape: the documented escape still lets the same branch land"
out="$(nd_land DWARVES_KIT_LOG_DIR="$TMPD/ng3-log" DWARVES_KIT_SKIP_CODEX_PIN=1)"
chk_no "land_nondraft_codex_pin_escape: the pin arm no longer blocks" "$out" "stale pin: hooks/demo-hook.sh"
chk "land_nondraft_codex_pin_escape: the branch was pushed" "$(nd_pushed)"

echo "---"
echo "test-wrap-land-gate: $PASS passed, $FAIL FAILED"
[ "$FAIL" -eq 0 ]
