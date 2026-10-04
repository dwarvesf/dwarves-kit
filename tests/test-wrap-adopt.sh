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
  "$([ "$(printf '%s' "$out" | grep -c 'refused: gh is unauthenticated')" -eq 2 ]; echo $?)"
chk "16: no worktree in a" "$([ ! -e "$C16A/.claude/worktrees/kit-adopt" ]; echo $?)"
chk "16: no worktree in b" "$([ ! -e "$C16B/.claude/worktrees/kit-adopt" ]; echo $?)"

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

echo "=== adopt: an unreadable PR state refuses the leftover (39) ==="
C39="$(adopt_leftover 39)"
WT39P="$(cd "$C39/.claude/worktrees/kit-adopt" && pwd -P)"
out="$(GH_STUB_MERGED_HEAD_RC=1 "$WRAP" adopt "$C39" 2>&1)"
chk_has "39: non-zero gh read is unreadable" "$out" "PR state unreadable; read $WT39P"
chk_no "39: no resume:" "$out" "resume:"
out="$(GH_STUB_MERGED_chore_kit_adopt='not json' "$WRAP" adopt "$C39" 2>&1)"
chk_has "39: unparseable JSON is unreadable" "$out" "PR state unreadable; read $WT39P"
chk_no "39: still no resume:" "$out" "resume:"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-adopt: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-adopt: all $PASS passed"
