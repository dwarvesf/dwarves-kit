#!/usr/bin/env bash
# test-wrap-pull.sh -- the pull cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== apply: a union-marked log is carried across the pull, nothing else is ==="
# ===========================================================================
# Real repos on disk, not a stubbed `git`: the whole point is what git itself does to a dirty
# checkout during a pull, which a command-text stub would never exercise.

echo "--- case 1+4: a dirty union log pulls clean, keeps both sides, anchors below the header"
build_union_repo carry; advance_union_repo carry
UC="$TMPD/uclone-carry"
printf '%s' "$LAB_LOCAL" > "$UC/_meta/LAB_LOG.md"
UC_TIP="$(git -C "$TMPD/ubare-carry" rev-parse main)"
out="$("$WRAP" apply --apply "$UC" 2>&1)"; rc=$?
chk "union carry: apply exits 0" "$rc"
chk_no "union carry: the pull did not fail" "$out" "FAILED pull --ff-only"
chk "union carry: HEAD moved to the incoming commit" \
  "$([ "$(git -C "$UC" rev-parse HEAD)" = "$UC_TIP" ]; echo $?)"
chk_has "union carry: HEAD prints in the pull block" "$out" "     HEAD: $(git -C "$UC" log --oneline -1)"
chk_has "union carry: the save is reported" "$out" "saved 1 union-marked file(s) aside"
chk_has "union carry: the carry-back count is reported" "$out" "carried 1 local line(s) back into _meta/LAB_LOG.md"
chk "union carry: the incoming line landed" \
  "$(grep -qF 'remote: the incoming line' "$UC/_meta/LAB_LOG.md"; echo $?)"
chk "union carry: the local uncommitted line survived" \
  "$(grep -qF 'local: the other session line' "$UC/_meta/LAB_LOG.md"; echo $?)"
chk "union carry: the local line is still uncommitted" \
  "$(git -C "$UC" diff --name-only | grep -qx '_meta/LAB_LOG.md'; echo $?)"
chk "union carry: README took the incoming content" \
  "$([ "$(cat "$UC/README.md")" = "readme remote" ]; echo $?)"
# Anchor rule: the header and the `---` separator stay above every carried line.
CARRY_LN="$(grep -n 'local: the other session line' "$UC/_meta/LAB_LOG.md" | cut -d: -f1)"
SEP_LN="$(grep -n '^---$' "$UC/_meta/LAB_LOG.md" | head -1 | cut -d: -f1)"
chk "union carry: line 1 is still the header" \
  "$([ "$(sed -n 1p "$UC/_meta/LAB_LOG.md")" = "# Lab log" ]; echo $?)"
chk "union carry: the carried line sits BELOW the --- anchor" \
  "$([ "$CARRY_LN" -gt "$SEP_LN" ]; echo $?)"
chk "union carry: the carried line sits ABOVE the older entries" \
  "$([ "$CARRY_LN" -lt "$(grep -n 'remote: the incoming line' "$UC/_meta/LAB_LOG.md" | cut -d: -f1)" ]; echo $?)"

echo "--- case 2: a dirty NON-union file is untouched and the pull behaves as it does today"
build_union_repo nonunion; advance_union_repo nonunion
UN="$TMPD/uclone-nonunion"
printf 'readme local edit\n' > "$UN/README.md"
UN_BEFORE="$(cksum < "$UN/README.md")"
UN_HEAD="$(git -C "$UN" rev-parse HEAD)"
out="$("$WRAP" apply --apply "$UN" 2>&1)"; rc=$?
chk "non-union: apply exits 2 because the pull still aborts" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "non-union: the blocking file is named before the pull" "$out" \
  "NOTE: uncommitted and not declared merge=union, so the pull aborts on: README.md"
chk_has "non-union: the pull failure is still reported" "$out" "FAILED pull --ff-only"
chk_no "non-union: nothing was saved aside" "$out" "union-marked file(s) aside"
chk "non-union: the dirty file is byte-identical" \
  "$([ "$UN_BEFORE" = "$(cksum < "$UN/README.md")" ]; echo $?)"
chk "non-union: HEAD did not move" "$([ "$(git -C "$UN" rev-parse HEAD)" = "$UN_HEAD" ]; echo $?)"

echo "--- case 3: one union plus one non-union is treated as the non-union case"
build_union_repo mixed; advance_union_repo mixed
UM="$TMPD/uclone-mixed"
printf '%s' "$LAB_LOCAL" > "$UM/_meta/LAB_LOG.md"
printf 'readme local edit\n' > "$UM/README.md"
UM_LAB_BEFORE="$(cksum < "$UM/_meta/LAB_LOG.md")"
out="$("$WRAP" apply --apply "$UM" 2>&1)"
chk_has "mixed: the non-union file is named" "$out" "not declared merge=union, so the pull aborts on: README.md"
chk_no "mixed: the union file was never saved aside" "$out" "union-marked file(s) aside"
chk_no "mixed: no carry-back happened" "$out" "local line(s) back into"
chk "mixed: the union file is byte-identical" \
  "$([ "$UM_LAB_BEFORE" = "$(cksum < "$UM/_meta/LAB_LOG.md")" ]; echo $?)"

echo "--- case 5: a dirty index is skipped with a reason, nothing is touched"
build_union_repo staged; advance_union_repo staged
US="$TMPD/uclone-staged"
printf '%s' "$LAB_LOCAL" > "$US/_meta/LAB_LOG.md"
git -C "$US" add _meta/LAB_LOG.md
US_BEFORE="$(cksum < "$US/_meta/LAB_LOG.md")"
out="$("$WRAP" apply --apply "$US" 2>&1)"
chk_has "dirty index: the reason prints" "$out" "NOTE: the index carries staged changes"
chk_no "dirty index: nothing was saved aside" "$out" "union-marked file(s) aside"
chk "dirty index: the staged path is still staged" \
  "$(git -C "$US" diff --cached --name-only | grep -qx '_meta/LAB_LOG.md'; echo $?)"
chk "dirty index: the file is byte-identical" \
  "$([ "$US_BEFORE" = "$(cksum < "$US/_meta/LAB_LOG.md")" ]; echo $?)"

echo "--- dry-run: a dirty union log is announced, never saved or checked out"
build_union_repo dry; advance_union_repo dry
UD="$TMPD/uclone-dry"
printf '%s' "$LAB_LOCAL" > "$UD/_meta/LAB_LOG.md"
UD_BEFORE="$(cksum < "$UD/_meta/LAB_LOG.md")"
out="$("$WRAP" apply "$UD" 2>&1)"
chk_has "dry-run: the carry is announced only" "$out" "--apply would carry its local lines across the pull"
chk_no "dry-run: nothing was saved aside" "$out" "union-marked file(s) aside"
chk "dry-run: the union file is byte-identical" \
  "$([ "$UD_BEFORE" = "$(cksum < "$UD/_meta/LAB_LOG.md")" ]; echo $?)"

# ===========================================================================
echo "=== apply: wrap.pull_past_dirty stashes only the blocking files ==="
# ===========================================================================
# Real repos again, for the same reason: what git refuses to overwrite during a fast-forward
# is the subject, and no stubbed `git` refuses anything.
A_BASE=$'a1\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'
A_REMOTE=$'a1 remote\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'
A_LOCAL_FAR=$'a1\na2\na3\na4\na5\na6\na7\na8\na9\na10 local\n'
A_LOCAL_SAME=$'a1 local\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'

build_pd_repo() { # build_pd_repo <name> -- bare origin plus a clone on main
  local name="$1" work clone
  work="$TMPD/pdwork-$name"; clone="$TMPD/pdclone-$name"
  mkdir -p "$work/_meta"
  git -C "$work" init -q
  gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf '%s' "$LAB_BASE" > "$work/_meta/LAB_LOG.md"
  printf '%s' "$A_BASE" > "$work/A.md"
  printf 'b base\n' > "$work/B.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/pdbare-$name"
  git clone -q "$TMPD/pdbare-$name" "$clone"
  gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
}

advance_pd_repo() { # advance_pd_repo <name> [also-lab] -- one incoming commit touching A.md
  local name="$1" also="${2:-}" push
  push="$TMPD/pdpush-$name"
  git clone -q "$TMPD/pdbare-$name" "$push"
  gitc "$push"
  printf '%s' "$A_REMOTE" > "$push/A.md"
  [ -n "$also" ] && printf '%s' "$LAB_REMOTE" > "$push/_meta/LAB_LOG.md"
  git -C "$push" commit -qam advance
  git -C "$push" push -q origin main
}

# A stash another session left behind. A bare `git stash pop` would take this one; every case
# below asserts it survives untouched, which is the whole reason the pop resolves a ref.
pd_sibling_stash() { # pd_sibling_stash <clone>
  printf 'sibling work\n' >> "$1/B.md"
  git -C "$1" stash push -q -m sibling -- B.md
}
pd_stash_count() { git -C "$1" stash list | grep -c '' ; }

echo "--- knob off: the pull still aborts and nothing moves"
build_pd_repo off; advance_pd_repo off
PO="$TMPD/pdclone-off"
pd_sibling_stash "$PO"
printf '%s' "$A_LOCAL_FAR" > "$PO/A.md"
printf 'b local edit\n' > "$PO/B.md"
printf 'c untracked\n' > "$PO/C.md"
PO_HEAD="$(git -C "$PO" rev-parse HEAD)"
PO_A="$(cksum < "$PO/A.md")"; PO_B="$(cksum < "$PO/B.md")"
out="$("$WRAP" apply --apply "$PO" 2>&1)"; rc=$?
chk "knob off: apply still exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "knob off: the pull failure is still reported" "$out" "FAILED pull --ff-only"
chk_has "knob off: git named the blocking file" "$out" "would be overwritten by merge"
chk_no "knob off: nothing was stashed" "$out" "stashed"
chk "knob off: HEAD did not move" "$([ "$(git -C "$PO" rev-parse HEAD)" = "$PO_HEAD" ]; echo $?)"
chk "knob off: A.md is byte-identical" "$([ "$PO_A" = "$(cksum < "$PO/A.md")" ]; echo $?)"
chk "knob off: B.md is byte-identical" "$([ "$PO_B" = "$(cksum < "$PO/B.md")" ]; echo $?)"
chk "knob off: the untracked file is still there" "$([ -f "$PO/C.md" ]; echo $?)"
chk "knob off: the sibling stash is the only stash" "$([ "$(pd_stash_count "$PO")" = "1" ]; echo $?)"

echo "--- knob on: the blocking file goes aside, the pull lands, everything else stays put"
build_pd_repo on; advance_pd_repo on
PN="$TMPD/pdclone-on"
pd_sibling_stash "$PN"
printf '%s' "$A_LOCAL_FAR" > "$PN/A.md"
printf 'b local edit\n' > "$PN/B.md"
printf 'c untracked\n' > "$PN/C.md"
PN_TIP="$(git -C "$TMPD/pdbare-on" rev-parse main)"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PN" 2>&1)"; rc=$?
chk "knob on: apply exits 0" "$rc"
chk_no "knob on: the pull did not fail" "$out" "FAILED pull --ff-only"
chk_has "knob on: the NOTE says the pull stashes rather than aborts" "$out" \
  "wrap.pull_past_dirty is on, so the pull stashes"
chk_has "knob on: exactly the one blocking file was stashed" "$out" "stashed 1 dirty tracked file(s)"
chk_has "knob on: the stash carries the run name" "$out" "as wrap-pull-past-dirty-"
chk_has "knob on: the stash was restored and dropped" "$out" "restored the stashed file(s) and dropped"
chk "knob on: HEAD moved to the incoming commit" \
  "$([ "$(git -C "$PN" rev-parse HEAD)" = "$PN_TIP" ]; echo $?)"
chk "knob on: the incoming line landed in A.md" "$(grep -qx 'a1 remote' "$PN/A.md"; echo $?)"
chk "knob on: the local line survived in A.md" "$(grep -qx 'a10 local' "$PN/A.md"; echo $?)"
chk_has "knob on: A.md is still uncommitted" "$(git -C "$PN" diff --name-only)" "A.md"
chk "knob on: A.md is not staged" \
  "$([ -z "$(git -C "$PN" diff --cached --name-only)" ]; echo $?)"
chk "knob on: B.md kept its local edit" "$([ "$(cat "$PN/B.md")" = "b local edit" ]; echo $?)"
chk_has "knob on: B.md is still dirty" "$(git -C "$PN" diff --name-only)" "B.md"
chk "knob on: the untracked file is untouched" \
  "$([ "$(cat "$PN/C.md")" = "c untracked" ]; echo $?)"
chk "knob on: the sibling stash is the only stash left" \
  "$([ "$(pd_stash_count "$PN")" = "1" ]; echo $?)"
chk_has "knob on: the surviving stash is the sibling's" "$(git -C "$PN" stash list)" "sibling"

echo "--- knob on: a sibling stash pushed DURING the pull does not steal the pop"
# The race the by-commit resolution exists for. A stash index shifts the moment any session
# pushes an entry, so a ref resolved before the pull points at the wrong entry after it. A
# post-merge hook is how the suite stages that deterministically.
build_pd_repo race; advance_pd_repo race
PRACE="$TMPD/pdclone-race"
printf '%s' "$A_LOCAL_FAR" > "$PRACE/A.md"
printf 'b local edit\n' > "$PRACE/B.md"
mkdir -p "$PRACE/.git/hooks"
printf '#!/bin/sh\ngit stash push -q -m sibling-mid-pull -- B.md\n' > "$PRACE/.git/hooks/post-merge"
chmod +x "$PRACE/.git/hooks/post-merge"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PRACE" 2>&1)"; rc=$?
chk "mid-pull stash: apply exits 0" "$rc"
chk_has "mid-pull stash: our own stash was the one restored" "$out" \
  "restored the stashed file(s) and dropped"
chk "mid-pull stash: A.md kept the local edit" "$(grep -qx 'a10 local' "$PRACE/A.md"; echo $?)"
chk "mid-pull stash: A.md took the incoming line" "$(grep -qx 'a1 remote' "$PRACE/A.md"; echo $?)"
chk "mid-pull stash: the sibling's mid-pull stash is still listed" \
  "$([ "$(pd_stash_count "$PRACE")" = "1" ]; echo $?)"
chk_has "mid-pull stash: and it is the sibling's, not ours" "$(git -C "$PRACE" stash list)" \
  "sibling-mid-pull"

echo "--- knob on: a sibling stash pushed right AFTER ours is not mistaken for ours"
# The other half of the race: a sibling's entry lands between the run's own stash push and
# the moment the run reads which entry is its own. Whatever sits at the top of the stack
# is then the sibling's, so the run must find its entry by name. A git shim stages the
# sibling's push the instant the run's own push returns.
build_pd_repo after; advance_pd_repo after
PAFT="$TMPD/pdclone-after"
printf '%s' "$A_LOCAL_FAR" > "$PAFT/A.md"
printf 'b sibling edit\n' > "$PAFT/B.md"
mkdir -p "$TMPD/gitshim"
REAL_GIT="$(command -v git)"
cat > "$TMPD/gitshim/git" <<SHIM
#!/usr/bin/env bash
"$REAL_GIT" "\$@"; rc=\$?
case " \$* " in *" -m wrap-pull-past-dirty-"*) "$REAL_GIT" -C "$PAFT" stash push -q -m sibling-after -- B.md ;; esac
exit \$rc
SHIM
chmod +x "$TMPD/gitshim/git"
out="$(PATH="$TMPD/gitshim:$PATH" KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PAFT" 2>&1)"; rc=$?
chk "after-push stash: apply exits 0" "$rc"
chk_has "after-push stash: our own stash was the one restored" "$out" \
  "restored the stashed file(s) and dropped"
chk "after-push stash: A.md kept the local edit" "$(grep -qx 'a10 local' "$PAFT/A.md"; echo $?)"
chk "after-push stash: A.md took the incoming line" "$(grep -qx 'a1 remote' "$PAFT/A.md"; echo $?)"
chk "after-push stash: the sibling's entry was not popped" \
  "$([ "$(cat "$PAFT/B.md")" = "b base" ]; echo $?)"
chk "after-push stash: exactly one stash is left" \
  "$([ "$(pd_stash_count "$PAFT")" = "1" ]; echo $?)"
chk_has "after-push stash: and it is the sibling's, not ours" "$(git -C "$PAFT" stash list)" \
  "sibling-after"

echo "--- knob on: a pop conflict keeps the stash and reports it"
build_pd_repo conflict; advance_pd_repo conflict
PC="$TMPD/pdclone-conflict"
pd_sibling_stash "$PC"
printf '%s' "$A_LOCAL_SAME" > "$PC/A.md"
PC_TIP="$(git -C "$TMPD/pdbare-conflict" rev-parse main)"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PC" 2>&1)"; rc=$?
chk "pop conflict: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pop conflict: the report names the file and keeps the stash" "$out" \
  "PULLED, POP CONFLICT: A.md, stash wrap-pull-past-dirty-"
chk "pop conflict: the pull still landed" \
  "$([ "$(git -C "$PC" rev-parse HEAD)" = "$PC_TIP" ]; echo $?)"
chk "pop conflict: the conflict markers are in the file" \
  "$(grep -q '^<<<<<<<' "$PC/A.md"; echo $?)"
chk_has "pop conflict: the run's own stash is still listed" "$(git -C "$PC" stash list)" "wrap-pull-past-dirty-"
chk "pop conflict: the sibling stash survived too" \
  "$([ "$(pd_stash_count "$PC")" = "2" ]; echo $?)"

echo "--- knob on: a dirty union file beside a dirty non-union file is carried, not stashed"
# The 2026-09-19 incident shape: LAB_LOG.md (merge=union) and a plain dirty file were both
# changed upstream, the union file went into the pull-past-dirty stash, and its pop left
# the checkout still dirty with the stash kept. Union files take the carry path now, so
# only the genuinely non-union blocker is ever stashed.
build_pd_repo union; advance_pd_repo union also-lab
PU="$TMPD/pdclone-union"
printf '%s' "$A_LOCAL_FAR" > "$PU/A.md"
printf '%s' "$LAB_LOCAL" > "$PU/_meta/LAB_LOG.md"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PU" 2>&1)"; rc=$?
chk "union carry+stash: apply exits 0" "$rc"
chk_no "union carry+stash: the pull did not fail" "$out" "FAILED pull --ff-only"
chk_has "union carry+stash: the union file was carried, not stashed" "$out" \
  "saved 1 union-marked file(s) aside"
chk_has "union carry+stash: the union lines came back" "$out" \
  "carried 1 local line(s) back into _meta/LAB_LOG.md"
chk_has "union carry+stash: only the non-union blocker was stashed" "$out" \
  "stashed 1 dirty tracked file(s)"
chk_has "union carry+stash: the stash was restored and dropped" "$out" \
  "restored the stashed file(s) and dropped"
chk "union carry+stash: the incoming log line landed" \
  "$(grep -qF 'remote: the incoming line' "$PU/_meta/LAB_LOG.md"; echo $?)"
chk "union carry+stash: the local log line survived" \
  "$(grep -qF 'local: the other session line' "$PU/_meta/LAB_LOG.md"; echo $?)"
chk "union carry+stash: the local line in A.md survived" \
  "$(grep -qx 'a10 local' "$PU/A.md"; echo $?)"
chk "union carry+stash: no stash is left behind" "$([ "$(pd_stash_count "$PU")" = "0" ]; echo $?)"

echo "--- knob on: an untracked file the incoming commit adds still aborts the pull"
build_pd_repo untracked
UPUSH="$TMPD/pdpush-untracked"
git clone -q "$TMPD/pdbare-untracked" "$UPUSH"; gitc "$UPUSH"
printf '%s' "$A_REMOTE" > "$UPUSH/A.md"; printf 'c incoming\n' > "$UPUSH/C.md"
git -C "$UPUSH" add -A; git -C "$UPUSH" commit -qm advance; git -C "$UPUSH" push -q origin main
PX="$TMPD/pdclone-untracked"
pd_sibling_stash "$PX"
printf '%s' "$A_LOCAL_FAR" > "$PX/A.md"
printf 'c local untracked\n' > "$PX/C.md"
PX_HEAD="$(git -C "$PX" rev-parse HEAD)"
PX_A="$(cksum < "$PX/A.md")"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PX" 2>&1)"; rc=$?
chk "untracked block: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "untracked block: the pull still failed" "$out" "FAILED pull --ff-only"
chk_has "untracked block: the stash came back anyway" "$out" "restored the stashed file(s)"
chk "untracked block: HEAD did not move" \
  "$([ "$(git -C "$PX" rev-parse HEAD)" = "$PX_HEAD" ]; echo $?)"
chk "untracked block: the dirty tracked file is byte-identical" \
  "$([ "$PX_A" = "$(cksum < "$PX/A.md")" ]; echo $?)"
chk "untracked block: the untracked file kept its local content" \
  "$([ "$(cat "$PX/C.md")" = "c local untracked" ]; echo $?)"
chk "untracked block: the sibling stash is the only stash" \
  "$([ "$(pd_stash_count "$PX")" = "1" ]; echo $?)"

echo "--- knob on: a dirty index is never stashed past"
build_pd_repo staged2; advance_pd_repo staged2
PS="$TMPD/pdclone-staged2"
printf '%s' "$A_LOCAL_FAR" > "$PS/A.md"
git -C "$PS" add A.md
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PS" 2>&1)"; rc=$?
chk "dirty index: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "dirty index: the index reason prints" "$out" "NOTE: the index carries staged changes"
chk_no "dirty index: nothing was stashed" "$out" "stashed"
chk_has "dirty index: the path is still staged" "$(git -C "$PS" diff --cached --name-only)" "A.md"

echo "--- knob on: a dry run never stashes"
build_pd_repo dry2; advance_pd_repo dry2
PD="$TMPD/pdclone-dry2"
printf '%s' "$A_LOCAL_FAR" > "$PD/A.md"
PD_A="$(cksum < "$PD/A.md")"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply "$PD" 2>&1)"
chk_no "dry run: nothing was stashed" "$out" "stashed"
chk_has "dry run: the knob is announced" "$out" "--apply would stash whichever of these block the pull"
chk "dry run: no stash was created" "$([ "$(pd_stash_count "$PD")" = "0" ]; echo $?)"
chk "dry run: the dirty file is byte-identical" "$([ "$PD_A" = "$(cksum < "$PD/A.md")" ]; echo $?)"

echo "--- knob on: an incoming rename does not hide the path the pull blocks on"
build_pd_repo rename
RPUSH="$TMPD/pdpush-rename"
git clone -q "$TMPD/pdbare-rename" "$RPUSH"; gitc "$RPUSH"
git -C "$RPUSH" mv A.md Z.md
printf '%s' "$A_REMOTE" > "$RPUSH/Z.md"
git -C "$RPUSH" add -A; git -C "$RPUSH" commit -qm rename
git -C "$TMPD/pdbare-rename" fetch -q "$RPUSH" main:main
PR_="$TMPD/pdclone-rename"
printf '%s' "$A_LOCAL_FAR" > "$PR_/A.md"
PR_TIP="$(git -C "$TMPD/pdbare-rename" rev-parse main)"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PR_" 2>&1)"; rc=$?
chk "rename: apply exits 0" "$rc"
chk_has "rename: the renamed-away path was still stashed" "$out" "stashed 1 dirty tracked file(s)"
chk "rename: HEAD moved to the incoming commit" \
  "$([ "$(git -C "$PR_" rev-parse HEAD)" = "$PR_TIP" ]; echo $?)"
# The pop follows the rename: the local edit lands on the incoming path, and nothing is lost.
chk "rename: the renamed file carries the incoming content" \
  "$(grep -qx 'a1 remote' "$PR_/Z.md"; echo $?)"
chk "rename: the local edit followed the rename instead of being lost" \
  "$(grep -qx 'a10 local' "$PR_/Z.md"; echo $?)"
chk "rename: the old path is gone, as the incoming commit says" "$([ ! -e "$PR_/A.md" ]; echo $?)"

echo "--- knob on: a worktree-deleted file is left for git to rewrite, never stashed"
build_pd_repo deleted; advance_pd_repo deleted
PDEL="$TMPD/pdclone-deleted"
mv -f "$PDEL/A.md" "$TMPD/pd-deleted-A.md"
PDEL_TIP="$(git -C "$TMPD/pdbare-deleted" rev-parse main)"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PDEL" 2>&1)"; rc=$?
chk "deleted: apply exits 0, as it does with the knob off" "$rc"
chk_no "deleted: nothing was stashed" "$out" "stashed"
chk_no "deleted: no pop conflict was manufactured" "$out" "POP CONFLICT"
chk "deleted: the pull landed" \
  "$([ "$(git -C "$PDEL" rev-parse HEAD)" = "$PDEL_TIP" ]; echo $?)"
chk "deleted: git rewrote the file with the incoming content" \
  "$(grep -qx 'a1 remote' "$PDEL/A.md"; echo $?)"
chk "deleted: the index carries no unmerged path" \
  "$([ -z "$(git -C "$PDEL" diff --name-only --diff-filter=U)" ]; echo $?)"

echo "--- knob on: a diverged checkout is never stashed past"
build_pd_repo diverged; advance_pd_repo diverged
PDIV="$TMPD/pdclone-diverged"
printf 'local commit\n' > "$PDIV/B.md"
git -C "$PDIV" commit -qam "chore: a local commit the remote never saw"
printf '%s' "$A_LOCAL_FAR" > "$PDIV/A.md"
PDIV_HEAD="$(git -C "$PDIV" rev-parse HEAD)"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PDIV" 2>&1)"; rc=$?
chk "diverged: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_no "diverged: nothing was stashed" "$out" "stashed"
chk "diverged: no stash was created" "$([ "$(pd_stash_count "$PDIV")" = "0" ]; echo $?)"
chk "diverged: HEAD did not move" \
  "$([ "$(git -C "$PDIV" rev-parse HEAD)" = "$PDIV_HEAD" ]; echo $?)"

echo "--- knob on: a path with a space and a glob character is stashed as itself"
build_pd_repo oddname
ONAME='a [odd] name.md'
git -C "$TMPD/pdwork-oddname" checkout -q main 2>/dev/null
printf '%s' "$A_BASE" > "$TMPD/pdwork-oddname/$ONAME"
printf 'decoy\n' > "$TMPD/pdwork-oddname/a o name.md"
git -C "$TMPD/pdwork-oddname" add -A
git -C "$TMPD/pdwork-oddname" commit -qm "chore: add the odd names"
git -C "$TMPD/pdbare-oddname" fetch -q "$TMPD/pdwork-oddname" main:main
PODD="$TMPD/pdclone-oddname"
git -C "$PODD" pull -q --ff-only
printf '%s' "$A_REMOTE" > "$TMPD/pdwork-oddname/$ONAME"
git -C "$TMPD/pdwork-oddname" commit -qam "chore: change the odd name"
git -C "$TMPD/pdbare-oddname" fetch -q "$TMPD/pdwork-oddname" main:main
printf '%s' "$A_LOCAL_FAR" > "$PODD/$ONAME"
printf 'decoy local\n' > "$PODD/a o name.md"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PODD" 2>&1)"; rc=$?
chk "odd name: apply exits 0" "$rc"
chk_has "odd name: exactly one file was stashed" "$out" "stashed 1 dirty tracked file(s)"
chk "odd name: the incoming line landed" "$(grep -qx 'a1 remote' "$PODD/$ONAME"; echo $?)"
chk "odd name: the local edit came back" "$(grep -qx 'a10 local' "$PODD/$ONAME"; echo $?)"
chk "odd name: the decoy the glob would have matched is untouched" \
  "$([ "$(cat "$PODD/a o name.md")" = "decoy local" ]; echo $?)"


# ===========================================================================
echo "=== apply --pull-only: the pull stage alone ==="
# ===========================================================================
# SPEC-359. Reuses the pull_past_dirty fixtures above (build_pd_repo/advance_pd_repo/
# pd_sibling_stash/pd_stash_count, PD_ON) since --pull-only changes nothing about
# _pull_default itself, only which OTHER steps run around it.

echo "--- pull-only: scope, happy path (only fetch + pull run, everything else survives)"
build_pd_repo puloscope
PSC="$TMPD/pdclone-puloscope"
git -C "$PSC" branch old-branch
advance_pd_repo puloscope
PSC_TIP="$(git -C "$TMPD/pdbare-puloscope" rev-parse main)"
out="$("$WRAP" apply --pull-only --apply "$PSC" 2>&1)"; rc=$?
chk "pull-only scope: exits 0" "$rc"
chk "pull-only scope: HEAD moved to the incoming commit" \
  "$([ "$(git -C "$PSC" rev-parse HEAD)" = "$PSC_TIP" ]; echo $?)"
chk "pull-only scope: old-branch still exists (branch sweep never ran)" \
  "$(git -C "$PSC" show-ref --verify --quiet refs/heads/old-branch; echo $?)"
chk_has "pull-only scope: the pull section still prints" "$out" "-- pull:"
chk_no "pull-only scope: no worktrees section" "$out" "-- worktrees:"
chk_no "pull-only scope: no branches section" "$out" "-- branches:"
chk_no "pull-only scope: no archive unmerged section" "$out" "-- archive unmerged:"
chk_no "pull-only scope: no origin branches section" "$out" "-- origin branches:"
chk_no "pull-only scope: no stray lines section" "$out" "-- stray lines:"
chk_no "pull-only scope: no stray commits section" "$out" "-- stray commits:"
chk_no "pull-only scope: no ahead NOTE when main is not ahead" "$out" "commits ahead of origin/"

echo "--- pull-only: union carry and wrap.pull_past_dirty stash/pop both still work"
build_pd_repo pulounion; advance_pd_repo pulounion also-lab
PUO="$TMPD/pdclone-pulounion"
printf '%s' "$A_LOCAL_FAR" > "$PUO/A.md"
printf '%s' "$LAB_LOCAL" > "$PUO/_meta/LAB_LOG.md"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --pull-only --apply "$PUO" 2>&1)"; rc=$?
chk "pull-only union+stash: apply exits 0" "$rc"
chk_no "pull-only union+stash: the pull did not fail" "$out" "FAILED pull --ff-only"
chk_has "pull-only union+stash: the union file was carried, not stashed" "$out" \
  "saved 1 union-marked file(s) aside"
chk_has "pull-only union+stash: the union lines came back" "$out" \
  "carried 1 local line(s) back into _meta/LAB_LOG.md"
chk_has "pull-only union+stash: only the non-union blocker was stashed" "$out" \
  "stashed 1 dirty tracked file(s)"
chk_has "pull-only union+stash: the stash was restored and dropped" "$out" \
  "restored the stashed file(s) and dropped"
chk "pull-only union+stash: the incoming log line landed" \
  "$(grep -qF 'remote: the incoming line' "$PUO/_meta/LAB_LOG.md"; echo $?)"
chk "pull-only union+stash: the local log line survived" \
  "$(grep -qF 'local: the other session line' "$PUO/_meta/LAB_LOG.md"; echo $?)"
chk "pull-only union+stash: the local line in A.md survived" \
  "$(grep -qx 'a10 local' "$PUO/A.md"; echo $?)"
chk "pull-only union+stash: no stash is left behind" "$([ "$(pd_stash_count "$PUO")" = "0" ]; echo $?)"
chk_no "pull-only union+stash: no branches section" "$out" "-- branches:"
chk_no "pull-only union+stash: the stray log line was not carried to an origin branch" \
  "$(git -C "$TMPD/pdbare-pulounion" for-each-ref --format='%(refname)' refs/heads/)" "wrap/stray-"

echo "--- pull-only: wrap.pull_past_dirty off still aborts and nothing moves"
build_pd_repo pulooff; advance_pd_repo pulooff
POF="$TMPD/pdclone-pulooff"
printf '%s' "$A_LOCAL_FAR" > "$POF/A.md"
printf '%s' "$LAB_LOCAL" > "$POF/_meta/LAB_LOG.md"
POF_HEAD="$(git -C "$POF" rev-parse HEAD)"
out="$("$WRAP" apply --pull-only --apply "$POF" 2>&1)"; rc=$?
chk "pull-only knob off: the union file's local line survived the failed pull" \
  "$(grep -qF 'local: the other session line' "$POF/_meta/LAB_LOG.md"; echo $?)"
chk "pull-only knob off: apply exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pull-only knob off: the pull failure is still reported" "$out" "FAILED pull --ff-only"
chk_no "pull-only knob off: nothing was stashed" "$out" "stashed"
chk "pull-only knob off: HEAD did not move" "$([ "$(git -C "$POF" rev-parse HEAD)" = "$POF_HEAD" ]; echo $?)"

echo "--- pull-only: dry run changes nothing"
build_pd_repo pulodry; advance_pd_repo pulodry
PDR="$TMPD/pdclone-pulodry"
PDR_HEAD="$(git -C "$PDR" rev-parse HEAD)"
out="$("$WRAP" apply --pull-only "$PDR" 2>&1)"; rc=$?
chk "pull-only dry run: exits 0" "$rc"
chk_has "pull-only dry run: DRY-RUN verdict prints" "$out" "[DRY-RUN] pull --ff-only"
chk "pull-only dry run: HEAD unmoved" "$([ "$(git -C "$PDR" rev-parse HEAD)" = "$PDR_HEAD" ]; echo $?)"
chk_no "pull-only dry run: no branches section" "$out" "-- branches:"

echo "--- pull-only: checkout off the default branch fetches instead of pulling"
build_pd_repo pulooffdef; advance_pd_repo pulooffdef
POD="$TMPD/pdclone-pulooffdef"
git -C "$POD" checkout -qb feature/x
out="$("$WRAP" apply --pull-only --apply "$POD" 2>&1)"; rc=$?
chk "pull-only off-default: exits 0" "$rc"
chk_has "pull-only off-default: SKIP pull line" "$out" "SKIP pull: checkout on 'feature/x'"
chk_has "pull-only off-default: fetch fallback ran" "$out" "fetch origin main:main (ff-only by nature)"
chk_no "pull-only off-default: no branches section" "$out" "-- branches:"
chk_no "pull-only off-default: no worktrees section" "$out" "-- worktrees:"

echo "--- pull-only: stray commits, ahead-only (origin unmoved) lands as a no-op"
build_pd_repo puloahead
PAH="$TMPD/pdclone-puloahead"
printf 'local only\n' > "$PAH/B.md"
git -C "$PAH" commit -qam "chore: a local commit origin never saw"
PAH_HEAD="$(git -C "$PAH" rev-parse HEAD)"
out="$("$WRAP" apply --pull-only --apply "$PAH" 2>&1)"; rc=$?
chk "pull-only ahead-only: exits 0" "$rc"
chk_no "pull-only ahead-only: no FAILED pull line" "$out" "FAILED pull --ff-only"
chk "pull-only ahead-only: HEAD unchanged" "$([ "$(git -C "$PAH" rev-parse HEAD)" = "$PAH_HEAD" ]; echo $?)"
chk_has "pull-only ahead-only: the ahead count is named, not silent" "$out" \
  "NOTE: main is 1 commits ahead of origin/main; --pull-only never carries them"
chk_no "pull-only ahead-only: no local stray-commits branch" \
  "$(git -C "$PAH" for-each-ref --format='%(refname)' refs/heads/)" "wrap/stray-commits-"
chk_no "pull-only ahead-only: no origin stray-commits branch" \
  "$(git -C "$TMPD/pdbare-puloahead" for-each-ref --format='%(refname)' refs/heads/)" "wrap/stray-commits-"

echo "--- pull-only: stray commits, diverged still fails the pull"
build_pd_repo pulodiverged; advance_pd_repo pulodiverged
PDV="$TMPD/pdclone-pulodiverged"
printf 'local only\n' > "$PDV/B.md"
git -C "$PDV" commit -qam "chore: a local commit the remote never saw"
PDV_HEAD="$(git -C "$PDV" rev-parse HEAD)"
out="$("$WRAP" apply --pull-only --apply "$PDV" 2>&1)"; rc=$?
chk "pull-only diverged: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pull-only diverged: FAILED pull line present" "$out" "FAILED pull --ff-only"
chk "pull-only diverged: HEAD did not move" "$([ "$(git -C "$PDV" rev-parse HEAD)" = "$PDV_HEAD" ]; echo $?)"
chk_has "pull-only diverged: the ahead count is named" "$out" "NOTE: main is 1 commits ahead of origin/main"
chk_no "pull-only diverged: no local stray-commits branch" \
  "$(git -C "$PDV" for-each-ref --format='%(refname)' refs/heads/)" "wrap/stray-commits-"
chk_no "pull-only diverged: no origin stray-commits branch" \
  "$(git -C "$TMPD/pdbare-pulodiverged" for-each-ref --format='%(refname)' refs/heads/)" "wrap/stray-commits-"

echo "--- pull-only: fetch failure wording differs from plain apply"
build_pd_repo pulofetchfail
PFF="$TMPD/pdclone-pulofetchfail"
git -C "$PFF" remote set-url origin "$TMPD/does-not-exist-bare-xyz"
out="$("$WRAP" apply --pull-only --apply "$PFF" 2>&1)"; rc=$?
chk "pull-only fetch failure: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pull-only fetch failure: the wording names the pull" "$out" \
  "(fetch failed; the pull below will likely fail too)"
chk_no "pull-only fetch failure: not the plain-apply wording" "$out" "every delete is skipped"
chk_has "pull-only fetch failure: a FAILED pull line follows" "$out" "FAILED pull --ff-only"

echo "--- pull-only: the no-repo usage line names the flag"
out="$("$WRAP" apply --pull-only 2>&1)"; rc=$?
chk "pull-only usage: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only usage: the usage line names --pull-only" "$out" "--pull-only"

echo "--- pull-only: flag conflicts"
build_pd_repo puloconflict; advance_pd_repo puloconflict
PCFL="$TMPD/pdclone-puloconflict"
PCFL_HEAD="$(git -C "$PCFL" rev-parse HEAD)"
out="$("$WRAP" apply --pull-only --apply --worktrees "$PCFL" 2>&1)"; rc=$?
chk "pull-only conflict --worktrees: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only conflict --worktrees: names the flag" "$out" "cannot combine with --worktrees"

out="$("$WRAP" apply --pull-only --apply --archive-unmerged "$PCFL" 2>&1)"; rc=$?
chk "pull-only conflict --archive-unmerged: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only conflict --archive-unmerged: names the flag" "$out" "cannot combine with --archive-unmerged"

out="$("$WRAP" apply --pull-only --apply --own "$PCFL" "$PCFL" 2>&1)"; rc=$?
chk "pull-only conflict --own: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only conflict --own: names the flag" "$out" "cannot combine with --own"
out="$("$WRAP" apply --pull-only --apply --own="$PCFL" "$PCFL" 2>&1)"; rc=$?
chk "pull-only conflict --own=<path>: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only conflict --own=<path>: names the flag" "$out" "cannot combine with --own"

out="$("$WRAP" apply --pull-only --apply --tips-file "$TMPD/does-not-exist-tips" "$PCFL" 2>&1)"; rc=$?
chk "pull-only conflict --tips-file: exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "pull-only conflict --tips-file: names the flag" "$out" "cannot combine with --tips-file"
chk_no "pull-only conflict --tips-file: refused for the conflict, not the missing path" "$out" \
  "is not an existing file"
chk "pull-only conflicts: no refused call pulled, though origin moved" \
  "$([ "$(git -C "$PCFL" rev-parse HEAD)" = "$PCFL_HEAD" ]; echo $?)"

echo "--- pull-only: multi-repo, each repo gets its own header and pull section"
build_pd_repo pulomulti1; advance_pd_repo pulomulti1
build_pd_repo pulomulti2; advance_pd_repo pulomulti2
PM1="$TMPD/pdclone-pulomulti1"; PM2="$TMPD/pdclone-pulomulti2"
PM1_TIP="$(git -C "$TMPD/pdbare-pulomulti1" rev-parse main)"
PM2_TIP="$(git -C "$TMPD/pdbare-pulomulti2" rev-parse main)"
out="$("$WRAP" apply --pull-only --apply "$PM1" "$PM2" 2>&1)"; rc=$?
chk "pull-only multi-repo: exits 0" "$rc"
chk_has "pull-only multi-repo: repo 1 header" "$out" "== $PM1"
chk_has "pull-only multi-repo: repo 2 header" "$out" "== $PM2"
chk "pull-only multi-repo: repo 1 pulled" "$([ "$(git -C "$PM1" rev-parse HEAD)" = "$PM1_TIP" ]; echo $?)"
chk "pull-only multi-repo: repo 2 pulled" "$([ "$(git -C "$PM2" rev-parse HEAD)" = "$PM2_TIP" ]; echo $?)"

echo "--- pull-only: a skipped pull fails the call"
build_pd_repo pulolock; advance_pd_repo pulolock
PLK="$TMPD/pdclone-pulolock"
PLK_HEAD="$(git -C "$PLK" rev-parse HEAD)"
# A fixed old mtime keeps the lock stale on any clock, so _write_guard refuses without waiting.
touch -t 200001010000 "$PLK/.git/index.lock"
out="$("$WRAP" apply --pull-only --apply "$PLK" 2>&1)"; rc=$?
chk "pull-only stale lock: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pull-only stale lock: the skipped pull is named" "$out" \
  "SKIP pull --ff-only (checkout on main): index.lock held by another writer"
chk "pull-only stale lock: HEAD unmoved" "$([ "$(git -C "$PLK" rev-parse HEAD)" = "$PLK_HEAD" ]; echo $?)"
out="$("$WRAP" apply --pull-only "$PLK" 2>&1)"; rc=$?
chk "pull-only stale lock: a dry run still exits 0 (the lock is transient)" "$rc"
out="$("$WRAP" apply --apply "$PLK" 2>&1)"; rc=$?
chk "plain apply stale lock: the same skip still exits 0" "$rc"
chk_has "plain apply stale lock: the pull was skipped the same way" "$out" "index.lock held by another writer"
rm -f "$PLK/.git/index.lock"

PNO="$TMPD/pulo-no-origin"
git init -q -b main "$PNO"; gitc "$PNO"; git -C "$PNO" commit -q --allow-empty -m "chore: root"
out="$("$WRAP" apply --pull-only --apply "$PNO" 2>&1)"; rc=$?
chk "pull-only no default branch: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "pull-only no default branch: the skip is named" "$out" "no default branch resolved"
out="$("$WRAP" apply --pull-only "$PNO" 2>&1)"; rc=$?
chk "pull-only no default branch: a dry run exits 2 too" "$([ "$rc" -eq 2 ]; echo $?)"
out="$("$WRAP" apply --apply "$PNO" 2>&1)"; rc=$?
chk "plain apply no default branch: still exits 0" "$rc"

# Regression (TASK-J): no new fixture here on purpose -- every pre-existing `apply` assertion
# above this section runs with no --pull-only in the call, so a full run of this file (not a
# --pull-only-scoped subset) is itself the regression check.


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-pull: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-pull: all $PASS passed"
