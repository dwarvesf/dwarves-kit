#!/usr/bin/env bash
# test-wrap-carry.sh -- the carry cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== apply: stray lines in a dirty union-marked file are carried onto a branch ==="
# ===========================================================================
# A session wrote two lines into the shared main checkout and never committed them. The dry
# run names them; --apply carries them to a new branch on origin and leaves the checkout alone.
build_union_repo stray
SC="$TMPD/uclone-stray"; SB="$TMPD/ubare-stray"
printf '%s' "$LAB_STRAY" > "$SC/_meta/LAB_LOG.md"
SC_BEFORE="$(cksum < "$SC/_meta/LAB_LOG.md")"
stray_branches() { git -C "$SB" for-each-ref --format='%(refname:short)' 'refs/heads/wrap/stray-*'; }
out="$("$WRAP" apply "$SC" 2>&1)"; rc=$?
chk "stray dry-run: apply exits 0" "$rc"
chk_has "stray dry-run: names the two lines" "$out" "WOULD carry 2 stray lines in _meta/LAB_LOG.md onto a branch"
chk "stray dry-run: no branch reached origin" "$([ -z "$(stray_branches)" ]; echo $?)"
out="$(KIT_CONFIG_OPERATOR="$TMPD/stray-off" "$WRAP" apply "$SC" 2>&1)" # no kit.toml there: default
chk_has "stray dry-run: the knob defaults to true" "$out" "WOULD carry 2 stray lines"
mkdir -p "$TMPD/stray-off"; printf '[wrap]\ncarry_stray_lines = false\n' > "$TMPD/stray-off/kit.toml"
out="$(KIT_CONFIG_OPERATOR="$TMPD/stray-off" "$WRAP" apply --apply "$SC" 2>&1)"
chk_has "stray knob off: reports and carries nothing" "$out" \
  "2 stray lines in _meta/LAB_LOG.md stay in the working copy (wrap.carry_stray_lines=false)"
chk "stray knob off: no branch reached origin" "$([ -z "$(stray_branches)" ]; echo $?)"
out="$("$WRAP" apply --apply "$SC" 2>&1)"; rc=$?
SBR="$(stray_branches)"
chk "stray --apply: apply exits 0" "$rc"
chk "stray --apply: exactly one wrap/stray branch on origin" "$([ "$(printf '%s' "$SBR" | grep -c .)" = 1 ]; echo $?)"
chk "stray --apply: the branch name carries the file slug and a stamp" \
  "$(printf '%s' "$SBR" | grep -qE '^wrap/stray-meta-lab-log-md-[0-9]{8}-[0-9]{4}$'; echo $?)"
chk_has "stray --apply: the carry is reported" "$out" "carried 2 stray lines in _meta/LAB_LOG.md to origin/${SBR}"
chk_has "stray --apply: the PR command is named, not run" "$out" "gh pr create --head ${SBR}"
SB_FILE="$(git -C "$SB" show "${SBR}:_meta/LAB_LOG.md")"
chk "stray --apply: the branch file is origin's plus the two lines below the anchor" \
  "$([ "$SB_FILE" = "${LAB_STRAY%$'\n'}" ]; echo $?)"
chk "stray --apply: the branch sits one commit on origin/main" \
  "$([ "$(git -C "$SB" rev-parse "${SBR}^")" = "$(git -C "$SB" rev-parse main)" ]; echo $?)"
chk "stray --apply: the commit subject names the file" \
  "$([ "$(git -C "$SB" log -1 --format=%s "$SBR")" = "chore(LAB_LOG): carry 2 stray lines from a shared checkout" ]; echo $?)"
chk "stray --apply: the checkout's file is byte-identical" \
  "$([ "$SC_BEFORE" = "$(cksum < "$SC/_meta/LAB_LOG.md")" ]; echo $?)"
chk "stray --apply: the checkout stays on main" "$([ "$(git -C "$SC" branch --show-current)" = main ]; echo $?)"
chk "stray --apply: the scratch worktree is gone" "$([ "$(git -C "$SC" worktree list | grep -c .)" = 1 ]; echo $?)"
out="$("$WRAP" apply --apply "$SC" 2>&1)"
chk_has "stray rerun: an existing carry branch skips the file" "$out" \
  "SKIP _meta/LAB_LOG.md: 2 stray lines, but an origin wrap/stray-meta-lab-log-md-* branch already carries this file"
chk "stray rerun: still one branch on origin" "$([ "$(stray_branches | grep -c .)" = 1 ]; echo $?)"

echo "--- stray lines: a main checkout sitting on a feature branch reports and carries"
# The incident state. A line the feature branch COMMITTED rides that branch's own PR, so only
# the two lines no commit holds are stray.
build_union_repo strayfeat
SF="$TMPD/uclone-strayfeat"; SFB="$TMPD/ubare-strayfeat"
git -C "$SF" checkout -q -b feat/other
LAB_FEAT=$'# Lab log\n\n---\n\n2026-09-06 · feat: committed on the branch\n2026-09-01 · base: the first line\n'
printf '%s' "$LAB_FEAT" > "$SF/_meta/LAB_LOG.md"; git -C "$SF" commit -qam "feat line"
printf '%s' $'# Lab log\n\n---\n\n2026-09-08 · stray: board set on the shared checkout\n2026-09-07 · stray: wrap log on the shared checkout\n2026-09-06 · feat: committed on the branch\n2026-09-01 · base: the first line\n' \
  > "$SF/_meta/LAB_LOG.md"
out="$("$WRAP" apply "$SF" 2>&1)"
chk_has "stray on a feature branch: the dry run names the two lines" "$out" \
  "WOULD carry 2 stray lines in _meta/LAB_LOG.md onto a branch"
out="$("$WRAP" apply --apply "$SF" 2>&1)"; rc=$?
SFR="$(git -C "$SFB" for-each-ref --format='%(refname:short)' 'refs/heads/wrap/stray-*')"
chk "stray on a feature branch: apply exits 0" "$rc"
chk_has "stray on a feature branch: the carry is reported" "$out" "carried 2 stray lines in _meta/LAB_LOG.md to origin/${SFR}"
chk "stray on a feature branch: the branch holds origin's file plus the two stray lines" \
  "$([ "$(git -C "$SFB" show "${SFR}:_meta/LAB_LOG.md")" = $'# Lab log\n\n---\n\n2026-09-08 · stray: board set on the shared checkout\n2026-09-07 · stray: wrap log on the shared checkout\n2026-09-01 · base: the first line' ]; echo $?)"
chk "stray on a feature branch: the checkout stays on its branch" \
  "$([ "$(git -C "$SF" branch --show-current)" = feat/other ]; echo $?)"

echo "--- stray lines: a flipped board row lands once, in place, with its new status"
# claimed -> shipped is the case `dedupe-all` alone gets wrong: both copies are non-queued,
# and the stale one comes first once the stray row is appended.
BW="$TMPD/bwork-stray"; BC="$TMPD/bclone-stray"; BB="$TMPD/bbare-stray"
mkdir -p "$BW/_meta"; git -C "$BW" init -q; gitc "$BW"; git -C "$BW" symbolic-ref HEAD refs/heads/main
printf '_meta/BACKLOG.md merge=union\n' > "$BW/.gitattributes"
BOARD_HEAD=$'# Board\n\n| ID | Title | Status |\n|---|---|---|\n'
printf '%s' "${BOARD_HEAD}"$'| OPS-1 | first | claimed |\n| OPS-2 | second | queued |\n' > "$BW/_meta/BACKLOG.md"
git -C "$BW" add -A; git -C "$BW" commit -qm base
git clone -q --bare "$BW" "$BB"; git clone -q "$BB" "$BC"; gitc "$BC"
git -C "$BC" remote set-head origin main >/dev/null 2>&1
printf '%s' "${BOARD_HEAD}"$'| OPS-1 | first | shipped (#12) |\n| OPS-2 | second | queued |\n| OPS-3 | third | queued |\n' > "$BC/_meta/BACKLOG.md"
out="$("$WRAP" apply --apply "$BC" 2>&1)"; rc=$?
BR="$(git -C "$BB" for-each-ref --format='%(refname:short)' 'refs/heads/wrap/stray-*')"
BFILE="$(git -C "$BB" show "${BR}:_meta/BACKLOG.md" 2>/dev/null)"
chk "board stray: apply exits 0" "$rc"
chk_has "board stray: both stray rows are counted" "$out" "carried 2 stray lines in _meta/BACKLOG.md to origin/${BR}"
chk "board stray: OPS-1 appears once" "$([ "$(printf '%s\n' "$BFILE" | grep -c '^| OPS-1 |')" = 1 ]; echo $?)"
chk "board stray: the carry branch holds the flipped row in place, the new row at the end" \
  "$([ "$BFILE" = "${BOARD_HEAD}"$'| OPS-1 | first | shipped (#12) |\n| OPS-2 | second | queued |\n| OPS-3 | third | queued |' ]; echo $?)"

# ===========================================================================
echo "=== apply: stray commits on the default branch are carried onto a branch ==="
# ===========================================================================
# A session committed on the shared checkout's main and never pushed, so every later
# `pull --ff-only` refused as diverging. Origin moved the union-marked log too, and the log
# is dirty here: a move straight to origin/main would trip `reset --keep` on that file.
build_union_repo scommit; advance_union_repo scommit
SCC="$TMPD/uclone-scommit"; SCB="$TMPD/ubare-scommit"
printf 'a note\n' > "$SCC/notes.md"; git -C "$SCC" add notes.md; git -C "$SCC" commit -qm "docs: a stray note"
SCC_STRAY="$(git -C "$SCC" rev-parse HEAD)"; SCC_SHORT="$(git -C "$SCC" rev-parse --short HEAD)"
printf '%s' "$LAB_LOCAL" > "$SCC/_meta/LAB_LOG.md"
commit_branches() { git -C "$1" for-each-ref --format='%(refname:short)' 'refs/heads/wrap/stray-commits-*'; }
out="$("$WRAP" apply "$SCC" 2>&1)"; rc=$?
chk "stray commits dry-run: apply exits 0" "$rc"
chk_has "stray commits dry-run: names the count" "$out" "WOULD carry 1 stray commits on main onto a branch:"
chk_has "stray commits dry-run: names the sha and subject" "$out" "       ${SCC_SHORT} docs: a stray note"
chk_has "stray commits dry-run: names the move" "$out" "WOULD move main back to origin/main"
chk "stray commits dry-run: no branch reached origin" "$([ -z "$(commit_branches "$SCB")" ]; echo $?)"
chk "stray commits dry-run: main did not move" "$([ "$(git -C "$SCC" rev-parse HEAD)" = "$SCC_STRAY" ]; echo $?)"
out="$("$WRAP" apply --apply "$SCC" 2>&1)"; rc=$?
SCR="$(commit_branches "$SCB")"
chk "stray commits --apply: apply exits 0" "$rc"
chk "stray commits --apply: the branch name carries a stamp" \
  "$(printf '%s' "$SCR" | grep -qE '^wrap/stray-commits-[0-9]{8}-[0-9]{4}$'; echo $?)"
chk "stray commits --apply: the origin branch sits on the stray commit" \
  "$([ "$(git -C "$SCB" rev-parse "$SCR" 2>/dev/null)" = "$SCC_STRAY" ]; echo $?)"
chk "stray commits --apply: a local branch of the same name keeps it" \
  "$([ "$(git -C "$SCC" rev-parse "refs/heads/${SCR}" 2>/dev/null)" = "$SCC_STRAY" ]; echo $?)"
chk_has "stray commits --apply: the carry is reported" "$out" "carried 1 stray commits on main to origin/${SCR}"
chk_has "stray commits --apply: the PR command is named, not run" "$out" "gh pr create --head ${SCR}"
chk_has "stray commits --apply: the move is reported" "$out" "where it left origin/main; the 1 commits live on ${SCR}"
chk_no "stray commits --apply: the pull did not fail" "$out" "FAILED"
chk "stray commits --apply: main fast-forwarded onto origin/main" \
  "$([ "$(git -C "$SCC" rev-parse HEAD)" = "$(git -C "$SCB" rev-parse main)" ]; echo $?)"
chk "stray commits --apply: the committed file left the working tree with its commit" \
  "$([ ! -e "$SCC/notes.md" ]; echo $?)"
chk "stray commits --apply: the dirty union line survived" \
  "$(grep -qF 'local: the other session line' "$SCC/_meta/LAB_LOG.md"; echo $?)"
out="$("$WRAP" apply "$SCC" 2>&1)"
chk_has "stray commits rerun: nothing left ahead" "$(printf '%s' "$out" | grep -A1 -- '-- stray commits:')" "none"

echo "--- stray commits: origin unmoved, the move lands on origin/main itself"
build_union_repo scsame
SCS="$TMPD/uclone-scsame"; SCSB="$TMPD/ubare-scsame"
printf 'a note\n' > "$SCS/notes.md"; git -C "$SCS" add notes.md; git -C "$SCS" commit -qm "docs: a stray note"
out="$("$WRAP" apply --apply "$SCS" 2>&1)"; rc=$?
SCSR="$(commit_branches "$SCSB")"
chk "stray commits, origin unmoved: apply exits 0" "$rc"
chk_has "stray commits, origin unmoved: the brief's move line" "$out" \
  "moved main back to origin/main; the 1 commits live on ${SCSR}"
chk "stray commits, origin unmoved: main is origin/main" \
  "$([ "$(git -C "$SCS" rev-parse HEAD)" = "$(git -C "$SCSB" rev-parse main)" ]; echo $?)"

echo "--- stray commits: a dirty non-union file keeps main ahead, the branch still goes"
build_union_repo scdirty
SCD="$TMPD/uclone-scdirty"; SCDB="$TMPD/ubare-scdirty"
printf 'a note\n' > "$SCD/notes.md"; git -C "$SCD" add notes.md; git -C "$SCD" commit -qm "docs: a stray note"
SCD_STRAY="$(git -C "$SCD" rev-parse HEAD)"
printf 'readme local\n' > "$SCD/README.md"
out="$("$WRAP" apply "$SCD" 2>&1)"
chk_has "stray commits dirty dry-run: names the block" "$out" \
  "main would stay ahead: dirty tracked files block the move: README.md"
out="$("$WRAP" apply --apply "$SCD" 2>&1)"
SCDR="$(commit_branches "$SCDB")"
chk "stray commits dirty: the branch reached origin" \
  "$([ "$(git -C "$SCDB" rev-parse "$SCDR" 2>/dev/null)" = "$SCD_STRAY" ]; echo $?)"
chk_has "stray commits dirty: the block is reported" "$out" \
  "main left ahead: dirty tracked files block the move: README.md"
chk "stray commits dirty: main did not move" "$([ "$(git -C "$SCD" rev-parse HEAD)" = "$SCD_STRAY" ]; echo $?)"
chk "stray commits dirty: the dirty file is untouched" \
  "$([ "$(cat "$SCD/README.md")" = "readme local" ]; echo $?)"
git -C "$SCD" checkout -q -- README.md
git -C "$SCD" branch -q -D "$SCDR"
# A branch outside wrap/ whose name ENDS like a carry branch is someone else's, never reused.
git -C "$SCD" push -q origin "${SCD_STRAY}:refs/heads/foo/wrap/stray-commits-x"
out="$("$WRAP" apply --apply "$SCD" 2>&1)"
chk_has "stray commits rerun: the existing origin branch is reused" "$out" \
  "origin/${SCDR} already carries the 1 stray commits on main"
chk_has "stray commits rerun: the PR command prints on reuse too" "$out" "gh pr create --head ${SCDR}"
chk "stray commits rerun: the local branch is back" \
  "$([ "$(git -C "$SCD" rev-parse "refs/heads/${SCDR}" 2>/dev/null)" = "$SCD_STRAY" ]; echo $?)"
chk_no "stray commits rerun: a suffix-matching foreign branch is not adopted" "$out" "foo/wrap/stray-commits-x"
chk "stray commits rerun: still one branch on origin" "$([ "$(commit_branches "$SCDB" | grep -c .)" = 1 ]; echo $?)"
chk "stray commits rerun: main moved once the tree was clean" \
  "$([ "$(git -C "$SCD" rev-parse HEAD)" = "$(git -C "$SCDB" rev-parse main)" ]; echo $?)"

echo "--- stray commits: a dirty union file the commits change stays for git to refuse"
build_union_repo scunion
SCU="$TMPD/uclone-scunion"
printf '%s' "$LAB_LOCAL" > "$SCU/_meta/LAB_LOG.md"; git -C "$SCU" commit -qam "chore: a stray log line"
SCU_STRAY="$(git -C "$SCU" rev-parse HEAD)"
printf '%s' $'# Lab log\n\n---\n\n2026-09-04 · local: uncommitted\n2026-09-03 · local: the other session line\n2026-09-01 · base: the first line\n' > "$SCU/_meta/LAB_LOG.md"
SCU_BEFORE="$(cksum < "$SCU/_meta/LAB_LOG.md")"
out="$("$WRAP" apply "$SCU" 2>&1)"
chk_has "stray commits union overlap: the dry run predicts the block" "$out" \
  "main would stay ahead: dirty files the stray commits change block the move: _meta/LAB_LOG.md"
out="$("$WRAP" apply --apply "$SCU" 2>&1)"
chk_has "stray commits union overlap: the block is reported" "$out" \
  "main left ahead: dirty files the stray commits change block the move: _meta/LAB_LOG.md"
chk "stray commits union overlap: main did not move" "$([ "$(git -C "$SCU" rev-parse HEAD)" = "$SCU_STRAY" ]; echo $?)"
chk "stray commits union overlap: the working copy is byte-identical" \
  "$([ "$SCU_BEFORE" = "$(cksum < "$SCU/_meta/LAB_LOG.md")" ]; echo $?)"

echo "--- stray commits: a staged union file blocks the move (the pull skips its carry then)"
build_union_repo scstaged
SCT="$TMPD/uclone-scstaged"
printf 'a note\n' > "$SCT/notes.md"; git -C "$SCT" add notes.md; git -C "$SCT" commit -qm "docs: a stray note"
SCT_STRAY="$(git -C "$SCT" rev-parse HEAD)"
printf '%s' "$LAB_LOCAL" > "$SCT/_meta/LAB_LOG.md"; git -C "$SCT" add _meta/LAB_LOG.md
out="$("$WRAP" apply --apply "$SCT" 2>&1)"
chk_has "stray commits staged: the block is reported" "$out" \
  "main left ahead: dirty tracked files block the move: _meta/LAB_LOG.md"
chk "stray commits staged: main did not move" "$([ "$(git -C "$SCT" rev-parse HEAD)" = "$SCT_STRAY" ]; echo $?)"

echo "--- stray commits: a carry PR that squash-merged is not pushed again"
# Run 1 pushed and a dirty file blocked the move. The PR then squash-merged and the sweeps
# deleted the carry branch, local and origin. Run 2 finds the change on origin by patch id.
build_union_repo scsquash
SCQ="$TMPD/uclone-scsquash"; SCQB="$TMPD/ubare-scsquash"
printf 'a note\n' > "$SCQ/notes.md"; git -C "$SCQ" add notes.md; git -C "$SCQ" commit -qm "docs: a stray note"
printf 'more\n' >> "$SCQ/notes.md"; git -C "$SCQ" commit -qam "docs: more of the note"
SQP="$TMPD/upush-scsquash"; git clone -q "$SCQB" "$SQP"; gitc "$SQP"
git -C "$SCQ" diff HEAD~2 HEAD | git -C "$SQP" apply --index
git -C "$SQP" commit -qm "docs: a stray note (#9)"
git -C "$SCQB" fetch -q "$SQP" main:main
out="$("$WRAP" apply "$SCQ" 2>&1)"
chk_has "stray commits squashed dry-run: names the landed commit" "$out" \
  "the 2 stray commits on main already landed on origin/main as $(git -C "$SCQB" rev-parse --short main); nothing to carry"
out="$("$WRAP" apply --apply "$SCQ" 2>&1)"; rc=$?
chk "stray commits squashed: apply exits 0" "$rc"
chk "stray commits squashed: no carry branch was pushed" "$([ -z "$(commit_branches "$SCQB")" ]; echo $?)"
chk_has "stray commits squashed: the move names where the change lives" "$out" \
  "the 2 commits live on origin/main as $(git -C "$SCQB" rev-parse --short main)"
chk "stray commits squashed: main is origin/main" \
  "$([ "$(git -C "$SCQ" rev-parse HEAD)" = "$(git -C "$SCQB" rev-parse main)" ]; echo $?)"

echo "--- stray commits: the knob false carries nothing"
build_union_repo scoff
SCO="$TMPD/uclone-scoff"; SCOB="$TMPD/ubare-scoff"
printf 'a note\n' > "$SCO/notes.md"; git -C "$SCO" add notes.md; git -C "$SCO" commit -qm "docs: a stray note"
SCO_STRAY="$(git -C "$SCO" rev-parse HEAD)"
out="$(KIT_CONFIG_OPERATOR="$TMPD/stray-off" "$WRAP" apply --apply "$SCO" 2>&1)"
chk_has "stray commits knob off: reports the count" "$out" \
  "1 stray commits on main stay local (wrap.carry_stray_lines=false)"
chk "stray commits knob off: no branch reached origin" "$([ -z "$(commit_branches "$SCOB")" ]; echo $?)"
chk "stray commits knob off: no local carry branch" "$([ -z "$(commit_branches "$SCO")" ]; echo $?)"
chk "stray commits knob off: main did not move" "$([ "$(git -C "$SCO" rev-parse HEAD)" = "$SCO_STRAY" ]; echo $?)"

echo "--- stray commits: a refused push is FAILED and the pull still runs"
build_union_repo screfuse
SCF="$TMPD/uclone-screfuse"; SCFB="$TMPD/ubare-screfuse"
mkdir -p "$SCFB/hooks"; printf '#!/bin/sh\nexit 1\n' > "$SCFB/hooks/pre-receive"; chmod +x "$SCFB/hooks/pre-receive"
printf 'a note\n' > "$SCF/notes.md"; git -C "$SCF" add notes.md; git -C "$SCF" commit -qm "docs: a stray note"
SCF_STRAY="$(git -C "$SCF" rev-parse HEAD)"
out="$("$WRAP" apply --apply "$SCF" 2>&1)"; rc=$?
chk "stray commits refused push: apply exits 2" "$([ "$rc" = 2 ]; echo $?)"
chk_has "stray commits refused push: FAILED names the branch" "$out" "FAILED carry 1 stray commits on main to wrap/stray-commits-"
chk "stray commits refused push: main did not move" "$([ "$(git -C "$SCF" rev-parse HEAD)" = "$SCF_STRAY" ]; echo $?)"
chk_has "stray commits refused push: the pull step still ran" "$out" "-- pull:"

# ===========================================================================
echo "=== apply: wrap.autoland_carry lands the carry branches through merge --pr ==="
# ===========================================================================
# The incident: an earlier run pushed a carry branch and nobody opened its PR, so every later
# run skipped the file. With the knob on, apply opens that PR, merges it through `merge --pr`,
# then carries and lands whatever the orphan did not hold.
source "$KIT_DIR/lib/config/kit-config.sh"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root wrap.autoland_carry true)"
chk "wrap.autoland_carry ships as false" "$([ "$v" = "false" ]; echo $?)"
v="$(KIT_CONFIG_OPERATOR="$AL_ON" kit_config_get_root wrap.autoland_carry false)"
chk "wrap.autoland_carry honours the operator kit.toml" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_PROJECT_ROOT="$AL_PROJ" kit_config_get_root wrap.autoland_carry false)"
chk "wrap.autoland_carry ignores a project .kit.toml" "$([ "$v" = "false" ]; echo $?)"

build_union_repo aladopt; al_orphan aladopt
ALC="$TMPD/uclone-aladopt"; ALB="$TMPD/ubare-aladopt"; ALO="wrap/stray-meta-lab-log-md-20260101-0000"
printf '%s' "$LAB_STRAY" > "$ALC/_meta/LAB_LOG.md"
out="$(al_run "$ALB" "$ALC")"; rc=$?
chk "autoland dry-run: apply exits 0" "$rc"
chk_has "autoland dry-run: the orphan still skips" "$out" "an origin wrap/stray-meta-lab-log-md-* branch already carries this file"
chk_has "autoland dry-run: names the landing" "$out" "WOULD open and merge its PR (wrap.autoland_carry=true)"
chk_no "autoland dry-run: no PR was opened" "$(cat "$GH_STUB_CALLS")" "pr create"
ORPHAN_TIP="$(git -C "$ALB" rev-parse "$ALO")"
out="$(al_run "$ALB" "$ALC" --apply)"; rc=$?
chk "autoland adopt: apply exits 0" "$rc"
chk_has "autoland adopt: the orphan's PR is opened" "$(cat "$GH_STUB_CALLS")" "pr create --repo $ALB --head $ALO"
chk_has "autoland adopt: the orphan merges pinned to its tip" "$(cat "$GH_STUB_CALLS")" "--squash --match-head-commit $ORPHAN_TIP"
chk_has "autoland adopt: merge --pr verifies the tree" "$out" "tree verified"
chk_no "autoland adopt: the file is no longer skipped" "$out" "SKIP _meta/LAB_LOG.md"
chk_has "autoland adopt: the remainder is one line" "$out" "carried 1 stray lines in _meta/LAB_LOG.md to origin/wrap/stray-meta-lab-log-md-2"
chk "autoland adopt: two PRs opened, two merges" \
  "$([ "$(grep -c '^pr create' "$GH_STUB_CALLS")" = 2 ] && [ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" = 2 ]; echo $?)"
chk "autoland adopt: origin main holds both stray lines once" \
  "$([ "$(git -C "$ALB" show main:_meta/LAB_LOG.md)" = "${LAB_STRAY%$'\n'}" ]; echo $?)"
chk_no "autoland adopt: nothing failed" "$out" "FAILED"
out="$(al_run "$ALB" "$ALC" --apply)"
chk_has "autoland rerun: no stray lines left" "$(printf '%s' "$out" | grep -A1 -- '-- stray lines:')" "none"

echo "--- --no-pull (a step 0 stop): the stray-line carry pushes nothing, even with autoland on"
build_union_repo alnp
ALN="$TMPD/uclone-alnp"; ALNB="$TMPD/ubare-alnp"
printf '%s' "$LAB_STRAY" > "$ALN/_meta/LAB_LOG.md"
# A tracked file with an old mtime and unchanged content: `git diff HEAD` refreshes the index
# entry (a write), `git diff-index` does not, so the index checksum below tells them apart.
touch -t 202001010000 "$ALN/README.md"
ALN_INDEX="$(cksum < "$ALN/.git/index")"; ALN_HEAD="$(git -C "$ALN" rev-parse HEAD)"; ALN_BYTES="$(cksum < "$ALN/_meta/LAB_LOG.md")"
out="$(al_run "$ALNB" "$ALN" --apply --no-pull)"; rc=$?
chk "stray --no-pull: apply exits 0" "$rc"
chk_has "stray --no-pull: the skip names the count and the file" "$out" \
  "SKIP stray lines: --no-pull (2 lines in _meta/LAB_LOG.md stay local)"
chk_no "stray --no-pull: nothing is reported as carried" "$out" "carried 2 stray lines"
chk "stray --no-pull: no wrap/stray-* branch reached origin" \
  "$([ -z "$(git -C "$ALNB" for-each-ref --format='%(refname:short)' 'refs/heads/wrap/stray-*')" ]; echo $?)"
chk_no "stray --no-pull: no PR was opened" "$(cat "$GH_STUB_CALLS")" "pr create"
chk_no "stray --no-pull: no PR was merged" "$(cat "$GH_STUB_CALLS")" "pr merge"
chk "stray --no-pull: HEAD and the dirty file are untouched" \
  "$([ "$(git -C "$ALN" rev-parse HEAD)" = "$ALN_HEAD" ] && [ "$(cksum < "$ALN/_meta/LAB_LOG.md")" = "$ALN_BYTES" ]; echo $?)"
out="$(al_run "$ALNB" "$ALN" --no-pull)"
chk_has "stray --no-pull dry run: the same skip line" "$out" "SKIP stray lines: --no-pull (2 lines in _meta/LAB_LOG.md stay local)"
chk_no "stray --no-pull dry run: no WOULD carry line" "$out" "WOULD carry"
chk "stray --no-pull: the index file is not rewritten by the scan" \
  "$([ "$(cksum < "$ALN/.git/index")" = "$ALN_INDEX" ]; echo $?)"

echo "--- autoland: a gate refusal leaves the PR open, exit 0"
build_union_repo algate
ALG="$TMPD/uclone-algate"; ALGB="$TMPD/ubare-algate"
printf '%s' "$LAB_STRAY" > "$ALG/_meta/LAB_LOG.md"
AL_PR_OVERRIDE="${AL_PR/\"statusCheckRollup\":\[\]/\"statusCheckRollup\":[{\"name\":\"ci\",\"status\":\"COMPLETED\",\"conclusion\":\"FAILURE\",\"completedAt\":\"2026-01-01T00:00:00Z\"}]}"
out="$(AL_PR_OVERRIDE="$AL_PR_OVERRIDE" al_run "$ALGB" "$ALG" --apply)"; rc=$?
chk "autoland gate refusal: apply exits 0" "$rc"
chk_has "autoland gate refusal: the gate names the checks" "$out" "checks are pending or failing"
chk_has "autoland gate refusal: the PR is left open" "$out" "PR #42 left open; wrap merge --apply --pr 42 merges it once green"
chk_no "autoland gate refusal: nothing merged" "$(cat "$GH_STUB_CALLS")" "pr merge"
unset AL_PR_OVERRIDE

echo "--- autoland: a draft PR on the orphan is the lead's call"
build_union_repo aldraft; al_orphan aldraft
ALD="$TMPD/uclone-aldraft"; ALDB="$TMPD/ubare-aldraft"
printf '%s' "$LAB_STRAY" > "$ALD/_meta/LAB_LOG.md"
out="$(GH_STUB_OPEN_HEAD_wrap_stray_meta_lab_log_md_20260101_0000='[{"number":7,"isDraft":true,"author":{"login":"me"}}]' al_run "$ALDB" "$ALD" --apply)"; rc=$?
chk "autoland draft: apply exits 0" "$rc"
chk_has "autoland draft: names the draft" "$out" "SKIP land ${ALO}: its PR #7 is a draft"
chk_has "autoland draft: today's skip follows" "$out" "SKIP _meta/LAB_LOG.md: 2 stray lines"
chk_no "autoland draft: never marked ready" "$(cat "$GH_STUB_CALLS")" "pr ready"
chk_no "autoland draft: nothing merged" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- autoland: a PR another login authored on the orphan is never adopted"
build_union_repo alforeignpr; al_orphan alforeignpr
ALP="$TMPD/uclone-alforeignpr"; ALPB="$TMPD/ubare-alforeignpr"
printf '%s' "$LAB_STRAY" > "$ALP/_meta/LAB_LOG.md"
out="$(GH_STUB_OPEN_HEAD_wrap_stray_meta_lab_log_md_20260101_0000='[{"number":7,"isDraft":false,"author":{"login":"someone"}}]' al_run "$ALPB" "$ALP" --apply)"; rc=$?
chk "autoland foreign PR: apply exits 0" "$rc"
chk_has "autoland foreign PR: names it" "$out" "SKIP land ${ALO}: its PR #7 is not authored by you"
chk_no "autoland foreign PR: nothing merged" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- autoland: an orphan adding a line this checkout lacks, or a look-alike name, is never landed"
build_union_repo alforeign
ALX="$TMPD/uclone-alforeign"; ALXB="$TMPD/ubare-alforeign"; ALXP="$TMPD/upush-al-alforeign"
git clone -q "$ALXB" "$ALXP"; gitc "$ALXP"
printf '%s' $'# Lab log\n\n---\n\n2026-09-09 · foreign: nobody here wrote this\n2026-09-04 · stray: the first line\n2026-09-01 · base: the first line\n' > "$ALXP/_meta/LAB_LOG.md"
git -C "$ALXP" commit -qam "chore(LAB_LOG): carry 2 stray lines from a shared checkout"
git -C "$ALXP" push -q origin "HEAD:refs/heads/${ALO}" "HEAD:refs/heads/wrap/stray-meta-lab-log-md-bak-x"
printf '%s' "$LAB_STRAY" > "$ALX/_meta/LAB_LOG.md"
out="$(al_run "$ALXB" "$ALX" --apply)"; rc=$?
chk "autoland foreign content: apply exits 0" "$rc"
chk_has "autoland foreign content: the orphan is refused" "$out" "SKIP land ${ALO}: not a carry of _meta/LAB_LOG.md alone"
chk_has "autoland foreign content: the look-alike is refused" "$out" "SKIP land wrap/stray-meta-lab-log-md-bak-x: not a carry"
chk_has "autoland foreign content: today's skip follows" "$out" "SKIP _meta/LAB_LOG.md: 2 stray lines"
chk_no "autoland foreign content: no PR opened" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- autoland: an orphan that removes a line is never landed"
build_union_repo aldel
ALR="$TMPD/uclone-aldel"; ALRB="$TMPD/ubare-aldel"; ALRP="$TMPD/upush-al-aldel"
git clone -q "$ALRB" "$ALRP"; gitc "$ALRP"
printf '%s' $'# Lab log\n\n---\n\n2026-09-04 · stray: the first line\n' > "$ALRP/_meta/LAB_LOG.md"
git -C "$ALRP" commit -qam "chore(LAB_LOG): carry 1 stray lines from a shared checkout"
git -C "$ALRP" push -q origin "HEAD:refs/heads/${ALO}"
printf '%s' "$LAB_STRAY" > "$ALR/_meta/LAB_LOG.md"
out="$(al_run "$ALRB" "$ALR" --apply)"
chk_has "autoland removal: the orphan is refused" "$out" "SKIP land ${ALO}: not a carry of _meta/LAB_LOG.md alone"
chk_no "autoland removal: no PR opened" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- autoland: a PR head that moved off the checked commit is never merged"
build_union_repo almoved
ALM="$TMPD/uclone-almoved"; ALMB="$TMPD/ubare-almoved"
printf '%s' "$LAB_STRAY" > "$ALM/_meta/LAB_LOG.md"
out="$(AL_PR_OVERRIDE="${AL_PR/"%CARRY_TIP%"/1111111111111111111111111111111111111111}" al_run "$ALMB" "$ALM" --apply)"; rc=$?
chk "autoland moved head: apply exits 0" "$rc"
chk_has "autoland moved head: names the moved head" "$out" "PR #42 head is 1111111, not the checked"
chk_no "autoland moved head: nothing merged" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- autoland: a fresh PR with no checks yet waits for its state to settle"
build_union_repo alwait
ALW="$TMPD/uclone-alwait"; ALWB="$TMPD/ubare-alwait"
printf '%s' "$LAB_STRAY" > "$ALW/_meta/LAB_LOG.md"
out="$(PATH="$TMPD/nosleep:$PATH" AL_WAIT=30 GH_STUB_PR_42_2="$AL_PR" \
  AL_PR_OVERRIDE="${AL_PR/\"CLEAN\"/\"BLOCKED\"}" al_run "$ALWB" "$ALW" --apply)"; rc=$?
chk "autoland settle: apply exits 0" "$rc"
chk_has "autoland settle: merged once the state went CLEAN" "$out" "tree verified"
chk "autoland settle: the wait read twice before the merge" \
  "$([ "$(grep -c '^pr view 42 --repo .* --json statusCheckRollup,mergeStateStatus' "$GH_STUB_CALLS")" = 2 ]; echo $?)"

echo "--- autoland: wrap.merge_own_prs false wins"
AL_HOLD="$TMPD/autoland-hold"; mkdir -p "$AL_HOLD"
printf '[wrap]\nautoland_carry = true\nmerge_own_prs = false\n' > "$AL_HOLD/kit.toml"
build_union_repo alhold
ALH="$TMPD/uclone-alhold"
printf '%s' "$LAB_STRAY" > "$ALH/_meta/LAB_LOG.md"
: > "$GH_STUB_CALLS"
out="$(KIT_CONFIG_OPERATOR="$AL_HOLD" "$WRAP" apply --apply "$ALH" 2>&1)"
chk_has "autoland held: prints today's PR command" "$out" "open its PR with: gh pr create --head wrap/stray-meta-lab-log-md-"
chk_no "autoland held: no PR opened" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- autoland: a failed merge exits 2"
build_union_repo alfail
ALF="$TMPD/uclone-alfail"; ALFB="$TMPD/ubare-alfail"
printf '%s' "$LAB_STRAY" > "$ALF/_meta/LAB_LOG.md"
out="$(GH_STUB_MERGE_RC=1 al_run "$ALFB" "$ALF" --apply)"; rc=$?
chk "autoland merge failure: apply exits 2" "$([ "$rc" = 2 ]; echo $?)"
chk_has "autoland merge failure: merge names it" "$out" "FAILED merge #42"

echo "--- autoland: stray commits land, then main moves and pulls"
build_union_repo alcommit
ALS="$TMPD/uclone-alcommit"; ALSB="$TMPD/ubare-alcommit"
printf 'a note\n' > "$ALS/notes.md"; git -C "$ALS" add notes.md; git -C "$ALS" commit -qm "docs: a stray note"
out="$(al_run "$ALSB" "$ALS")"
chk_has "autoland commits dry-run: names the landing" "$out" "WOULD open and merge its PR (wrap.autoland_carry=true)"
out="$(al_run "$ALSB" "$ALS" --apply)"; rc=$?
ALSR="$(commit_branches "$ALSB")"
chk "autoland commits: apply exits 0" "$rc"
chk_has "autoland commits: the PR is opened" "$(cat "$GH_STUB_CALLS")" "pr create --repo $ALSB --head $ALSR"
chk_has "autoland commits: the merge verifies" "$out" "tree verified"
chk "autoland commits: origin main holds the note" "$([ "$(git -C "$ALSB" show main:notes.md)" = "a note" ]; echo $?)"
chk "autoland commits: main is origin/main" "$([ "$(git -C "$ALS" rev-parse HEAD)" = "$(git -C "$ALSB" rev-parse main)" ]; echo $?)"
chk_no "autoland commits: nothing failed" "$out" "FAILED"

echo "--- autoland: stray commits a dirty file keeps ahead are pushed, not landed"
build_union_repo alcblock
ALK="$TMPD/uclone-alcblock"
printf 'a note\n' > "$ALK/notes.md"; git -C "$ALK" add notes.md; git -C "$ALK" commit -qm "docs: a stray note"
printf 'readme local\n' > "$ALK/README.md"
out="$(al_run "$TMPD/ubare-alcblock" "$ALK")"
chk_no "autoland commits blocked dry-run: no landing named" "$out" "WOULD open and merge"
out="$(al_run "$TMPD/ubare-alcblock" "$ALK" --apply)"
chk_has "autoland commits blocked: the reason prints" "$out" "not landed: dirty tracked files block the move: README.md"
chk_no "autoland commits blocked: no PR opened" "$(cat "$GH_STUB_CALLS")" "pr create"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-carry: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-carry: all $PASS passed"
