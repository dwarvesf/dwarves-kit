#!/usr/bin/env bash
# test-wrap-merge-gate.sh -- `wrap merge --apply` runs the ship-gate on the PR head before it
# merges, and the re-merge push (shared with `land`) runs it on the merge commit before it
# pushes. The PreToolUse hook never sees either from inside the wrap script.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap-merge.sh lib/wrap/wrap-common.sh hooks/ship-gate.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

GATES="$TMPD/gates"; mkdir -p "$GATES"
cat > "$GATES/pass.sh" <<'GATE'
#!/usr/bin/env bash
cat > "$(dirname "$0")/pass.in"
git -C "$(jq -r '.cwd' "$(dirname "$0")/pass.in")" rev-parse HEAD > "$(dirname "$0")/pass.head" 2>/dev/null
exit 0
GATE
cat > "$GATES/block.sh" <<'GATE'
#!/usr/bin/env bash
cat >/dev/null
echo "BLOCKED: stub gate says no" >&2
exit 2
GATE
chmod +x "$GATES"/*.sh

# mg_build <name> -- a bare origin with main and feat/gate (one commit ahead), a clone sitting on main
mg_build() {
  local name="$1" work="$TMPD/mg-work-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  # The real gate refuses the t@t fixture identity before it reaches the arm under test.
  git -C "$work" config user.email dev@dwarves.foundation; git -C "$work" config user.name dev
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf 'base\n' > "$work/a.txt"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/gate
  printf 'feature\n' > "$work/b.txt"
  git -C "$work" add -A; git -C "$work" commit -qm "feat: gate fixture"
  git -C "$work" checkout -q main
  git clone -q --bare "$work" "$TMPD/mg-bare-$name"
  MG="$TMPD/mg-clone-$name"
  git clone -q "$TMPD/mg-bare-$name" "$MG"; gitc "$MG"
  git -C "$MG" remote set-head origin main >/dev/null 2>&1
  MG_TIP="$(git -C "$MG" rev-parse origin/feat/gate)"
}
mg_json() { # mg_json <number> <tip>
  printf '{"number":%s,"title":"gate fixture","headRefName":"feat/gate","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2"
}
mg_open() { printf '[{"number":%s,"title":"gate fixture","headRefName":"feat/gate"}]' "$1"; }
mg_merge() { # mg_merge <n> [VAR=val ...] -- one --apply merge of PR <n> in $MG
  local n="$1"; shift
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  env -u CLAUDE_PLUGIN_ROOT -u WRAP_LAND_SHIP_GATE GH_STUB_OPEN_PRS="$(mg_open "$n")" "GH_STUB_PR_${n}=$(mg_json "$n" "$MG_TIP")" "$@" \
    "$WRAP" merge --apply --pr "$n" "$MG" 2>&1
}
mg_merged() { grep -q '^pr merge' "$GH_STUB_CALLS" && echo 0 || echo 1; }
mg_scratch_gone() { [ "$(git -C "$MG" worktree list | wc -l)" -eq 1 ] && echo 0 || echo 1; }

echo "--- merge_runs_gate: a blocking gate stops the merge, leaves the PR open, cleans its scratch worktree"
mg_build g1
out="$(mg_merge 81 WRAP_LAND_SHIP_GATE="$GATES/block.sh")"; rc=$?
chk "merge_runs_gate: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "merge_runs_gate: says the gate blocked the merge" "$out" "MERGE REFUSED #81: ship-gate blocked the push"
chk_has "merge_runs_gate: relays the gate's reason" "$out" "BLOCKED: stub gate says no"
chk_has "merge_runs_gate: says the PR is left open" "$out" "FAILED merge #81: left open"
chk "merge_runs_gate: no pr merge call" "$([ "$(mg_merged)" -eq 1 ]; echo $?)"
chk "merge_runs_gate: the scratch worktree is gone" "$(mg_scratch_gone)"

echo "--- merge_gate_payload: a passing gate reads the PR head in a worktree, then the merge goes on"
mg_build g2
rm -f "$GATES/pass.in" "$GATES/pass.head"
out="$(mg_merge 82 WRAP_LAND_SHIP_GATE="$GATES/pass.sh")"; rc=$?
chk_has "merge_gate_payload: the merge ran" "$out" "merged #82"
chk_no "merge_gate_payload: no refusal" "$out" "REFUSED"
chk "merge_gate_payload: the gate cwd HEAD is the PR head" "$([ "$(cat "$GATES/pass.head" 2>/dev/null)" = "$MG_TIP" ]; echo $?)"
chk "merge_gate_payload: the gate cwd is not the main checkout" "$([ "$(jq -r '.cwd' "$GATES/pass.in" 2>/dev/null)" != "$MG" ]; echo $?)"
chk "merge_gate_payload: the gate got the push command for the head branch" \
  "$([ "$(jq -r '.tool_input.command' "$GATES/pass.in" 2>/dev/null)" = "git push origin feat/gate" ]; echo $?)"
chk "merge_gate_payload: the PR was merged" "$(mg_merged)"
chk "merge_gate_payload: the scratch worktree is gone" "$(mg_scratch_gone)"

echo "--- merge_gate_missing: a missing gate file fails closed"
mg_build g3
out="$(mg_merge 83 WRAP_LAND_SHIP_GATE="$GATES/nope.sh")"; rc=$?
chk "merge_gate_missing: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "merge_gate_missing: names the missing hook" "$out" "ship-gate hook not found"
chk "merge_gate_missing: no pr merge call" "$([ "$(mg_merged)" -eq 1 ]; echo $?)"

echo "--- merge_stale_codex_pin: the REAL ship-gate blocks a merge of a head with a stale codex pin"
mg_build g4
WK="$TMPD/mg-wk-g4"; git clone -q "$TMPD/mg-bare-g4" "$WK"; gitc "$WK"
git -C "$WK" config user.email dev@dwarves.foundation; git -C "$WK" config user.name dev
git -C "$WK" checkout -q feat/gate
mkdir -p "$WK/lib/codex" "$WK/hooks"
cp "$KIT_DIR/lib/codex/repin.sh" "$WK/lib/codex/repin.sh"
printf '#!/bin/bash\n# demo-hook.sh -- a stub hook\n' > "$WK/hooks/demo-hook.sh"
h="$(shasum -a 256 "$WK/hooks/demo-hook.sh" | awk '{print $1}')"
printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"hash_file \\"${PLUGIN_ROOT}/hooks/demo-hook.sh\\" | /usr/bin/grep -q '"'"'^%s '"'"' || exit 2"}]}]}}\n' "$h" > "$WK/hooks/codex-hooks.json"
git -C "$WK" add -A; git -C "$WK" commit -qm "chore: pin the demo hook"
printf '# edited\n' >> "$WK/hooks/demo-hook.sh"
git -C "$WK" add -A; git -C "$WK" commit -qm "fix: edit a pinned hook"
git -C "$WK" push -q origin feat/gate
git -C "$MG" fetch -q origin; MG_TIP="$(git -C "$MG" rev-parse origin/feat/gate)"
out="$(mg_merge 84 DWARVES_KIT_LOG_DIR="$TMPD/g4-log")"; rc=$?
chk "merge_stale_codex_pin: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "merge_stale_codex_pin: says the gate blocked the merge" "$out" "MERGE REFUSED #84: ship-gate blocked the push"
chk_has "merge_stale_codex_pin: the codex-pin arm is the reason" "$out" "stale pin: hooks/demo-hook.sh"
chk "merge_stale_codex_pin: no pr merge call" "$([ "$(mg_merged)" -eq 1 ]; echo $?)"
chk "merge_stale_codex_pin: the scratch worktree is gone" "$(mg_scratch_gone)"

echo "--- merge_codex_pin_escape: the documented escape lets the same head merge"
out="$(mg_merge 84 DWARVES_KIT_LOG_DIR="$TMPD/g4-log" DWARVES_KIT_SKIP_CODEX_PIN=1)"
chk_no "merge_codex_pin_escape: the pin arm no longer blocks" "$out" "stale pin: hooks/demo-hook.sh"
chk "merge_codex_pin_escape: the PR was merged" "$(mg_merged)"

echo "--- remerge_push_runs_gate: the re-merge push gates the merge commit and undoes it on a refusal"
build_rm() { # a bare origin whose main and feat/gate both appended to a union-marked log
  local name="$1" work="$TMPD/rm-work-$1" clone="$TMPD/rm-clone-$1"
  mkdir -p "$work/_meta"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf 'base line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/gate
  printf 'branch line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" commit -qam "branch entry"
  git -C "$work" checkout -q main
  printf 'main line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  git -C "$work" commit -qam "main entry"
  git clone -q --bare "$work" "$TMPD/rm-bare-$name"
  git clone -q "$TMPD/rm-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/gate origin/feat/gate
  git -C "$clone" checkout -q main
  git -C "$clone" worktree add -q "$TMPD/rm-wt-$name" feat/gate
}
build_rm r1
RM="$TMPD/rm-clone-r1"; RM_BARE="$TMPD/rm-bare-r1"; RM_TIP="$(git -C "$RM" rev-parse feat/gate)"
conflict_gate_json() { printf '{"number":%s,"title":"gate fixture","headRefName":"feat/gate","headRefOid":"%s","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2"; }
: > "$GH_STUB_CALLS"
out="$(env -u CLAUDE_PLUGIN_ROOT GH_STUB_OPEN_PRS="$(mg_open 85)" GH_STUB_PR_85="$(conflict_gate_json 85 "$RM_TIP")" \
  WRAP_LAND_SHIP_GATE="$GATES/block.sh" "$WRAP" merge --apply --no-pull --pr 85 "$RM" 2>&1)"
chk_has "remerge_push_runs_gate: says the gate blocked the push" "$out" "PUSH REFUSED: ship-gate blocked the push"
chk_has "remerge_push_runs_gate: the merge commit is undone" "$out" "feat/gate is back at"
chk "remerge_push_runs_gate: origin still holds the original tip" \
  "$([ "$(git -C "$RM_BARE" rev-parse feat/gate)" = "$RM_TIP" ]; echo $?)"
chk "remerge_push_runs_gate: the local branch is back at the original tip" \
  "$([ "$(git -C "$RM" rev-parse feat/gate)" = "$RM_TIP" ]; echo $?)"
chk "remerge_push_runs_gate: no pr merge call" "$([ "$(mg_merged)" -eq 1 ]; echo $?)"

echo "---"
echo "test-wrap-merge-gate: $PASS passed, $FAIL FAILED"
[ "$FAIL" -eq 0 ]
