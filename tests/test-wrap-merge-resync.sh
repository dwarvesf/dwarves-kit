#!/usr/bin/env bash
# test-wrap-merge-resync.sh -- the merge head-resync cases: GitHub keeps serving the pre-push head
# after wrap's re-merge push, so merge closes and reopens its own PR once. Split from
# test-wrap-merge.sh so each half sits well under the per-suite ceiling (the section alone is ~30
# `merge --apply` runs, each with its own fixture repo).
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-merge.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

build_remerge() { # build_remerge <name> [--also-conflict]
  local name="$1" also="${2:-}" work="$TMPD/rm-work-$1" clone="$TMPD/rm-clone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  mkdir -p "$work/_meta"
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf 'base line\n' > "$work/_meta/LAB_LOG.md"
  printf 'shared\n' > "$work/a.txt"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  printf 'branch line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  [ "$also" = "--also-conflict" ] && printf 'branch side\n' > "$work/a.txt"
  git -C "$work" commit -qam "branch entry"
  git -C "$work" checkout -q main
  printf 'main line\nbase line\n' > "$work/_meta/LAB_LOG.md"
  [ "$also" = "--also-conflict" ] && printf 'main side\n' > "$work/a.txt"
  git -C "$work" commit -qam "main entry"
  git clone -q --bare "$work" "$TMPD/rm-bare-$name"
  git clone -q "$TMPD/rm-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}
open_one() { printf '[{"number":%s,"title":"log entry","headRefName":"feat/union"}]' "$1"; }


# ===========================================================================
echo "=== merge: a stale head after wrap's own push resyncs with one close and reopen ==="
# ===========================================================================
# GitHub can keep serving the pre-push head after wrap's re-merge push. When the settle
# wait ends on it and origin holds exactly the pushed commit, wrap closes and reopens its
# own PR once. Every case runs the bare form. Reads of the PR: 1 the cache loop, 2 to 4 the
# settle window (bound 4s, no-op sleep), 5 the resync's own read, 6 on the state reads.
rs_json() { # rs_json <number> <head oid> <mergeable> <mergeStateStatus> [jq edit]
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"%s","mergeStateStatus":"%s","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"state":"OPEN","isDraft":false,"isCrossRepository":false,"autoMergeRequest":null}' \
    "$1" "$2" "$3" "$4" | jq -c "${5:-.}"
}
rs_tip() { git -C "$TMPD/rm-bare-$1" rev-parse feat/union; }
rs_count() { grep -c -- "$1" "$GH_STUB_CALLS" || true; }
rs_reads() { cat "$GH_STUB_CALLS.view-$1" 2>/dev/null || echo 0; }
RS_PIDF="$TMPD/rs-wrap.pid"; RS_ERRF="$TMPD/rs-wrap.err"
RS_FLAGS=""  # extra merge flags for one case, e.g. "--pr 116"; reset after every run
rs_merge() { # rs_merge <n> <name> [VAR=value ...] -- later VAR=value pairs win
  local n="$1" name="$2" stale; shift 2
  stale="$(rs_json "$n" "$(rs_tip "$name")" CONFLICTING DIRTY)"
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  # stdout and stderr are kept apart so a case can check which stream a line went to.
  # shellcheck disable=SC2086
  RS_STDOUT="$(env PATH="$TMPD/nosleep:$PATH" KIT_WRAP_SETTLE_SECS=4 \
    GH_STUB_OPEN_PRS="$(open_one "$n")" "GH_STUB_PR_${n}=${stale}" "GH_STUB_PR_${n}_2=${stale}" \
    GH_STUB_LAND_REPO="$TMPD/rm-clone-$name" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-$name" \
    GH_STUB_LAND_BRANCH=feat/union GH_STUB_KILL_PIDFILE="$RS_PIDF" "$@" \
    sh -c 'echo $$ > "$0"; exec "$@"' "$RS_PIDF" "$WRAP" merge --apply $RS_FLAGS "$TMPD/rm-clone-$name" 2>"$RS_ERRF")"
  RS_RC=$?
  RS_ERR="$(cat "$RS_ERRF")"
  RS_OUT="${RS_STDOUT}
${RS_ERR}"
  RS_FLAGS=""
}
rs_merged() { # rs_merged <n> <name> -- merged, tree verified, pinned to the pushed head
  local pushed; pushed="$(git -C "$TMPD/rm-clone-$2" rev-parse feat/union)"
  chk "resync #$1: exits 0" "$RS_RC"
  chk_has "resync #$1: merged, tree verified" "$RS_OUT" "merged #$1 ($(git -C "$TMPD/rm-bare-$2" rev-parse main)): tree verified"
  chk "resync #$1: merge pinned to the pushed head" \
    "$(grep -q -- "^pr merge $1 .*--match-head-commit ${pushed}" "$GH_STUB_CALLS"; echo $?)"
}
rs_untouched() { # rs_untouched <n> [expected exit, default 0] -- no close, no reopen, no merge
  chk "resync #$1: exits ${2:-0}" "$([ "$RS_RC" -eq "${2:-0}" ]; echo $?)"
  chk "resync #$1: no pr close" "$([ "$(rs_count "^pr close $1")" -eq 0 ]; echo $?)"
  chk "resync #$1: no pr reopen" "$([ "$(rs_count "^pr reopen $1")" -eq 0 ]; echo $?)"
  chk "resync #$1: no pr merge" "$([ "$(rs_count "^pr merge")" -eq 0 ]; echo $?)"
}

echo "--- resync: a stale head is closed and reopened once, then merged"
build_remerge rs90; T="$(rs_tip rs90)"
rs_merge 90 rs90 GH_STUB_PR_90_REOPENED="$(rs_json 90 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 90 rs90
chk_has "resync #90: names the resync" "$RS_OUT" "#90 still shows head $(printf '%s' "$T" | cut -c1-7) after the push of"
chk_has "resync #90: reports it" "$RS_OUT" "resynced #90: closed and reopened"
chk_has "resync #90: eligible after the re-merge" "$RS_OUT" "eligible #90 after the re-merge"
chk "resync #90: one close" "$([ "$(rs_count '^pr close 90')" -eq 1 ]; echo $?)"
chk "resync #90: one reopen" "$([ "$(rs_count '^pr reopen 90')" -eq 1 ]; echo $?)"
chk "resync #90: one comment" "$([ "$(rs_count '^pr comment 90')" -eq 1 ]; echo $?)"
chk "resync #90: the close comes before the reopen" \
  "$([ "$(grep -n '^pr close 90' "$GH_STUB_CALLS" | cut -d: -f1)" -lt "$(grep -n '^pr reopen 90' "$GH_STUB_CALLS" | cut -d: -f1)" ]; echo $?)"
chk "resync #90: the close carries no --comment, -d or --delete-branch" \
  "$(grep '^pr close 90' "$GH_STUB_CALLS" | grep -qE -- '--comment|--delete-branch|(^| )-d( |$)' && echo 1 || echo 0)"
chk_no "resync #90: the comment carries no branch name" "$(grep '^pr comment 90' "$GH_STUB_CALLS")" "feat/union"

echo "--- resync: GitHub caught up before the close, so no close runs"
build_remerge rs96
rs_merge 96 rs96 GH_STUB_PR_96_5="$(rs_json 96 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 96 rs96
chk_has "resync #96: caught up on its own" "$RS_OUT" "#96 caught up on its own; no resync needed"
chk "resync #96: no pr close" "$([ "$(rs_count '^pr close 96')" -eq 0 ]; echo $?)"
chk_no "resync #96: no still-stale text" "$RS_OUT" "still stale"

echo "--- resync: a refusing step 1 read never closes"
build_remerge rs92; T="$(rs_tip rs92)"
rs_merge 92 rs92 GH_STUB_PR_92_5="$(rs_json 92 "$T" CONFLICTING DIRTY '.isDraft = true')"
rs_untouched 92
chk_has "resync #92: a draft is named" "$RS_OUT" "no resync for #92: isDraft is not false"
chk_has "resync #92: the existing SKIP stands" "$RS_OUT" "SKIP #92 after the re-merge: head is"
build_remerge rs93; T="$(rs_tip rs93)"
rs_merge 93 rs93 GH_STUB_PR_93_5="$(rs_json 93 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
rs_untouched 93
chk_has "resync #93: a closed PR is named" "$RS_OUT" "no resync for #93: state CLOSED"
build_remerge rs102; T="$(rs_tip rs102)"
rs_merge 102 rs102 GH_STUB_PR_102_5="$(rs_json 102 "$T" CONFLICTING DIRTY '.autoMergeRequest = {"mergeMethod":"SQUASH"}')"
rs_untouched 102
chk_has "resync #102: armed auto-merge is named" "$RS_OUT" "no resync for #102: auto-merge armed or unreadable"
build_remerge rs105; T="$(rs_tip rs105)"
rs_merge 105 rs105 GH_STUB_PR_105_5="$(rs_json 105 "$T" CONFLICTING DIRTY 'del(.state)')"
rs_untouched 105
chk_has "resync #105: a missing state fails closed" "$RS_OUT" "no resync for #105: state unreadable"
build_remerge rs106; T="$(rs_tip rs106)"
rs_merge 106 rs106 GH_STUB_PR_106_5="$(rs_json 106 "$T" CONFLICTING DIRTY 'del(.isDraft)')"
rs_untouched 106
chk_has "resync #106: a missing isDraft fails closed" "$RS_OUT" "no resync for #106: isDraft is not false"
build_remerge rs107; T="$(rs_tip rs107)"
rs_merge 107 rs107 GH_STUB_PR_107_5="$(rs_json 107 "$T" CONFLICTING DIRTY 'del(.autoMergeRequest)')"
rs_untouched 107
chk_has "resync #107: a missing autoMergeRequest fails closed" "$RS_OUT" "no resync for #107: auto-merge armed or unreadable"

echo "--- resync: origin moved past the pushed commit, so no close"
build_remerge rs91
mkdir -p "$TMPD/rm-bare-rs91/hooks"
cat > "$TMPD/rm-bare-rs91/hooks/post-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
  [ "$ref" = refs/heads/feat/union ] || continue
  c="$(GIT_AUTHOR_NAME=f GIT_AUTHOR_EMAIL=f@f GIT_COMMITTER_NAME=f GIT_COMMITTER_EMAIL=f@f \
    git commit-tree "${new}^{tree}" -p "$new" -m foreign)"
  git update-ref refs/heads/feat/union "$c"
done
HOOK
chmod +x "$TMPD/rm-bare-rs91/hooks/post-receive"
rs_merge 91 rs91
rs_untouched 91
chk_has "resync #91: a foreign origin tip is named" "$RS_OUT" "no resync for #91: origin tip is"

echo "--- resync: open dependents skip the resync (bare form only)"
build_remerge rs98
rs_merge 98 rs98 \
  GH_STUB_OPEN_PRS='[{"number":98,"title":"log entry","headRefName":"feat/union"},{"number":99,"title":"stacked","headRefName":"feat/child"}]' \
  GH_STUB_PR_99='{"number":99,"title":"stacked","headRefName":"feat/child","headRefOid":"aa","baseRefName":"feat/union","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}'
rs_untouched 98
chk_has "resync #98: dependents are named" "$RS_OUT" "no resync for #98: dependents open"
chk_has "resync #98: the dependent itself is not eligible" "$RS_OUT" "SKIP #99 stacked: base is feat/union"

echo "--- resync: a decoy ref that tail-matches the branch does not fool the origin check"
build_remerge rs103
git -C "$TMPD/rm-bare-rs103" update-ref refs/heads/a/refs/heads/feat/union "$(rs_tip rs103)"
rs_merge 103 rs103 GH_STUB_PR_103_REOPENED="$(rs_json 103 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 103 rs103
chk "resync #103: one close" "$([ "$(rs_count '^pr close 103')" -eq 1 ]; echo $?)"

echo "--- resync: two failed reopens exit 2 and name the reopen command"
build_remerge rs94
rs_merge 94 rs94 GH_STUB_REOPEN_RC=1
chk "resync #94: exits 2" "$([ "$RS_RC" -eq 2 ]; echo $?)"
chk_has "resync #94: names the reopen command" "$RS_OUT" \
  "FAILED merge #94: closed #94 to resync its head, and the reopen failed; reopen it: gh pr reopen 94 --repo"
chk_has "resync #94: names the re-push step" "$RS_OUT" "(if origin lost feat/union, push it at"
chk "resync #94: two reopens" "$([ "$(rs_count '^pr reopen 94')" -eq 2 ]; echo $?)"
chk "resync #94: one comment saying the reopen failed" \
  "$([ "$(grep '^pr comment 94' "$GH_STUB_CALLS" | grep -c 'the reopen failed')" -eq 1 ]; echo $?)"
chk_no "resync #94: the comment carries no branch name" "$(grep '^pr comment 94' "$GH_STUB_CALLS")" "feat/union"
chk "resync #94: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"

echo "--- resync: one failed reopen, then the retry succeeds"
build_remerge rs95
rs_merge 95 rs95 GH_STUB_REOPEN_FAILS=1 GH_STUB_PR_95_REOPENED="$(rs_json 95 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 95 rs95
chk "resync #95: two reopens" "$([ "$(rs_count '^pr reopen 95')" -eq 2 ]; echo $?)"

echo "--- resync: a failed close is judged by state, fail closed"
build_remerge rs100; T="$(rs_tip rs100)"
rs_merge 100 rs100 GH_STUB_CLOSE_RC=1 GH_STUB_PR_100_6="$(rs_json 100 "$T" CONFLICTING DIRTY)"
chk "resync #100: exits 0" "$RS_RC"
chk "resync #100: no reopen" "$([ "$(rs_count '^pr reopen 100')" -eq 0 ]; echo $?)"
chk_has "resync #100: an open PR after a failed close is named" "$RS_OUT" "no resync for #100: close failed and #100 is still open"
chk_has "resync #100: the existing SKIP stands" "$RS_OUT" "SKIP #100 after the re-merge: head is"
build_remerge rs101
rs_merge 101 rs101 GH_STUB_CLOSE_RC=1 GH_STUB_PR_101_6='{}'
chk "resync #101: exits 2" "$([ "$RS_RC" -eq 2 ]; echo $?)"
chk_has "resync #101: names the unreadable close on stderr" "$RS_ERR" \
  "FAILED merge #101: close #101 errored and its state is unreadable; if it is closed: gh pr reopen 101 --repo"
chk_no "resync #101: the FAILED line is not on stdout" "$RS_STDOUT" "FAILED merge #101"
chk "resync #101: three state reads, no more" "$([ "$(rs_reads 101)" -eq 8 ]; echo $?)"
chk "resync #101: no reopen" "$([ "$(rs_count '^pr reopen 101')" -eq 0 ]; echo $?)"
chk "resync #101: no comment" "$([ "$(rs_count '^pr comment 101')" -eq 0 ]; echo $?)"
chk "resync #101: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"
build_remerge rs108; T="$(rs_tip rs108)"
rs_merge 108 rs108 GH_STUB_CLOSE_RC=1 GH_STUB_PR_108_6='{}' \
  GH_STUB_PR_108_7="$(rs_json 108 "$T" CONFLICTING DIRTY '.state = "CLOSED"')" \
  GH_STUB_PR_108_REOPENED="$(rs_json 108 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 108 rs108
chk "resync #108: one reopen after the CLOSED read" "$([ "$(rs_count '^pr reopen 108')" -eq 1 ]; echo $?)"

echo "--- resync: still stale after the reopen, one pair only and the next steps named"
build_remerge rs97
rs_merge 97 rs97
chk "resync #97: exits 0" "$RS_RC"
chk "resync #97: one close" "$([ "$(rs_count '^pr close 97')" -eq 1 ]; echo $?)"
chk "resync #97: one reopen" "$([ "$(rs_count '^pr reopen 97')" -eq 1 ]; echo $?)"
chk_has "resync #97: names the wait" "$RS_OUT" \
  "still stale after a close and reopen; wait until gh pr view 97 --json headRefOid shows"
chk_has "resync #97: names the manual close and reopen" "$RS_OUT" "gh pr close 97 && gh pr reopen 97"
chk "resync #97: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"

echo "--- resync: an interrupt inside the close window reopens and exits 130"
build_remerge rs104; T="$(rs_tip rs104)"
rs_merge 104 rs104 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_104_6="$(rs_json 104 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #104: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #104: prints the recovery command on stderr" "$RS_ERR" \
  "INTERRUPTED inside the resync of #104; if #104 is closed, reopen it: gh pr reopen 104 --repo"
chk_has "resync #104: reports the reopen" "$RS_OUT" "reopened #104 after the interrupt"
chk "resync #104: one reopen" "$([ "$(rs_count '^pr reopen 104')" -eq 1 ]; echo $?)"
chk "resync #104: no pr merge" "$([ "$(rs_count '^pr merge')" -eq 0 ]; echo $?)"
build_remerge rs109; T="$(rs_tip rs109)"
rs_merge 109 rs109 GH_STUB_CLOSE_KILL=1 GH_STUB_CLOSE_RC=1 \
  GH_STUB_PR_109_6="$(rs_json 109 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #109: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #109: reports the reopen" "$RS_OUT" "reopened #109 after the interrupt"
chk "resync #109: one reopen" "$([ "$(rs_count '^pr reopen 109')" -eq 1 ]; echo $?)"
chk "resync #109: the handler's read is the last one (6 reads)" "$([ "$(rs_reads 109)" -eq 6 ]; echo $?)"

echo "--- resync: an interrupt before the close stops the run with the PR untouched"
build_remerge rs110
rs_merge 110 rs110 GH_STUB_VIEW_KILL_110_5=1
chk_has "resync #110: says nothing changed" "$RS_OUT" \
  "INTERRUPTED inside the resync of #110 before the close; nothing changed on GitHub"
rs_untouched 110 130

echo "--- resync: the handler acts only on exactly CLOSED"
build_remerge rs111; T="$(rs_tip rs111)"
rs_merge 111 rs111 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_111_6="$(rs_json 111 "$T" CONFLICTING DIRTY)"
chk "resync #111: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #111: an open PR is left alone" "$RS_ERR" "#111 is still open after the interrupt; nothing to undo"
chk "resync #111: no reopen" "$([ "$(rs_count '^pr reopen 111')" -eq 0 ]; echo $?)"
build_remerge rs112
rs_merge 112 rs112 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_112_6='{}'
chk "resync #112: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #112: an unreadable state is reported" "$RS_ERR" \
  "#112 state reads 'unreadable' after the interrupt, so no reopen was tried; check it: gh pr view 112 --repo"
chk "resync #112: no reopen" "$([ "$(rs_count '^pr reopen 112')" -eq 0 ]; echo $?)"
build_remerge rs113; T="$(rs_tip rs113)"
rs_merge 113 rs113 GH_STUB_CLOSE_KILL=1 GH_STUB_REOPEN_RC=1 \
  GH_STUB_PR_113_6="$(rs_json 113 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #113: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #113: a failed reopen names the command" "$RS_ERR" \
  "could not reopen #113 after the interrupt; reopen it: gh pr reopen 113 --repo"
chk "resync #113: the handler and the wrapper each try once (2 reopens)" \
  "$([ "$(rs_count '^pr reopen 113')" -eq 2 ]; echo $?)"

echo "--- resync: the handler read OPEN before the close landed; one more read reopens it"
build_remerge rs117; T="$(rs_tip rs117)"
rs_merge 117 rs117 GH_STUB_CLOSE_KILL=1 GH_STUB_PR_117_6="$(rs_json 117 "$T" CONFLICTING DIRTY)" \
  GH_STUB_PR_117_7="$(rs_json 117 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #117: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #117: the late read reopens" "$RS_ERR" "reopened #117 after the interrupt"
chk "resync #117: one reopen" "$([ "$(rs_count '^pr reopen 117')" -eq 1 ]; echo $?)"

echo "--- resync: an interrupt during a failed close's state reads"
build_remerge rs115; T="$(rs_tip rs115)"
rs_merge 115 rs115 GH_STUB_CLOSE_RC=1 GH_STUB_VIEW_KILL_115_6=1 GH_STUB_PR_115_6='{}' \
  GH_STUB_PR_115_7="$(rs_json 115 "$T" CONFLICTING DIRTY '.state = "CLOSED"')"
chk "resync #115: exits 130" "$([ "$RS_RC" -eq 130 ]; echo $?)"
chk_has "resync #115: the handler reopens" "$RS_ERR" "reopened #115 after the interrupt"
chk "resync #115: one reopen" "$([ "$(rs_count '^pr reopen 115')" -eq 1 ]; echo $?)"

echo "--- resync: a failed comment never fails the merge"
build_remerge rs114
rs_merge 114 rs114 GH_STUB_COMMENT_RC=1 GH_STUB_PR_114_REOPENED="$(rs_json 114 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 114 rs114
chk_has "resync #114: names the failed comment" "$RS_OUT" "comment on #114 failed; the resync itself is unaffected"

echo "--- resync: the --pr form resyncs the same way"
build_remerge rs116
RS_FLAGS="--pr 116"
rs_merge 116 rs116 GH_STUB_PR_116_REOPENED="$(rs_json 116 %REMERGE_TIP% MERGEABLE CLEAN)"
rs_merged 116 rs116
chk "resync #116: one close" "$([ "$(rs_count '^pr close 116')" -eq 1 ]; echo $?)"

echo "--- resync: a moved, unreadable or fork head at step 1 never closes"
build_remerge rs118
rs_merge 118 rs118 GH_STUB_PR_118_5="$(rs_json 118 4444444444444444444444444444444444444444 CONFLICTING DIRTY)"
rs_untouched 118
chk_has "resync #118: a moved head is named" "$RS_OUT" "no resync for #118: head moved to 4444444"
build_remerge rs119
rs_merge 119 rs119 GH_STUB_FAIL_VIEW_119_5=1
rs_untouched 119
chk_has "resync #119: a failed read is named" "$RS_OUT" "no resync for #119: unreadable PR state"
build_remerge rs121; T="$(rs_tip rs121)"
rs_merge 121 rs121 GH_STUB_PR_121_5="$(rs_json 121 "$T" CONFLICTING DIRTY '.isCrossRepository = true')"
rs_untouched 121
chk_has "resync #121: a fork PR is named" "$RS_OUT" "no resync for #121: a fork PR or unreadable"

echo "--- resync: origin lost the branch after the push"
build_remerge rs122
mkdir -p "$TMPD/rm-bare-rs122/hooks"
cat > "$TMPD/rm-bare-rs122/hooks/post-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
  [ "$ref" = refs/heads/feat/union ] && git update-ref -d refs/heads/feat/union
done
HOOK
chmod +x "$TMPD/rm-bare-rs122/hooks/post-receive"
rs_merge 122 rs122
rs_untouched 122
chk_has "resync #122: a missing origin ref is named" "$RS_OUT" "no resync for #122: origin ref is ambiguous or missing"

echo "--- resync: the helper restores the caller's traps, resets its flag, and strips userinfo"
cat > "$TMPD/rs-unit.sh" <<'UNIT'
source "$1/lib/wrap/wrap-common.sh"
source "$1/lib/wrap/wrap-merge.sh"
trap 'echo caller-term' TERM
int_before="$(trap -p INT)"
_RS_HIT=1
_pr_head_resync /nonexistent https://example.invalid/o/r 120 feat/x \
  1111111111111111111111111111111111111111 2222222222222222222222222222222222222222 >/dev/null
echo "rc=$?"
echo "term=$(trap -p TERM)"
[ "$(trap -p INT)" = "$int_before" ] && echo "int=unchanged" || echo "int=changed"
echo "pub1=$(_url_public 'https://u:p@ss@host.example/o/r.git')"
echo "pub2=$(_url_public 'git@github.com:o/r.git')"
echo "pub3=$(_url_public 'https://github.com/o/r')"
UNIT
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_PR_120="$(rs_json 120 2222222222222222222222222222222222222222 MERGEABLE CLEAN)" \
  bash "$TMPD/rs-unit.sh" "$KIT_DIR" 2>&1)"
chk_has "resync unit: a stale flag from an earlier run is reset (caught up, rc 3)" "$out" "rc=3"
chk_has "resync unit: the caller's TERM trap is back" "$out" "term=trap -- 'echo caller-term'"
chk_has "resync unit: the caller's INT disposition is back" "$out" "int=unchanged"
chk_no "resync unit: no INT trap remains" "$out" "_resync_trap"
chk_has "resync unit: userinfo is stripped, a raw @ in the password too" "$out" "pub1=https://host.example/o/r.git"
chk_has "resync unit: an scp-style URL is unchanged" "$out" "pub2=git@github.com:o/r.git"
chk_has "resync unit: a plain URL is unchanged" "$out" "pub3=https://github.com/o/r"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-merge-resync: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-merge-resync: all $PASS passed"
