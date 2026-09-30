#!/usr/bin/env bash
# test-wrap-land.sh -- the land cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# ===========================================================================
echo "=== land: one hand-made worktree, from a committed branch to landed ==="
# ===========================================================================
# Real git throughout, `gh` stubbed: the push, the fast-forward, the worktree removal and
# the branch delete are the subject, so nothing about the tree state is faked.
echo "--- happy path: pushed, PR opened with --head, merged alone, pulled, tidied"
build_land ok
LREPO="$TMPD/ld-repo-ok"; LREPO_P="$(cd "$LREPO" && pwd -P)"; LWT="$(cd "$LREPO/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ok" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "land exits 0 on the happy path" "$rc"
chk_has "land reports the push with the tip" "$out" "pushed feat/land (${LTIP:0:7})"
chk_has "land opened the PR with --head" "$LAND_CALLS" "pr create --repo"
chk_has "the create call names the branch as head" "$LAND_CALLS" "--head feat/land"
chk_no "the create call never names a base" "$LAND_CALLS" "--base"
chk_has "land reports the PR number" "$out" "opened PR #42"
chk "land ran the squash merge as its own call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk_has "the merge call is a squash" "$LAND_CALLS" "pr merge 42 --repo"
chk_has "the merge call pins the pushed head" "$LAND_CALLS" "--squash --match-head-commit ${LTIP}"
chk_has "land verifies the default branch holds the PR head" "$out" "merged #42 ($(git -C "$TMPD/ld-bare-ok" rev-parse main)): tree verified"
chk "land fast-forwarded the main checkout onto the landed tree" \
  "$([ "$(git -C "$LREPO" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk_has "land reports the pull" "$out" "pulled ${LREPO_P}"
chk "land removed the worktree" "$([ ! -e "$LWT" ]; echo $?)"
chk "land dropped the worktree from the list" \
  "$(git -C "$LREPO" worktree list --porcelain | grep -qxF "worktree $LWT" && echo 1 || echo 0)"
chk "land deleted the local branch" \
  "$(git -C "$LREPO" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk_has "land reports the delete" "$out" "deleted feat/land"
chk "land deleted the branch on origin too" \
  "$(git -C "$TMPD/ld-bare-ok" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk_has "land reports the origin delete" "$out" "deleted feat/land on origin"

# ===========================================================================
echo "=== land: no-flag title picks the feature commit, not the tip (SPEC-326) ==="
# ===========================================================================
echo "--- feature commit in the middle: the doc bookends are skipped"
build_land title-mid "" feat/land "docs(spec): reserve" "fix(x): the real change" "docs(x): proof"
LWT_TM="$(cd "$TMPD/ld-repo-title-mid/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
GH_QUOTED_MID="$TMPD/gh-calls-quoted-mid.log"; : > "$GH_QUOTED_MID"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=70 GH_STUB_LAND_REPO="$LWT_TM" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-mid" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main GH_STUB_CALLS_QUOTED="$GH_QUOTED_MID" \
  "$WRAP" land "$LWT_TM" 2>&1)"; rc=$?
chk "title-mid: land exits 0" "$rc"
chk_has "title-mid: the create call titles from the feature commit" "$(cat "$GH_STUB_CALLS")" \
  "--title fix(x): the real change"
chk_no "title-mid: the tip's docs subject is never the title" "$(cat "$GH_STUB_CALLS")" \
  "--title docs(x): proof"
chk_has "title-mid: the title landed as ONE argv entry, not word-split" "$(cat "$GH_QUOTED_MID")" \
  "<--title><fix(x): the real change>"

echo "--- feature commit first: it is also the only non-housekeeping one"
build_land title-first "" feat/land "fix(x): the real change" "docs(x): proof and changelog"
LWT_TF="$(cd "$TMPD/ld-repo-title-first/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=71 GH_STUB_LAND_REPO="$LWT_TF" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-first" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TF" 2>&1)"; rc=$?
chk "title-first: land exits 0" "$rc"
chk_has "title-first: titled from the first, non-housekeeping commit" "$(cat "$GH_STUB_CALLS")" \
  "--title fix(x): the real change"

echo "--- the #771 shape: a later same-type commit never outranks the original (proves --reverse)"
build_land title-771 "" feat/land "docs(spec): r" "feat(x): the change" "fix(x): review follow-up"
LWT_771="$(cd "$TMPD/ld-repo-title-771/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=90 GH_STUB_LAND_REPO="$LWT_771" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-771" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_771" 2>&1)"; rc=$?
chk "title-771: land exits 0" "$rc"
chk_has "title-771: titled from the original feature commit, oldest first" "$(cat "$GH_STUB_CALLS")" \
  "--title feat(x): the change"
chk_no "title-771: the later review-followup commit is never the title" "$(cat "$GH_STUB_CALLS")" \
  "--title fix(x): review follow-up"

echo "--- every commit ahead is housekeeping: falls back to the OLDEST, never the tip"
build_land title-hk "" feat/land "docs(x): a" "chore(x): b" "test(x): c" "docs!: d"
LWT_HK="$(cd "$TMPD/ld-repo-title-hk/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=72 GH_STUB_LAND_REPO="$LWT_HK" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-hk" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_HK" 2>&1)"; rc=$?
chk "title-hk: land exits 0" "$rc"
chk_has "title-hk: falls back to the oldest commit ahead" "$(cat "$GH_STUB_CALLS")" "--title docs(x): a"
chk_no "title-hk: never the newest housekeeping commit" "$(cat "$GH_STUB_CALLS")" "--title chore(x): b"
chk_no "title-hk: a test-type housekeeping commit is never picked either" "$(cat "$GH_STUB_CALLS")" "--title test(x): c"
chk_no "title-hk: a bare-bang docs subject is never picked either" "$(cat "$GH_STUB_CALLS")" "--title docs!: d"

echo "--- a non-conventional subject counts as the feature, never treated as housekeeping"
build_land title-wip "" feat/land "docs(x): a" "wip stuff"
LWT_WIP="$(cd "$TMPD/ld-repo-title-wip/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=73 GH_STUB_LAND_REPO="$LWT_WIP" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-wip" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_WIP" 2>&1)"; rc=$?
chk "title-wip: land exits 0" "$rc"
chk_has "title-wip: the non-conventional subject is picked" "$(cat "$GH_STUB_CALLS")" "--title wip stuff"

echo "--- an explicit --title still wins over a multi-commit branch's feature commit"
build_land title-flag "" feat/land "docs(spec): reserve" "fix(x): the real change"
LWT_TFL="$(cd "$TMPD/ld-repo-title-flag/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=74 GH_STUB_LAND_REPO="$LWT_TFL" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-flag" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TFL" --title "custom title" 2>&1)"; rc=$?
chk "title-flag: land exits 0" "$rc"
chk_has "title-flag: the explicit title wins" "$(cat "$GH_STUB_CALLS")" "--title custom title"
chk_no "title-flag: the walk's own pick never surfaces" "$(cat "$GH_STUB_CALLS")" "--title fix(x): the real change"

echo "--- an adopted PR on a multi-commit branch keeps its own title, no create call at all"
build_land title-adopt "" feat/land "docs(spec): reserve" "fix(x): the real change"
LWT_TA="$(cd "$TMPD/ld-repo-title-adopt/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land='[{"number":75,"baseRefName":"main","author":{"login":"me"},"isDraft":false,"isCrossRepository":false}]' \
  GH_STUB_LAND_REPO="$LWT_TA" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-adopt" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TA" 2>&1)"; rc=$?
chk "title-adopt: land exits 0" "$rc"
chk_has "title-adopt: adopted, not created" "$out" "adopted PR #75"
chk_no "title-adopt: never calls pr create" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- --no-merges on the WALK: a housekeeping own commit lets a later merge subject through unless excluded"
build_land title-mrg "" feat/land "docs(x): only"
LREPO_MRG="$TMPD/ld-repo-title-mrg"; LWT_MRG="$(cd "$LREPO_MRG/wt" && pwd -P)"
BARE_MRG="$TMPD/ld-bare-title-mrg"
# Advance the bare remote's main first, so the merge below is a real, two-parent merge and
# not a no-op fast-forward the branch already contained. The branch's OWN commit is
# housekeeping on purpose: the walk must skip it and reach the merge commit next, which is
# exactly the point where --no-merges either excludes it (correct) or lets it through (bug).
CLONE_MRG="$TMPD/ld-clone-title-mrg-advance"
git clone -q "$BARE_MRG" "$CLONE_MRG"; gitc "$CLONE_MRG"
echo "remote moved on" >> "$CLONE_MRG/base.txt"
git -C "$CLONE_MRG" add -A; git -C "$CLONE_MRG" commit -qm "docs(x): remote advanced"
git -C "$CLONE_MRG" push -q origin main
git -C "$LWT_MRG" fetch -q origin main
git -C "$LWT_MRG" merge -q --no-edit origin/main
chk "title-mrg: fixture precondition, exactly one real merge commit ahead" \
  "$([ "$(git -C "$LWT_MRG" rev-list --merges --count origin/main..HEAD)" = "1" ]; echo $?)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=76 GH_STUB_LAND_REPO="$LWT_MRG" GH_STUB_LAND_REMOTE="$BARE_MRG" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_MRG" 2>&1)"; rc=$?
chk "title-mrg: land exits 0" "$rc"
chk_has "title-mrg: falls back to the own housekeeping commit, never the merge" "$(cat "$GH_STUB_CALLS")" \
  "--title docs(x): only"
chk_no "title-mrg: the merge commit's own subject is never the title" "$(cat "$GH_STUB_CALLS")" "--title Merge"

echo "--- --no-merges on the FALLBACK: a merge before any own commit never surfaces the merge subject"
FBWORK="$TMPD/ld-work-title-mrgfb"; FBREPO="$TMPD/ld-repo-title-mrgfb"; FBBARE="$TMPD/ld-bare-title-mrgfb"
mkdir -p "$FBWORK"; git -C "$FBWORK" init -q; gitc "$FBWORK"
git -C "$FBWORK" symbolic-ref HEAD refs/heads/main
echo base > "$FBWORK/base.txt"; git -C "$FBWORK" add -A; git -C "$FBWORK" commit -qm base
git clone -q --bare "$FBWORK" "$FBBARE"
git clone -q "$FBBARE" "$FBREPO"; gitc "$FBREPO"
git -C "$FBREPO" remote set-head origin main >/dev/null 2>&1
git -C "$FBREPO" worktree add -q -b feat/land "$FBREPO/wt" main >/dev/null 2>&1
LWT_MRGFB="$(cd "$FBREPO/wt" && pwd -P)"
# The branch owns NO commit yet when it merges: origin/main advances first, the branch
# merges it in with --no-ff (a real merge, not a fast-forward), and only THEN commits its own
# housekeeping change. The walk finds nothing (its own commit is housekeeping, the merge is
# excluded), so this exercises the FALLBACK's own --no-merges, not the walk's.
FBCLONE="$TMPD/ld-clone-title-mrgfb-advance"
git clone -q "$FBBARE" "$FBCLONE"; gitc "$FBCLONE"
echo "remote moved on" >> "$FBCLONE/base.txt"
git -C "$FBCLONE" add -A; git -C "$FBCLONE" commit -qm "docs(x): remote advanced"
git -C "$FBCLONE" push -q origin main
git -C "$LWT_MRGFB" fetch -q origin main
git -C "$LWT_MRGFB" merge -q --no-ff --no-edit origin/main
echo "own file" > "$LWT_MRGFB/own.txt"
git -C "$LWT_MRGFB" add -A; git -C "$LWT_MRGFB" commit -qm "docs(x): a"
chk "title-mrgfb: fixture precondition, a real merge landed before any own commit" \
  "$([ "$(git -C "$LWT_MRGFB" rev-list --merges --count origin/main..HEAD)" = "1" ]; echo $?)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=91 GH_STUB_LAND_REPO="$LWT_MRGFB" GH_STUB_LAND_REMOTE="$FBBARE" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_MRGFB" 2>&1)"; rc=$?
chk "title-mrgfb: land exits 0" "$rc"
chk_has "title-mrgfb: the fallback picks the own housekeeping commit" "$(cat "$GH_STUB_CALLS")" "--title docs(x): a"
chk_no "title-mrgfb: the merge commit's own subject is never the fallback pick" "$(cat "$GH_STUB_CALLS")" \
  "--title Merge"

echo "--- --topo-order: a merged-in side commit with an older date never outranks the branch's own"
build_land title-topo "" feat/land "feat(x): the main change"
LREPO_TOPO="$TMPD/ld-repo-title-topo"; LWT_TOPO="$(cd "$LREPO_TOPO/wt" && pwd -P)"
git -C "$LWT_TOPO" checkout -q -b side-topo main
echo "side file" > "$LWT_TOPO/side-topo.txt"
git -C "$LWT_TOPO" add -A
GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" \
  git -C "$LWT_TOPO" commit -qm "feat(y): the backdated side change"
git -C "$LWT_TOPO" checkout -q feat/land
git -C "$LWT_TOPO" merge -q --no-ff --no-edit side-topo
chk "title-topo: fixture precondition, the backdated side commit is really merged in" \
  "$(git -C "$LWT_TOPO" merge-base --is-ancestor side-topo feat/land 2>/dev/null; echo $?)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=92 GH_STUB_LAND_REPO="$LWT_TOPO" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-title-topo" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TOPO" 2>&1)"; rc=$?
chk "title-topo: land exits 0" "$rc"
chk_has "title-topo: the branch's own commit wins over the backdated side commit" "$(cat "$GH_STUB_CALLS")" \
  "--title feat(x): the main change"
chk_no "title-topo: the backdated side commit is never the title" "$(cat "$GH_STUB_CALLS")" \
  "--title feat(y): the backdated side change"

echo "--- the usage text and the command doc name the verb"
chk_has "wrap --help names land" "$("$WRAP" --help 2>&1)" "wrap.sh land  <worktree>"
chk_has "commands/wrap.md names land for a hand-made worktree" "$(cat "$KIT_DIR/commands/wrap.md")" \
  "bin/wrap land <worktree>"

echo "--- ship-gate record: a rid with a prior ledger gets the Ship gate recorded"
build_land shiprec "" feat/shiprec
LWT_SR="$(cd "$TMPD/ld-repo-shiprec/wt" && pwd -P)"
bash "$GATE_LEDGER" record shiprec spec ran "spec cycle for the land test" >/dev/null
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=61 GH_STUB_LAND_REPO="$LWT_SR" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-shiprec" \
  GH_STUB_LAND_BRANCH=feat/shiprec GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_SR" 2>&1)"; rc=$?
chk "ship-gate record: land still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "ship-gate record: land reports the record" "$out" "recorded ship gate for shiprec (pr=#61)"
chk_has "ship-gate record: the ledger gained the Ship line" \
  "$(cat "$KIT_LEDGER_DIR/runs/shiprec.log")" "| GATE | ship | ran | shipping pr=#61"

echo "--- ship-gate record: a rid with no prior ledger writes nothing"
build_land noship "" feat/noship
LWT_NS="$(cd "$TMPD/ld-repo-noship/wt" && pwd -P)"
[ ! -f "$KIT_LEDGER_DIR/runs/noship.log" ] || rm -f "$KIT_LEDGER_DIR/runs/noship.log"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=62 GH_STUB_LAND_REPO="$LWT_NS" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-noship" \
  GH_STUB_LAND_BRANCH=feat/noship GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_NS" 2>&1)"; rc=$?
chk "ship-gate record: no-prior-ledger land still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "ship-gate record: no-prior-ledger land reports no record" "$out" "recorded ship gate"
chk_no "ship-gate record: no-prior-ledger land reports no failure" "$out" "ship-gate record FAILED"
chk "ship-gate record: no-prior-ledger land created no ledger file" \
  "$([ ! -f "$KIT_LEDGER_DIR/runs/noship.log" ]; echo $?)"

echo "--- ship-gate record: a record failure never fails the land"
build_land shipfail "" feat/shipfail
LWT_SF="$(cd "$TMPD/ld-repo-shipfail/wt" && pwd -P)"
bash "$GATE_LEDGER" record shipfail spec ran "spec cycle for the land test" >/dev/null
chmod 444 "$KIT_LEDGER_DIR/runs/shipfail.log"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=63 GH_STUB_LAND_REPO="$LWT_SF" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-shipfail" \
  GH_STUB_LAND_BRANCH=feat/shipfail GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_SF" 2>&1)"; rc=$?
chmod 644 "$KIT_LEDGER_DIR/runs/shipfail.log" 2>/dev/null || true
chk "ship-gate record: a record failure still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "ship-gate record: a record failure names the rid and PR" "$out" \
  "ship-gate record FAILED for shipfail (pr=#63):"
chk_has "ship-gate record: a record failure captures the stderr" "$out" "Permission denied"
chk_has "ship-gate record: a record failure names the manual command" "$out" \
  "record it by hand: bash ${GATE_LEDGER} record shipfail Ship ran \"shipping pr=#63 via=land\""
chk "ship-gate record: the land still tidied despite the record failure" \
  "$([ ! -e "$LWT_SF" ]; echo $?)"

echo "--- ship-gate record: the recorded line is tagged via=land (distinguishable from a gated push)"
chk_has "ship-gate record: the ledger line carries via=land" \
  "$(cat "$KIT_LEDGER_DIR/runs/shiprec.log")" "| GATE | ship | ran | shipping pr=#61 via=land"
chk_has "ship-gate record: /kit:wrap step 8's anchored grep still matches it" \
  "$(cat "$KIT_LEDGER_DIR/runs/shiprec.log")" "shipping pr=#61 "

echo "--- ship-gate record: a nested branch lands under gate-ledger.sh's own rid"
build_land nested "" feat/a/b
LWT_NST="$(cd "$TMPD/ld-repo-nested/wt" && pwd -P)"
NESTED_RID="$(cd "$LWT_NST" && bash "$GATE_LEDGER" rid)"
chk "ship-gate record: nested branch feat/a/b rids to a-b" "$([ "$NESTED_RID" = "a-b" ]; echo $?)"
bash "$GATE_LEDGER" record "$NESTED_RID" spec ran "spec cycle for the land test" >/dev/null
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=64 GH_STUB_LAND_REPO="$LWT_NST" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-nested" \
  GH_STUB_LAND_BRANCH=feat/a/b GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_NST" 2>&1)"; rc=$?
chk "ship-gate record: a nested-branch land still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "ship-gate record: nested branch reports the rid it actually used" "$out" \
  "recorded ship gate for ${NESTED_RID} (pr=#64)"
chk_has "ship-gate record: the nested rid's ledger gained the Ship line" \
  "$(cat "$KIT_LEDGER_DIR/runs/${NESTED_RID}.log")" "| GATE | ship | ran | shipping pr=#64 via=land"

echo "--- ship-gate record: a TREE MISMATCH never records, even with a prior ledger"
build_land mismatch "" feat/mismatch
LWT_MM="$(cd "$TMPD/ld-repo-mismatch/wt" && pwd -P)"
bash "$GATE_LEDGER" record mismatch spec ran "spec cycle for the land test" >/dev/null
MMWORK="$TMPD/ld-mismatch-squash"
git clone -q "$TMPD/ld-bare-mismatch" "$MMWORK"; gitc "$MMWORK"
echo "stale change" > "$MMWORK/pr-file.txt"
git -C "$MMWORK" add -A; git -C "$MMWORK" commit -qm "squash: stale head"
git -C "$MMWORK" push -q origin main
MM_SHA="$(git -C "$MMWORK" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=70 \
  GH_STUB_VIEW_STATE="{\"state\":\"MERGED\",\"mergeCommit\":{\"oid\":\"${MM_SHA}\"}}" \
  "$WRAP" land "$LWT_MM" 2>&1)"; rc=$?
chk "ship-gate record: a MISMATCH land exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "ship-gate record: the mismatch is reported" "$out" "TREE MISMATCH"
chk_no "ship-gate record: a MISMATCH never reports a record" "$out" "recorded ship gate"
chk_has "ship-gate record: the mismatch ledger keeps only the seeded line" \
  "$(cat "$KIT_LEDGER_DIR/runs/mismatch.log")" "spec cycle for the land test"
chk_no "ship-gate record: the mismatch ledger gained no Ship line" \
  "$(cat "$KIT_LEDGER_DIR/runs/mismatch.log")" "| GATE | ship |"

echo "--- ship-gate record: a ledger already naming this PR skips as idempotent"
build_land samepr "" feat/samepr
LWT_SP="$(cd "$TMPD/ld-repo-samepr/wt" && pwd -P)"
bash "$GATE_LEDGER" record samepr Ship ran "shipping pr=#71 via=land" >/dev/null
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=71 GH_STUB_LAND_REPO="$LWT_SP" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-samepr" \
  GH_STUB_LAND_BRANCH=feat/samepr GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_SP" 2>&1)"; rc=$?
chk "ship-gate record: the idempotent same-PR case still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "ship-gate record: the idempotent case reports why it skipped" "$out" \
  "ship gate for samepr already names pr=#71; skipping (already recorded)"
chk_no "ship-gate record: the idempotent case never reports a fresh record" "$out" "recorded ship gate"
chk "ship-gate record: the idempotent case wrote no second Ship line" \
  "$([ "$(grep -c '| GATE | ship |' "$KIT_LEDGER_DIR/runs/samepr.log")" -eq 1 ]; echo $?)"

echo "--- ship-gate record: a reused slug naming a different PR skips, never overwrites"
build_land typo "" feat/typo
LWT_TY="$(cd "$TMPD/ld-repo-typo/wt" && pwd -P)"
bash "$GATE_LEDGER" record typo Ship ran "shipping pr=#80 via=land" >/dev/null
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=81 GH_STUB_LAND_REPO="$LWT_TY" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-typo" \
  GH_STUB_LAND_BRANCH=feat/typo GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TY" 2>&1)"; rc=$?
chk "ship-gate record: the reused-slug case still exits 0" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "ship-gate record: the reused-slug case names the mismatch" "$out" \
  "ship gate for typo already names pr=#80, not pr=#81; skipping (reused slug, different run)"
chk_no "ship-gate record: the reused-slug case never reports a fresh record" "$out" "recorded ship gate"
chk "ship-gate record: the reused-slug ledger kept exactly its original line" \
  "$([ "$(grep -c '| GATE | ship |' "$KIT_LEDGER_DIR/runs/typo.log")" -eq 1 ]; echo $?)"
chk_has "ship-gate record: the reused-slug ledger still names the original PR" \
  "$(cat "$KIT_LEDGER_DIR/runs/typo.log")" "pr=#80"
chk_no "ship-gate record: the reused-slug ledger never gained the new PR" \
  "$(cat "$KIT_LEDGER_DIR/runs/typo.log")" "pr=#81"

# ===========================================================================
echo "=== land: adopting an operator-owned open PR for the branch (SPEC-299) ==="
# ===========================================================================
open_pr_json() { # open_pr_json <number> <base> <author> [isDraft] [isCrossRepo]
  printf '[{"number":%s,"baseRefName":"%s","author":{"login":"%s"},"isDraft":%s,"isCrossRepository":%s}]' \
    "$1" "$2" "$3" "${4:-false}" "${5:-false}"
}
two_open_pr_json() {
  printf '[{"number":%s,"baseRefName":"main","author":{"login":"me"},"isDraft":false,"isCrossRepository":false},{"number":%s,"baseRefName":"main","author":{"login":"me"},"isDraft":false,"isCrossRepository":false}]' "$1" "$2"
}

echo "--- own PR on the default branch is adopted, no create, merge runs on it"
build_land adopt-own
LREPO_AO="$TMPD/ld-repo-adopt-own"; LWT_AO="$(cd "$LREPO_AO/wt" && pwd -P)"
LTIP_AO="$(git -C "$LWT_AO" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 7 main me)" GH_STUB_LAND_REPO="$LWT_AO" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-own" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_AO" 2>&1)"; rc=$?
CALLS_AO="$(cat "$GH_STUB_CALLS")"
chk "adopt: own open PR on the default branch exits 0" "$rc"
chk_has "adopt: reports adopted, not opened" "$out" "adopted PR #7"
chk_no "adopt: never calls pr create" "$CALLS_AO" "pr create"
chk_has "adopt: merge runs on the adopted PR" "$CALLS_AO" "pr merge 7 --repo"
chk_has "adopt: merge still pins the pushed head" "$CALLS_AO" "--squash --match-head-commit ${LTIP_AO}"

echo "--- an uppercase author login still matches the operator (case-insensitive)"
build_land adopt-case
LWT_AC="$(cd "$TMPD/ld-repo-adopt-case/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 8 main Me)" GH_STUB_LAND_REPO="$LWT_AC" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-case" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_AC" 2>&1)"; rc=$?
chk "adopt: uppercase-login PR exits 0" "$rc"
chk_has "adopt: uppercase-login PR is adopted" "$out" "adopted PR #8"

echo "--- a draft PR is marked ready, then adopted and merged"
build_land adopt-draft
LWT_AD="$(cd "$TMPD/ld-repo-adopt-draft/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 9 main me true)" GH_STUB_LAND_REPO="$LWT_AD" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-draft" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_AD" 2>&1)"; rc=$?
CALLS_AD="$(cat "$GH_STUB_CALLS")"
chk "adopt: draft PR exits 0" "$rc"
chk_has "adopt: draft PR is marked ready" "$CALLS_AD" "pr ready 9 --repo"
chk_has "adopt: draft PR is then adopted" "$out" "adopted PR #9"
chk_has "adopt: draft PR is merged" "$CALLS_AD" "pr merge 9 --repo"

echo "--- a draft PR whose ready call fails refuses before any merge"
build_land adopt-draft-fail
LWT_ADF="$(cd "$TMPD/ld-repo-adopt-draft-fail/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 10 main me true)" GH_STUB_READY_RC=1 \
  GH_STUB_LAND_REPO="$LWT_ADF" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-draft-fail" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_ADF" 2>&1)"; rc=$?
chk "adopt: failed ready exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: failed ready names the refusal" "$out" \
  "PR REFUSED: open PR #10 is a draft and gh pr ready failed"
chk_no "adopt: failed ready never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- an open PR targeting another base refuses"
build_land adopt-offbase
LWT_OB="$(cd "$TMPD/ld-repo-adopt-offbase/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 11 feat/other me)" GH_STUB_LAND_REPO="$LWT_OB" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-offbase" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_OB" 2>&1)"; rc=$?
chk "adopt: off-base PR exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: off-base PR names the base" "$out" \
  "PR REFUSED: open PR #11 targets feat/other, not main"
chk_no "adopt: off-base PR never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- an open PR authored by someone else refuses"
build_land adopt-foreign
LWT_FO="$(cd "$TMPD/ld-repo-adopt-foreign/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 12 main other)" GH_STUB_LAND_REPO="$LWT_FO" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-foreign" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_FO" 2>&1)"; rc=$?
chk "adopt: foreign-author PR exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: foreign-author PR names the author" "$out" \
  "PR REFUSED: open PR #12 is authored by other"
chk_no "adopt: foreign-author PR never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- two open PRs for the branch refuses"
build_land adopt-two
LWT_TWO="$(cd "$TMPD/ld-repo-adopt-two/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(two_open_pr_json 13 14)" GH_STUB_LAND_REPO="$LWT_TWO" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-two" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_TWO" 2>&1)"; rc=$?
chk "adopt: two open PRs exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: two open PRs names the count" "$out" "PR REFUSED: 2 open PRs for feat/land"
chk_no "adopt: two open PRs never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- a fork's same-named-branch PR is dropped, land creates as today"
build_land adopt-fork
LWT_FK="$(cd "$TMPD/ld-repo-adopt-fork/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 15 main other false true)" \
  GH_STUB_CREATE_NUM=44 GH_STUB_LAND_REPO="$LWT_FK" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-fork" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_FK" 2>&1)"; rc=$?
chk "adopt: fork-only entry exits 0" "$rc"
chk_has "adopt: fork-only entry still creates a PR" "$out" "opened PR #44"
chk_has "adopt: fork-only entry called pr create" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- the operator login not resolving refuses"
build_land adopt-noid
LWT_NOID="$(cd "$TMPD/ld-repo-adopt-noid/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 16 main me)" GH_STUB_API_RC=1 \
  GH_STUB_LAND_REPO="$LWT_NOID" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-noid" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_NOID" 2>&1)"; rc=$?
chk "adopt: identity read failure exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: identity read failure names it" "$out" \
  "PR REFUSED: open PR #16: operator login did not resolve"
chk_no "adopt: identity read failure never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- the open-PR lookup itself failing refuses"
build_land adopt-listfail
LWT_LF="$(cd "$TMPD/ld-repo-adopt-listfail/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_LIST_RC=1 GH_STUB_LAND_REPO="$LWT_LF" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-listfail" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_LF" 2>&1)"; rc=$?
chk "adopt: list failure exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: list failure names the branch" "$out" \
  "PR REFUSED: open-PR lookup for feat/land failed"
chk_no "adopt: list failure never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- --title/--body-file on an adopted PR are ignored, with a note"
build_land adopt-flags
LWT_FL="$(cd "$TMPD/ld-repo-adopt-flags/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 17 main me)" GH_STUB_LAND_REPO="$LWT_FL" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-flags" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_FL" --title "custom title" 2>"$TMPD/adopt-flags.err")"; rc=$?
chk "adopt: flags-ignored case exits 0" "$rc"
chk_has "adopt: flags-ignored case is adopted" "$out" "adopted PR #17"
chk_has "adopt: the kept-flags note goes to stderr" "$(cat "$TMPD/adopt-flags.err")" \
  "note: adopted PR #17 keeps its own title and body"
chk_no "adopt: the kept-flags note stays off stdout" "$out" "keeps its own title and body"

echo "--- a lookup that answers unparseable JSON refuses instead of creating a PR"
build_land adopt-badjson
LWT_BJ="$(cd "$TMPD/ld-repo-adopt-badjson/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land='not json' GH_STUB_LAND_REPO="$LWT_BJ" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adopt-badjson" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_BJ" 2>&1)"; rc=$?
chk "adopt: bad lookup JSON exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "adopt: bad lookup JSON names the failed lookup" "$out" "open-PR lookup for feat/land failed"
chk_no "adopt: bad lookup JSON never creates a PR" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "=== land: flags packed into one positional are refused ==="
out="$("$WRAP" land " --title x" 2>&1)"; rc=$?
chk "packed arg to land exits 64" "$([ "$rc" = 64 ]; echo $?)"
chk_has "packed arg to land names the packed-flags refusal" "$out" "wrap.sh land: argument '"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-land: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-land: all $PASS passed"
