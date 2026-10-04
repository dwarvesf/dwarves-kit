#!/usr/bin/env bash
# test-wrap-adopt.sh -- the adopt verb's preflight, dry-run and exit-code cases
# (SPEC-387 T1a). Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures,
# chk). Cases 30 and 31 hand-build the leftovers a landed-but-unproven run leaves,
# the state T1b's apply will produce.
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# adopt_clone <name> -- a bare remote plus a clean clone on main, unadopted. Prints
# the clone path. One commit is everything adopt's fixtures need, so they do not
# ride build_remote's branch farm.
adopt_clone() {
  local name="$1" work="$TMPD/aw-$1" bare="$TMPD/abare-$1" clone="$TMPD/aclone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$bare"
  git clone -q "$bare" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  printf '%s\n' "$clone"
}

# adopt_leftover <name> -- the state a merged-but-unproven adoption run leaves:
# chore/kit-adopt exists locally and on origin, checked out at
# .claude/worktrees/kit-adopt, one real adoption commit ahead of main. Prints the
# repo path; the worktree path is <repo>/.claude/worktrees/kit-adopt.
adopt_leftover() {
  local c wt
  c="$(adopt_clone "l$1")"
  wt="$c/.claude/worktrees/kit-adopt"
  mkdir -p "$c/.claude/worktrees"
  git -C "$c" worktree add -q -b chore/kit-adopt "$wt" origin/main
  bash "$KIT_DIR/lib/adopt.sh" "$wt" >/dev/null 2>&1
  git -C "$wt" add -A
  git -C "$wt" commit -qm "chore: adopt the dwarves-kit operate-contract"
  git -C "$wt" push -q origin chore/kit-adopt
  printf '%s\n' "$c"
}

# adopt_apply <clone> <bare> [--body-file F] -- `wrap adopt --apply` with the gh
# stub wired for the create/merge/verify flow: no open PR for the head, #7 as
# the created number, and `pr merge` pushing the local chore/kit-adopt to
# GH_STUB_LAND_REMOTE's main the way a real squash would. Each stub env can be
# overridden by exporting it before the call (a throwaway LAND_REMOTE keeps a
# failed-merge fixture's real origin clean).
adopt_apply() {
  local c="$1" b="$2"; shift 2
  GH_STUB_OPEN_HEAD_chore_kit_adopt="${GH_STUB_OPEN_HEAD_chore_kit_adopt:-[]}" \
  GH_STUB_CREATE_NUM="${GH_STUB_CREATE_NUM:-7}" \
  GH_STUB_LAND_REPO="${GH_STUB_LAND_REPO:-$c/.claude/worktrees/kit-adopt}" \
  GH_STUB_LAND_REMOTE="${GH_STUB_LAND_REMOTE:-$b}" \
  GH_STUB_LAND_BRANCH="${GH_STUB_LAND_BRANCH:-chore/kit-adopt}" \
  GH_STUB_LAND_DEF="${GH_STUB_LAND_DEF:-main}" \
  "$WRAP" adopt --apply "$@" "$c" 2>&1
}

# adopt_stub <file> <body> -- a WRAP_ADOPT_SH driver: runs the real adopt.sh,
# then <body>, inside the worktree named by $1.
adopt_stub() {
  printf '#!/usr/bin/env bash\nbash "%s/lib/adopt.sh" "$1" || exit $?\n%s\n' \
    "$KIT_DIR" "$2" > "$1"
  chmod +x "$1"
}

# ===========================================================================
echo "=== adopt: a clean unadopted repo dry-runs and writes nothing (1) ==="
# ===========================================================================
C1="$(adopt_clone c1)"
# A commit lands on origin AFTER the clone: if adopt fetched, the tracking tip moves.
p1="$TMPD/apush-c1"; git clone -q "$TMPD/abare-c1" "$p1"; gitc "$p1"
echo newer > "$p1/newer.txt"; git -C "$p1" add -A; git -C "$p1" commit -qm newer
git -C "$p1" push -q origin main
tip1="$(git -C "$C1" rev-parse refs/remotes/origin/main)"
: > "$GH_STUB_CALLS"
out="$("$WRAP" adopt "$C1" 2>&1)"; rc=$?
chk "1: dry run exits 0" "$rc"
chk_has "1: prints would adopt" "$out" "would adopt"
chk "1: no worktree created" "$([ ! -e "$C1/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "1: no chore/kit-adopt ref" "$(git -C "$C1" show-ref --verify --quiet refs/heads/chore/kit-adopt && echo 1 || echo 0)"
chk "1: no fetch, tracking tip unmoved" "$([ "$(git -C "$C1" rev-parse refs/remotes/origin/main)" = "$tip1" ]; echo $?)"
chk "1: gh log holds only auth status" "$([ -z "$(grep -v 'auth status' "$GH_STUB_CALLS")" ]; echo $?)"
chk "1: no override log" "$([ -z "$(find "$KIT_LEDGER_DIR" -name proof-overrides.log 2>/dev/null)" ]; echo $?)"

echo "=== adopt: an adopted repo skips every other check (2) ==="
C2="$(adopt_clone c2)"
bash "$KIT_DIR/lib/adopt.sh" "$C2" >/dev/null 2>&1
git -C "$C2" add -A; git -C "$C2" commit -qm adopt; git -C "$C2" push -q origin main
out="$("$WRAP" adopt "$C2" 2>&1)"; rc=$?
chk "2: exit 0" "$rc"
chk_has "2: prints the skip row" "$out" "skip: already adopted"

echo "=== adopt: an untracked ADOPT_PATHS file refuses, under --apply too (3) ==="
C3="$(adopt_clone c3)"
echo x > "$C3/AGENTS.md"
: > "$GH_STUB_CALLS"
out="$("$WRAP" adopt --apply "$C3" 2>&1)"; rc=$?
chk "3: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "3: refused" "$out" "refused:"
chk_has "3: names the ?? line" "$out" "?? AGENTS.md"
chk "3: no worktree" "$([ ! -e "$C3/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "3: no branch" "$(git -C "$C3" show-ref --verify --quiet refs/heads/chore/kit-adopt && echo 1 || echo 0)"
chk "3: gh log holds only auth status" "$([ -z "$(grep -v 'auth status' "$GH_STUB_CALLS")" ]; echo $?)"

echo "=== adopt: a modified tracked ADOPT_PATHS file refuses (4) ==="
C4="$(adopt_clone c4)"
echo claude > "$C4/CLAUDE.md"
git -C "$C4" add -A; git -C "$C4" commit -qm c; git -C "$C4" push -q origin main
echo edit >> "$C4/CLAUDE.md"
out="$("$WRAP" adopt --apply "$C4" 2>&1)"; rc=$?
chk "4: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "4: names the M line" "$out" " M CLAUDE.md"

echo "=== adopt: every collision kind reports its own path (5, 6) ==="
C5W="$(adopt_clone c5w)"; echo x > "$C5W/WORKFLOW.md"
C5K="$(adopt_clone c5k)"; echo x > "$C5K/.kit.toml"
C5D="$(adopt_clone c5d)"; mkdir -p "$C5D/docs/verification"; echo x > "$C5D/docs/verification/README.md"
C5S="$(adopt_clone c5s)"; mkdir -p "$C5S/.claude"; echo x > "$C5S/.claude/settings.json"
out="$("$WRAP" adopt "$C5W" "$C5K" "$C5D" "$C5S" 2>&1)"; rc=$?
chk "5: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "5: ?? WORKFLOW.md" "$out" "?? WORKFLOW.md"
chk_has "5: ?? .kit.toml" "$out" "?? .kit.toml"
chk_has "5: ?? docs/verification/README.md" "$out" "?? docs/verification/README.md"
chk_has "5: ?? .claude/settings.json, not the dir" "$out" "?? .claude/settings.json"
chk_no "5: the dir-collapse line never prints" "$out" "?? .claude/ "
C6="$(adopt_clone c6)"; echo x > "$C6/AGENTS.md"; echo x > "$C6/WORKFLOW.md"
out="$("$WRAP" adopt "$C6" 2>&1)"
chk_has "6: both collisions join on ;" \
  "$out" "?? AGENTS.md in the main checkout would block the post-land pull; ?? WORKFLOW.md in the main checkout would block the post-land pull"

echo "=== adopt: sequencer and unmerged states (7, 8, 9) ==="
C7="$(adopt_clone c7)"
git -C "$C7" checkout -qb side
echo side >> "$C7/a.txt"; git -C "$C7" commit -qam side
git -C "$C7" checkout -q main
echo mainline >> "$C7/a.txt"; git -C "$C7" commit -qam mainline
git -C "$C7" merge side >/dev/null 2>&1
out="$("$WRAP" adopt "$C7" 2>&1)"; rc=$?
chk "7: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "7: mid-merge" "$out" "mid-merge"
chk_has "7: unmerged paths" "$out" "unmerged paths: a.txt"

C8="$(adopt_clone c8)"
git -C "$C8" checkout -qb rb-side
echo s1 >> "$C8/a.txt"; git -C "$C8" commit -qam s1
git -C "$C8" checkout -q main
echo m1 >> "$C8/a.txt"; git -C "$C8" commit -qam m1
git -C "$C8" rebase main rb-side >/dev/null 2>&1
out="$("$WRAP" adopt "$C8" 2>&1)"
chk_has "8: mid-rebase" "$out" "mid-rebase"

C9="$(adopt_clone c9)"
echo extra >> "$C9/a.txt"; git -C "$C9" stash push -qm st
echo conflict >> "$C9/a.txt"; git -C "$C9" commit -qam c2
git -C "$C9" stash pop >/dev/null 2>&1
out="$("$WRAP" adopt "$C9" 2>&1)"
chk_has "9: unmerged paths" "$out" "unmerged paths: a.txt"
chk_no "9: no mid- reason" "$out" "mid-"

echo "=== adopt: the chore/kit-adopt shapes (10, 11, 12) ==="
C10="$(adopt_clone c10)"
git -C "$C10" branch chore/kit-adopt
out="$("$WRAP" adopt "$C10" 2>&1)"
chk_has "10: exists locally" "$out" "chore/kit-adopt exists locally"
chk_no "10: no on-origin" "$out" "exists on origin"

C11="$(adopt_clone c11)"
p11="$TMPD/apush-c11"; git clone -q "$TMPD/abare-c11" "$p11"; gitc "$p11"
git -C "$p11" checkout -qb chore/kit-adopt
git -C "$p11" push -q origin chore/kit-adopt
out="$("$WRAP" adopt "$C11" 2>&1)"
chk_has "11: exists on origin" "$out" "chore/kit-adopt exists on origin"
chk_no "11: no local" "$out" "exists locally"

C12="$(adopt_clone c12)"
git -C "$C12" checkout -qb feat/x
out="$("$WRAP" adopt "$C12" 2>&1)"
chk_has "12: off the default branch" "$out" "main checkout is on feat/x, not main"

echo "=== adopt: the PR-template rule (13) and a linked worktree (14) ==="
C13="$(adopt_clone c13)"
mkdir -p "$C13/.github"; echo tpl > "$C13/.github/pull_request_template.md"
git -C "$C13" add -A; git -C "$C13" commit -qm tpl; git -C "$C13" push -q origin main
out="$("$WRAP" adopt "$C13" 2>&1)"; rc=$?
chk "13: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "13: names the template" "$out" ".github/pull_request_template.md exists; pass --body-file"
echo body > "$TMPD/adopt-body.md"
out="$("$WRAP" adopt --body-file "$TMPD/adopt-body.md" "$C13" 2>&1)"; rc=$?
chk "13: --body-file exits 0" "$rc"
chk_has "13: --body-file would adopt" "$out" "would adopt"

C14="$(adopt_clone c14)"
git -C "$C14" worktree add -q -b feat/side "$C14/wt-side" >/dev/null 2>&1
out="$("$WRAP" adopt "$C14/wt-side" 2>&1)"
chk_has "14: not a main checkout" "$out" "not a main checkout"

echo "=== adopt: adopt --dry-run's own refusal passes through (15) ==="
C15="$(adopt_clone c15)"
echo agents > "$C15/AGENTS.md"; echo claude > "$C15/CLAUDE.md"
git -C "$C15" add -A; git -C "$C15" commit -qm both; git -C "$C15" push -q origin main
op15="$TMPD/op-single"; mkdir -p "$op15"; printf '[adopt]\nsingle_source = true\n' > "$op15/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$op15" "$WRAP" adopt "$C15" 2>&1)"; rc=$?
chk "15: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "15: the refusal names adopt --dry-run" "$out" "adopt --dry-run:"
chk_has "15: quotes the merge-by-hand refusal" "$out" "merge them by hand"

echo "=== adopt: a gh not-ok state refuses every repo before any work (16) ==="
C16A="$(adopt_clone c16a)"; C16B="$(adopt_clone c16b)"
out="$(GH_STUB_UNAUTH=1 "$WRAP" adopt "$C16A" "$C16B" 2>&1)"; rc=$?
chk "16: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk "16: both rows refuse" \
  "$([ "$(printf '%s' "$out" | grep -c 'result: - refused: gh is unauthenticated')" -eq 2 ]; echo $?)"
chk "16: no worktree in a" "$([ ! -e "$C16A/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "16: no worktree in b" "$([ ! -e "$C16B/.claude/worktrees/kit-adopt" ]; echo $?)"

echo "=== adopt: --apply lands a clean adoption end to end (17, 18) ==="
C17="$(adopt_clone c17)"
: > "$GH_STUB_CALLS"
out="$(adopt_apply "$C17" "$TMPD/abare-c17")"; rc=$?
chk "17: exits 0" "$rc"
chk_has "17: streams opened PR" "$out" "opened PR #7"
chk_has "17: streams the verified merge" "$out" "merged #7"
chk_has "17: result row names the PR" "$out" "result: #7 adopted"
chk "17: worktree gone" "$([ ! -e "$C17/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "17: branch gone locally" "$(git -C "$C17" show-ref --verify --quiet refs/heads/chore/kit-adopt && echo 1 || echo 0)"
chk "17: branch gone on origin" \
  "$(git -C "$C17" ls-remote --exit-code --heads origin chore/kit-adopt >/dev/null 2>&1; [ $? -eq 2 ]; echo $?)"
chk "17: HEAD equals origin/main" \
  "$([ "$(git -C "$C17" rev-parse HEAD)" = "$(git -C "$C17" rev-parse origin/main)" ]; echo $?)"
bash "$KIT_DIR/lib/adopt.sh" --check "$C17" >/dev/null 2>&1
chk "17: adopt --check exit 0" "$?"
chk "17: merged commit subject" \
  "$([ "$(git -C "$C17" log -1 --format=%s origin/main)" = "chore: adopt the dwarves-kit operate-contract" ]; echo $?)"

OVLOG="$KIT_LEDGER_DIR/proof-overrides.log"
C17P="$(cd "$C17" && pwd -P)"
chk "18: exactly one override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 1 ]; echo $?)"
chk_has "18: names this repo" "$(cat "$OVLOG")" "$C17P"
chk_has "18: the kit-adopt slug" "$(cat "$OVLOG")" "kit-adopt"
chk_has "18: OVERRIDE kind" "$(cat "$OVLOG")" "OVERRIDE"
chk_has "18: the fixed reason" "$(cat "$OVLOG")" "adoption scaffold only"

echo "=== adopt: a driver write outside ADOPT_PATHS fails before commit (19) ==="
adopt_stub "$TMPD/adopt-stub19.sh" 'mkdir -p "$1/src"; echo x > "$1/src/x.sh"'
C19="$(adopt_clone c19)"
: > "$GH_STUB_CALLS"
out="$(WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stub19.sh" \
  adopt_apply "$C19" "$TMPD/abare-c19")"; rc=$?
chk "19: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "19: names the path" "$out" "failed: adoption wrote src/x.sh, outside the scaffold set"
chk_has "19: names the worktree" "$out" "worktree left at"
chk "19: worktree on disk" "$([ -e "$C19/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "19: no commit on the branch" \
  "$([ "$(git -C "$C19" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"
chk "19: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 1 ]; echo $?)"
chk "19: gh log has no create" "$([ -z "$(grep 'pr create' "$GH_STUB_CALLS")" ]; echo $?)"

echo "=== adopt: a driver that writes nothing reports no change (20) ==="
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMPD/adopt-stub20.sh"; chmod +x "$TMPD/adopt-stub20.sh"
C20="$(adopt_clone c20)"
out="$(WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stub20.sh" \
  adopt_apply "$C20" "$TMPD/abare-c20")"; rc=$?
chk "20: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "20: no change row" "$out" "no change: origin/main already carries the adoption; worktree left at"
chk "20: no commit on the branch" \
  "$([ "$(git -C "$C20" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"
chk "20: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 1 ]; echo $?)"

echo "=== adopt: a merge that cannot pull reports merged-not-adopted (21) ==="
C21="$(adopt_clone c21)"
echo local > "$C21/local.txt"; git -C "$C21" add -A; git -C "$C21" commit -qm local
out="$(adopt_apply "$C21" "$TMPD/abare-c21")"; rc=$?
chk "21: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "21: PULL BLOCKED streamed" "$out" "PULL BLOCKED"
chk_has "21: the row names the block" \
  "$out" "merged, not adopted on the main checkout: PULL BLOCKED: pull --ff-only refused"
chk "21: origin carries the merge" \
  "$([ "$(git -C "$C21" log -1 --format=%s origin/main)" = "chore: adopt the dwarves-kit operate-contract" ]; echo $?)"

echo "=== adopt: drift guard, widest write set and single-source (22) ==="
C22A="$(adopt_clone c22a)"
mkdir -p "$C22A/.claude"
printf '%s\n' \
  '{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"bash /opt/mine/hook.sh"},' \
  '{"type":"command","command":"bash $HOME/.claude/dwarves-kit/hooks/old-hook.sh"}]}]},"model":"opus"}' \
  > "$C22A/.claude/settings.json"
printf '[modules]\nboard = true\nsession = true\nadvisor = true\ncosmetic = true\n\n[output]\nstyle = "adhd"\n' \
  > "$C22A/.kit.toml"
git -C "$C22A" add -A; git -C "$C22A" commit -qm cfg; git -C "$C22A" push -q origin main
out="$(adopt_apply "$C22A" "$TMPD/abare-c22a")"; rc=$?
chk "22a: exits 0" "$rc"
chk_has "22a: adopted" "$out" "result: #7 adopted"
chk "22a: style file landed" \
  "$(git -C "$C22A" cat-file -e origin/main:.claude/output-styles/adhd.md 2>/dev/null; echo $?)"
chk "22a: user hook kept" \
  "$(git -C "$C22A" show origin/main:.claude/settings.json | grep -q '/opt/mine/hook.sh'; echo $?)"

C22B="$(adopt_clone c22b)"
echo claude > "$C22B/CLAUDE.md"
git -C "$C22B" add -A; git -C "$C22B" commit -qm claude; git -C "$C22B" push -q origin main
op22="$TMPD/op-singlesrc-22"; mkdir -p "$op22"; printf '[adopt]\nsingle_source = true\n' > "$op22/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$op22" adopt_apply "$C22B" "$TMPD/abare-c22b")"; rc=$?
chk "22b: exits 0" "$rc"
chk_has "22b: adopted" "$out" "result: #7 adopted"
chk "22b: both source files landed" \
  "$(git -C "$C22B" cat-file -e origin/main:AGENTS.md 2>/dev/null && git -C "$C22B" cat-file -e origin/main:CLAUDE.md 2>/dev/null; echo $?)"

echo "=== adopt: usage errors exit 64 (24) ==="
C24="$(adopt_clone c24)"
echo body > "$TMPD/adopt-body-24.md"
out="$("$WRAP" adopt 2>&1)"; rc=$?
chk "24: no repos exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt --force "$C24" 2>&1)"; rc=$?
chk "24: --force exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt --title x "$C24" 2>&1)"; rc=$?
chk "24: --title exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt --body-file 2>&1)"; rc=$?
chk "24: --body-file no value exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt --body-file "$TMPD/no-such-body.md" "$C24" 2>&1)"; rc=$?
chk "24: missing body file exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt --body-file "$TMPD/adopt-body-24.md" "$C24" "$C24" 2>&1)"; rc=$?
chk "24: --body-file plus two repos exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" adopt " --apply" "$C24" 2>&1)"; rc=$?
chk "24: a packed repo argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk "24: nothing written" \
  "$([ ! -e "$C24/.claude/worktrees/kit-adopt" ] && ! git -C "$C24" show-ref --verify --quiet refs/heads/chore/kit-adopt; echo $?)"

echo "=== adopt: a staged non-kit hook entry refuses the settings diff (25) ==="
adopt_stub "$TMPD/adopt-stub25a.sh" \
  'jq ".hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash /tmp/evil.sh\"}]}])" "$1/.claude/settings.json" > "$1/.s.json" && mv "$1/.s.json" "$1/.claude/settings.json"'
adopt_stub "$TMPD/adopt-stub25b.sh" \
  'jq ".hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash $HOME/.claude/dwarves-kit/hooks/x.sh\nbash /tmp/evil.sh\"}]}])" "$1/.claude/settings.json" > "$1/.s.json" && mv "$1/.s.json" "$1/.claude/settings.json"'
adopt_stub "$TMPD/adopt-stub25c.sh" \
  'jq ".hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{\"matcher\":\"Bash\",\"hooks\":[{\"type\":\"command\",\"command\":\"bash $HOME/.claude/dwarves-kit/hooks/x.sh\",\"env\":\"x\"}]}])" "$1/.claude/settings.json" > "$1/.s.json" && mv "$1/.s.json" "$1/.claude/settings.json"'
for v in a b c; do
  C25="$(adopt_clone "c25$v")"
  : > "$GH_STUB_CALLS"
  out="$(WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stub25$v.sh" \
    adopt_apply "$C25" "$TMPD/abare-c25$v")"; rc=$?
  chk "25$v: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
  chk_has "25$v: names event, matcher and index" \
    "$out" "failed: adoption changed .claude/settings.json beyond kit hooks: PreToolUse Bash #"
  chk_no "25$v: never the command text" "$out" "evil.sh"
  chk "25$v: no commit on the branch" \
    "$([ "$(git -C "$C25" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"
  chk "25$v: worktree left" "$([ -e "$C25/.claude/worktrees/kit-adopt" ]; echo $?)"
  chk "25$v: gh log has no create" "$([ -z "$(grep 'pr create' "$GH_STUB_CALLS")" ]; echo $?)"
done
chk "25: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 4 ]; echo $?)"

echo "=== adopt: a staged non-hook settings key refuses (26) ==="
adopt_stub "$TMPD/adopt-stub26.sh" \
  'jq ".permissions.allow = [\"Bash(x)\"]" "$1/.claude/settings.json" > "$1/.s.json" && mv "$1/.s.json" "$1/.claude/settings.json"'
C26="$(adopt_clone c26)"
out="$(WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stub26.sh" \
  adopt_apply "$C26" "$TMPD/abare-c26")"; rc=$?
chk "26: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "26: names the key" "$out" "beyond kit hooks: key permissions"
chk "26: no commit on the branch" \
  "$([ "$(git -C "$C26" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"
chk "26: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 4 ]; echo $?)"

echo "=== adopt: a refused merge leaves a resumable worktree (27) ==="
C27="$(adopt_clone c27)"
WT27="$C27/.claude/worktrees/kit-adopt"
git init -q --bare "$TMPD/throw-27"
out="$(GH_STUB_MERGE_RC=1 GH_STUB_MERGE_ERR='not mergeable' \
  GH_STUB_LAND_REMOTE="$TMPD/throw-27" \
  GH_STUB_PR_7='{"number":7,"headRefOid":"%REMERGE_TIP%","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' \
  adopt_apply "$C27" "$TMPD/abare-c27")"; rc=$?
WT27P="$(cd "$WT27" && pwd -P)"
chk "27: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "27: the row" "$out" "failed: land exit 2: MERGE FAILED #7: exit 1; resume: wrap land $WT27P"
chk "27: worktree kept" "$([ -e "$WT27" ]; echo $?)"
chk "27: branch kept" "$(git -C "$C27" show-ref --verify --quiet refs/heads/chore/kit-adopt; echo $?)"
out="$(GH_STUB_OPEN_HEAD_chore_kit_adopt='[{"number":7,"title":"t","headRefName":"chore/kit-adopt","baseRefName":"main","isDraft":false,"isCrossRepository":false,"author":{"login":"me"}}]' \
  GH_STUB_LAND_REPO="$WT27" GH_STUB_LAND_REMOTE="$TMPD/abare-c27" \
  GH_STUB_LAND_BRANCH=chore/kit-adopt GH_STUB_LAND_DEF=main \
  "$WRAP" land "$WT27" 2>&1)"; rc=$?
chk "27: resume land exits 0" "$rc"
chk_has "27: adopted the open PR" "$out" "adopted PR #7"
chk_has "27: merged verified" "$out" "merged #7"
bash "$KIT_DIR/lib/adopt.sh" --check "$C27" >/dev/null 2>&1
chk "27: adopt --check exit 0" "$?"

echo "=== adopt: single-source adoption lands (28) ==="
C28="$(adopt_clone c28)"
echo claude > "$C28/CLAUDE.md"
git -C "$C28" add -A; git -C "$C28" commit -qm claude; git -C "$C28" push -q origin main
op28="$TMPD/op-singlesrc-28"; mkdir -p "$op28"; printf '[adopt]\nsingle_source = true\n' > "$op28/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$op28" adopt_apply "$C28" "$TMPD/abare-c28")"; rc=$?
chk "28: exits 0" "$rc"
chk_has "28: adopted" "$out" "result: #7 adopted"
chk "28: AGENTS.md and CLAUDE.md both landed" \
  "$(git -C "$C28" cat-file -e origin/main:AGENTS.md 2>/dev/null && git -C "$C28" cat-file -e origin/main:CLAUDE.md 2>/dev/null; echo $?)"

echo "=== adopt: a mismatched merge tree leaves the worktree for reading (29) ==="
C29="$(adopt_clone c29)"
p29="$TMPD/apush-c29"; git clone -q "$TMPD/abare-c29" "$p29"; gitc "$p29"
echo stale > "$p29/stale.txt"; git -C "$p29" add -A; git -C "$p29" commit -qm stale
git -C "$p29" push -q origin main
MM29="$(git -C "$p29" rev-parse HEAD)"
out="$(GH_STUB_VIEW_STATE="{\"state\":\"MERGED\",\"mergeCommit\":{\"oid\":\"$MM29\"}}" \
  adopt_apply "$C29" "$TMPD/abare-c29")"; rc=$?
chk "29: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "29: the row" "$out" "failed: land exit 3: merged #7 ($MM29): TREE MISMATCH"
chk_has "29: worktree named" "$out" "worktree left at"
chk_no "29: no resume" "$out" "resume:"
chk "29: worktree on disk" "$([ -e "$C29/.claude/worktrees/kit-adopt" ]; echo $?)"

echo "=== adopt: a clean leftover prints resume: (30) ==="
C30="$(adopt_leftover 30)"
WT30P="$(cd "$C30/.claude/worktrees/kit-adopt" && pwd -P)"
tip30="$(git -C "$C30" rev-parse chore/kit-adopt)"
out="$("$WRAP" adopt "$C30" 2>&1)"; rc=$?
chk "30: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "30: exists locally" "$out" "chore/kit-adopt exists locally"
chk_has "30: exists on origin" "$out" "chore/kit-adopt exists on origin"
chk_has "30: worktree path exists" "$out" "chore/kit-adopt worktree path exists"
chk_has "30: resume line" "$out" "resume: wrap land $WT30P"
chk "30: nothing written" "$([ "$(git -C "$C30" rev-parse chore/kit-adopt)" = "$tip30" ]; echo $?)"
base30="$(git -C "$C30" rev-parse origin/main)"
out="$(GH_STUB_MERGED_chore_kit_adopt="[{\"number\":3,\"headRefOid\":\"$base30\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]" \
  "$WRAP" adopt "$C30" 2>&1)"
chk_has "30: a stale merged PR still resumes" "$out" "resume: wrap land $WT30P"

echo "=== adopt: a leftover behind a merged PR never prints resume: (31) ==="
C31="$(adopt_leftover 31)"
WT31P="$(cd "$C31/.claude/worktrees/kit-adopt" && pwd -P)"
tip31="$(git -C "$WT31P" rev-parse HEAD)"
out="$(GH_STUB_MERGED_chore_kit_adopt="[{\"number\":7,\"headRefOid\":\"$tip31\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]" \
  "$WRAP" adopt "$C31" 2>&1)"; rc=$?
chk "31: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "31: names the merged PR" "$out" "merged #7; read $WT31P"
chk_no "31: no resume:" "$out" "resume:"
out="$(GH_STUB_MERGED_chore_kit_adopt="[{\"number\":7,\"headRefOid\":\"$tip31\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-01T00:00:00Z\"},{\"number\":8,\"headRefOid\":\"$tip31\",\"baseRefName\":\"main\",\"mergedAt\":\"2026-01-02T00:00:00Z\"}]" \
  "$WRAP" adopt "$C31" 2>&1)"
chk_has "31: every merged PR named" "$out" "merged #7 #8; read $WT31P"

echo "=== adopt: an ignored adoption path refuses (32) ==="
C32A="$(adopt_clone c32a)"
printf '.claude/\n' > "$C32A/.gitignore"
git -C "$C32A" add -A; git -C "$C32A" commit -qm ig; git -C "$C32A" push -q origin main
out="$("$WRAP" adopt "$C32A" 2>&1)"; rc=$?
chk "32a: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "32a: refused" "$out" ".claude/settings.json is gitignored"
out="$("$WRAP" adopt --apply "$C32A" 2>&1)"; rc=$?
chk "32a: --apply exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "32a: --apply refused" "$out" ".claude/settings.json is gitignored"
chk "32a: no worktree" "$([ ! -e "$C32A/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "32a: no branch" "$(git -C "$C32A" show-ref --verify --quiet refs/heads/chore/kit-adopt && echo 1 || echo 0)"

C32B="$(adopt_clone c32b)"
printf '.claude/*\n!.claude/settings.json\n' > "$C32B/.gitignore"
git -C "$C32B" add -A; git -C "$C32B" commit -qm ig; git -C "$C32B" push -q origin main
out="$("$WRAP" adopt "$C32B" 2>&1)"; rc=$?
chk "32b: re-included settings.json passes" "$rc"
chk_has "32b: would adopt" "$out" "would adopt"

C32C="$(adopt_clone c32c)"
printf '.claude/*\n!.claude/settings.json\n' > "$C32C/.gitignore"
git -C "$C32C" add -A; git -C "$C32C" commit -qm ig; git -C "$C32C" push -q origin main
op32="$TMPD/op-style"; mkdir -p "$op32"; printf '[output]\nstyle = "x"\n' > "$op32/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$op32" "$WRAP" adopt "$C32C" 2>&1)"; rc=$?
chk "32c: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "32c: the ignored style file refuses" "$out" ".claude/output-styles/x.md is gitignored"

echo "=== adopt: a commit hook that adds files fails the commit recheck (33) ==="
C33="$(adopt_clone c33)"
mkdir -p "$C33/.git/hooks"
cat > "$C33/.git/hooks/pre-commit" <<'EOF'
#!/bin/sh
mkdir -p src && echo hooked > src/hooked.txt && git add src/hooked.txt
EOF
chmod +x "$C33/.git/hooks/pre-commit"
: > "$GH_STUB_CALLS"
out="$(adopt_apply "$C33" "$TMPD/abare-c33")"; rc=$?
chk "33: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "33: names the hook-written path" \
  "$out" "failed: the commit differs from the guarded set: src/hooked.txt"
chk "33: the commit exists with the hooked file" \
  "$(git -C "$C33" cat-file -e chore/kit-adopt:src/hooked.txt 2>/dev/null; echo $?)"
chk "33: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 7 ]; echo $?)"
chk "33: gh log has no create" "$([ -z "$(grep 'pr create' "$GH_STUB_CALLS")" ]; echo $?)"
chk "33: worktree left" "$([ -e "$C33/.claude/worktrees/kit-adopt" ]; echo $?)"

echo "=== adopt: a CONFLICTING merge quotes land's wrap-merge advice (35) ==="
C35="$(adopt_clone c35)"
git init -q --bare "$TMPD/throw-35"
out="$(GH_STUB_MERGE_RC=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_LAND_REMOTE="$TMPD/throw-35" \
  GH_STUB_PR_7='{"number":7,"headRefOid":"%REMERGE_TIP%","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","statusCheckRollup":[]}' \
  adopt_apply "$C35" "$TMPD/abare-c35")"; rc=$?
chk "35: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "35: quotes the wrap-merge line" \
  "$out" "failed: land exit 2: chore/kit-adopt already contains origin/main; GitHub's conflict is the union-blind case, run wrap merge --apply --pr 7"
chk_no "35: no resume" "$out" "resume:"

echo "=== adopt: a foreign output-style file refuses the path guard (36) ==="
adopt_stub "$TMPD/adopt-stub36.sh" \
  'mkdir -p "$1/.claude/output-styles"; echo y > "$1/.claude/output-styles/y.md"'
C36="$(adopt_clone c36)"
op36="$TMPD/op-style-36"; mkdir -p "$op36"; printf '[output]\nstyle = "x"\n' > "$op36/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$op36" WRAP_ADOPT_TEST=1 WRAP_ADOPT_SH="$TMPD/adopt-stub36.sh" \
  adopt_apply "$C36" "$TMPD/abare-c36")"; rc=$?
chk "36: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "36: names the foreign file" \
  "$out" "failed: adoption wrote .claude/output-styles/y.md, outside the scaffold set"
chk "36: no commit on the branch" \
  "$([ "$(git -C "$C36" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"

echo "=== adopt: a hook-contaminated leftover prints read: (37) ==="
WT33P="$(cd "$C33/.claude/worktrees/kit-adopt" && pwd -P)"
tip37="$(git -C "$C33" rev-parse chore/kit-adopt)"
out="$("$WRAP" adopt "$C33" 2>&1)"; rc=$?
chk "37: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "37: refused" "$out" "refused:"
chk_has "37: exists locally" "$out" "chore/kit-adopt exists locally"
chk_has "37: read row" "$out" "read $WT33P"
chk_no "37: no resume" "$out" "resume:"
chk "37: nothing written" "$([ "$(git -C "$C33" rev-parse chore/kit-adopt)" = "$tip37" ]; echo $?)"

echo "=== adopt: an ignored .claude on fresh origin refuses the apply (38) ==="
C38="$(adopt_clone c38)"
p38="$TMPD/apush-c38"; git clone -q "$TMPD/abare-c38" "$p38"; gitc "$p38"
printf '.claude/\n' > "$p38/.gitignore"
git -C "$p38" add -A; git -C "$p38" commit -qm ig; git -C "$p38" push -q origin main
out="$(adopt_apply "$C38" "$TMPD/abare-c38")"; rc=$?
chk "38: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "38: names the ignored path" "$out" "is gitignored in origin/main"
chk "38: no commit on the branch" \
  "$([ "$(git -C "$C38" rev-list --count origin/main..chore/kit-adopt)" = 0 ]; echo $?)"
chk "38: no new override line" "$([ "$(wc -l < "$OVLOG" | tr -d ' ')" = 8 ]; echo $?)"
chk "38: worktree left" "$([ -e "$C38/.claude/worktrees/kit-adopt" ]; echo $?)"

echo "=== adopt: an unreadable PR state refuses the leftover (39) ==="
C39="$(adopt_leftover 39)"
WT39P="$(cd "$C39/.claude/worktrees/kit-adopt" && pwd -P)"
out="$(GH_STUB_MERGED_HEAD_RC=1 "$WRAP" adopt "$C39" 2>&1)"
chk_has "39: non-zero gh read is unreadable" "$out" "PR state unreadable; read $WT39P"
chk_no "39: no resume:" "$out" "resume:"
out="$(GH_STUB_MERGED_chore_kit_adopt='not json' "$WRAP" adopt "$C39" 2>&1)"
chk_has "39: unparseable JSON is unreadable" "$out" "PR state unreadable; read $WT39P"
chk_no "39: still no resume:" "$out" "resume:"

echo "=== adopt: a batch runs in argument order and ends with the summary (23) ==="
C23A="$(adopt_clone c23a)"; echo x > "$C23A/AGENTS.md"
C23B="$(adopt_clone c23b)"
C23C="$(adopt_clone c23c)"
bash "$KIT_DIR/lib/adopt.sh" "$C23C" >/dev/null 2>&1
git -C "$C23C" add -A; git -C "$C23C" commit -qm adopt; git -C "$C23C" push -q origin main
# adopt_apply puts its own clone last, so B's land wiring rides the overrides and
# the call reads `adopt --apply A B C`.
out="$(GH_STUB_LAND_REPO="$C23B/.claude/worktrees/kit-adopt" GH_STUB_LAND_REMOTE="$TMPD/abare-c23b" \
  adopt_apply "$C23C" "$TMPD/abare-c23c" "$C23A" "$C23B")"; rc=$?
chk "23: exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk "23: repos run in argument order" "$(printf '%s\n' "$out" | grep '^== ' | sed 's/^== //' \
  | diff -q - <(printf '%s\n' "$(cd "$C23A" && pwd -P)" "$(cd "$C23B" && pwd -P)" "$(cd "$C23C" && pwd -P)") >/dev/null; echo $?)"
sum23="$(printf '%s\n' "$out" | sed -n '/^ADOPT SUMMARY$/,$p')"
chk "23: summary rows in order" "$(printf '%s\n' "$sum23" | sed 1d | tr -s ' ' | diff -q - <(printf '%s\n' \
  ' aclone-c23a - refused: ?? AGENTS.md in the main checkout would block the post-land pull' \
  ' aclone-c23b #7 adopted' ' aclone-c23c - skip: already adopted') >/dev/null; echo $?)"
chk "23: B adopted on origin" \
  "$([ "$(git -C "$C23B" log -1 --format=%s origin/main)" = "chore: adopt the dwarves-kit operate-contract" ]; echo $?)"

# adopt_kill_gh -- a gh in front of the stub whose first `pr merge` raises
# $ADOPT_KILL_SIG instead of merging: mode `sub` signals land's pipeline
# subshell and itself, never the verb; mode `pg` signals its whole process group.
KILLBIN="$TMPD/killbin"; mkdir -p "$KILLBIN"
cat > "$KILLBIN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-} ${2:-}" = "pr merge" ] && [ ! -e "$ADOPT_KILL_ONCE" ]; then
  : > "$ADOPT_KILL_ONCE"
  if [ "$ADOPT_KILL_MODE" = pg ]; then
    kill "-$ADOPT_KILL_SIG" -- "-$(ps -o pgid= -p $$ | tr -d ' ')"
  else
    # Every forked `wrap.sh adopt` ancestor below the topmost one (the verb):
    # land's pipeline subshell and the $(gh ...) subshell between it and us.
    chain=""; p=$PPID
    while [ "${p:-1}" -gt 1 ]; do
      case "$(ps -o args= -p "$p")" in *"wrap.sh adopt"*) chain="$chain $p" ;; *) break ;; esac
      p="$(ps -o ppid= -p "$p" | tr -d ' ')"
    done
    set -- $chain
    while [ $# -gt 1 ]; do kill "-$ADOPT_KILL_SIG" "$1"; shift; done
    kill "-$ADOPT_KILL_SIG" $$
  fi
  sleep 5; exit 1
fi
exec "$(dirname "$0")/../stub/gh" "$@"
EOF
chmod +x "$KILLBIN/gh"

# adopt_kill <mode> <sig> <tag> -- batch [A, B] (two case-17 fixtures) under the
# killing gh. `pg` runs the verb as a set -m job, its own process group, so the
# signal never reaches this runner. Sets KA, KB, KOUT, KRC.
adopt_kill() {
  local mode="$1" sig="$2" t="$3"
  KA="$(adopt_clone "k${t}a")"; KB="$(adopt_clone "k${t}b")"
  set -- env PATH="$KILLBIN:$PATH" ADOPT_KILL_MODE="$mode" ADOPT_KILL_SIG="$sig" \
    ADOPT_KILL_ONCE="$TMPD/kill-$t.once" GH_STUB_OPEN_HEAD_chore_kit_adopt='[]' GH_STUB_CREATE_NUM=7 \
    GH_STUB_LAND_REPO="$KA/.claude/worktrees/kit-adopt" GH_STUB_LAND_REMOTE="$TMPD/abare-k${t}a" \
    GH_STUB_LAND_BRANCH=chore/kit-adopt GH_STUB_LAND_DEF=main "$WRAP" adopt --apply "$KA" "$KB"
  if [ "$mode" = pg ]; then
    set -m
    "$@" > "$TMPD/kill-$t.out" 2>&1 &
    wait $!; KRC=$?
    set +m
    KOUT="$(cat "$TMPD/kill-$t.out")"
  else
    KOUT="$("$@" 2>&1)"; KRC=$?
  fi
}

# adopt_kill_chk <tag> <A's row> -- the assertions 34a and 34b share.
adopt_kill_chk() {
  local t="$1" row="$2" wta sum
  wta="$(cd "$KA/.claude/worktrees/kit-adopt" 2>/dev/null && pwd -P)"
  sum="$(printf '%s\n' "$KOUT" | sed -n '/^ADOPT SUMMARY$/,$p' | tr -s ' ')"
  chk "$t: exits 1" "$([ "$KRC" -eq 1 ]; echo $?)"
  chk_has "$t: A's result line" "$(printf '%s\n' "$KOUT" | grep 'result:')" "${row}; read ${wta}"
  chk_has "$t: summary carries A's row" "$sum" "${row}; read ${wta}"
  chk_has "$t: summary carries B's not run" "$sum" "$(basename "$KB") - not run"
  chk "$t: B has no worktree" "$([ ! -e "$KB/.claude/worktrees/kit-adopt" ]; echo $?)"
  chk "$t: B has no branch" "$(git -C "$KB" show-ref --verify --quiet refs/heads/chore/kit-adopt && echo 1 || echo 0)"
}

echo "=== adopt: a signal to land's subshell stops the batch via R8 (34a) ==="
adopt_kill sub INT 34ai;  adopt_kill_chk 34a-INT  "interrupted: land exit 130"
adopt_kill sub TERM 34at; adopt_kill_chk 34a-TERM "interrupted: land exit 143"

echo "=== adopt: a signal to the verb's process group hits the trap (34b) ==="
adopt_kill pg INT 34bi;  adopt_kill_chk 34b-INT  "interrupted: INT"
adopt_kill pg TERM 34bt; adopt_kill_chk 34b-TERM "interrupted: TERM"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-adopt: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-adopt: all $PASS passed"
