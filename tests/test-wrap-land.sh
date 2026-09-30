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

echo "=== land-merge: a CONFLICTING land merges origin/<def> in, then retries ==="
# ===========================================================================
# A refused `gh pr merge` is the trigger: the branch is already pushed, so the recovery
# merges origin/<def> into it (never a rebase, never a force push), resolves only the
# conflict shapes `_rb_resolve` owns, pushes fast-forward, and tries the squash once more.
# The structural checks run here at the top because the whole block leans on them: the
# shared resolver is the same classifier rebase stops call, and the marker scan reads
# each path's configured marker size rather than a fixed seven.
chk "land-merge: _rb_stop resolves through _rb_resolve" \
  "$(sed -n '/^_rb_stop()/,/^}/p' "$KIT_DIR/lib/wrap/wrap-rebase.sh" | grep -q '_rb_resolve '; echo $?)"
chk "land-merge: _rb_markers reads conflict-marker-size" \
  "$(sed -n '/^_rb_markers()/,/^}/p' "$KIT_DIR/lib/wrap/wrap-rebase.sh" | grep -q 'check-attr conflict-marker-size'; echo $?)"

# ---------------------------------------------------------------------------
# land-merge fixtures: the registry layout (the generator is a stub listing
# specs/), a clone on feat/land in its own worktree, and a second clone that
# advances origin/main. Every conflicting case fails the first `pr merge` with a
# non-transient refusal, then answers CONFLICTING at the pushed head and
# MERGEABLE at the re-merge head (%REMERGE_TIP% resolves to whatever feat/land
# points at when the read happens -- the old tip before the push, the merge
# commit after it).
build_land_reg() { # build_land_reg <name>
  local name="$1" work="$TMPD/ld-work-$1" repo="$TMPD/ld-repo-$1"
  mkdir -p "$work/lib/registry" "$work/specs" "$work/docs"
  git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  { printf '#!/usr/bin/env bash\nroot="$(cd "$(dirname "$0")/../.." && pwd)"\n'
    printf '%s\n' "${LGEN:-ls \"\$root/specs\" | LC_ALL=C sort > \"\$root/docs/FEATURES.md\"}"
  } > "$work/lib/registry/feature-registry.sh"
  chmod +x "$work/lib/registry/feature-registry.sh"
  echo base > "$work/base.txt"
  printf 'ignored.bin\n' > "$work/.gitignore"
  [ -z "${LBASE_ATTR:-}" ] || printf '%s\n' "$LBASE_ATTR" > "$work/.gitattributes"
  echo a > "$work/specs/a.md"
  printf '# Changelog\n\n- base\n' > "$work/docs/CHANGELOG.md"
  ( cd "$work" && bash lib/registry/feature-registry.sh generate )
  rm -f "$work/docs/GEN_OUT.txt"   # generator side output never enters history
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/ld-bare-$name"
  git clone -q "$TMPD/ld-bare-$name" "$repo"; gitc "$repo"
  git -C "$repo" remote set-head origin main >/dev/null 2>&1
  git -C "$repo" worktree add -q -b feat/land "$repo/wt" main >/dev/null 2>&1
  if [ -n "${LBRANCH:-}" ]; then
    ( cd "$repo/wt" && eval "$LBRANCH" )
  else
    echo b > "$repo/wt/specs/b.md"
    ( cd "$repo/wt" && bash lib/registry/feature-registry.sh generate )
  fi
  git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "feat: the landed change"
}
land_adv() { git clone -q "$TMPD/ld-bare-$1" "$TMPD/ld-adv-$1" && gitc "$TMPD/ld-adv-$1"; }
land_adv_regen() { # land_adv_regen <name> <spec> -- origin gains specs/<s> + a regen
  land_adv "$1" || return 1
  echo "$2" > "$TMPD/ld-adv-$1/specs/$2.md"
  ( cd "$TMPD/ld-adv-$1" && bash lib/registry/feature-registry.sh generate )
  rm -f "$TMPD/ld-adv-$1/docs/GEN_OUT.txt"
  git -C "$TMPD/ld-adv-$1" add -A; git -C "$TMPD/ld-adv-$1" commit -qm "origin: another feature"
  git -C "$TMPD/ld-adv-$1" push -q origin main
}
lm_conf() { printf '{"number":%s,"title":"x","headRefName":"feat/land","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","statusCheckRollup":[],"headRefOid":"%s"}' "$1" "$2"; }
lm_ok() { printf '{"number":%s,"title":"x","headRefName":"feat/land","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[],"headRefOid":"%%REMERGE_TIP%%"}' "$1"; }
REAL_GIT_BIN="$(command -v git)"

echo "--- land-merge: a FEATURES conflict merges origin/main in, then lands"
build_land_reg featx
LWT="$(cd "$TMPD/ld-repo-featx/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-featx"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen featx o
LADV="$(git -C "$TMPD/ld-adv-featx" rev-parse HEAD)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-featx" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
LHEAD="$(git -C "$LREPO" rev-parse HEAD)"
chk "land-merge: FEATURES conflict exits 0" "$rc"
chk_has "land-merge: reports the CONFLICTING trigger" "$out" "#42 is CONFLICTING: merging origin/main into feat/land"
chk_has "land-merge: reports the resolved conflict count" "$out" "merged origin/main into feat/land: 1 conflict(s) resolved"
chk_has "land-merge: waits for GitHub to see the merge commit" "$out" "waiting for GitHub to see ${LHEAD:0:7}"
chk "land-merge: HEAD is a merge of origin/main" \
  "$([ "$(git -C "$LREPO" log -1 --format=%P HEAD)" = "$LTIP $LADV" ]; echo $?)"
chk_has "land-merge: the merge commit carries a conventional subject" \
  "$(git -C "$LREPO" log -1 --format=%s HEAD)" "chore(merge): merge origin/main"
chk "land-merge: FEATURES equals a fresh generate" \
  "$([ "$(git -C "$LREPO" show HEAD:docs/FEATURES.md)" = $'a.md\nb.md\no.md' ]; echo $?)"
chk "land-merge: the second merge pins the merged head" \
  "$(awk -v m="$LHEAD" '/^pr merge 42 /{c++; if (c==2) exit (index($0, "--match-head-commit " m) ? 0 : 1)}' "$GH_STUB_CALLS"; echo $?)"
chk "land-merge: the old tip is an ancestor of the pushed head" \
  "$(git -C "$LREPO" merge-base --is-ancestor "$LTIP" HEAD 2>/dev/null; echo $?)"
chk_has "land-merge: lands with the merged tree verified" "$out" "merged #42 (${LHEAD}): tree verified"
chk "land-merge: no rebase entry in the reflog" "$(git -C "$LREPO" reflog 2>/dev/null | grep -c rebase)"

echo "--- land-merge: a union-only divergence keeps both lines once"
build_land ulog --union-log
LWT="$(cd "$TMPD/ld-repo-ulog/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-ulog"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv ulog
printf 'origin entry\n' >> "$TMPD/ld-adv-ulog/_meta/LAB_LOG.md"
git -C "$TMPD/ld-adv-ulog" commit -qam "origin: log line"
git -C "$TMPD/ld-adv-ulog" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ulog" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
ULOG="$(git -C "$LREPO" show HEAD:_meta/LAB_LOG.md 2>/dev/null)"
chk "land-merge: union merge exits 0" "$rc"
chk "land-merge: union kept the branch line once" \
  "$([ "$(printf '%s\n' "$ULOG" | grep -cx 'remote entry')" = 1 ]; echo $?)"
chk "land-merge: union kept the origin line once" \
  "$([ "$(printf '%s\n' "$ULOG" | grep -cx 'origin entry')" = 1 ]; echo $?)"
chk "land-merge: union kept the base line" \
  "$(printf '%s\n' "$ULOG" | grep -qx 'base entry'; echo $?)"

echo "--- land-merge: pure-add CHANGELOG bullets on both sides union in"
build_land_reg clog
LWT="$(cd "$TMPD/ld-repo-clog/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-clog"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv clog
printf -- '- origin bullet\n' >> "$TMPD/ld-adv-clog/docs/CHANGELOG.md"
git -C "$TMPD/ld-adv-clog" commit -qam "origin: changelog line"
git -C "$TMPD/ld-adv-clog" push -q origin main
printf -- '- branch bullet\n' >> "$LWT/docs/CHANGELOG.md"
git -C "$LWT" commit -qam "feat: changelog line"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-clog" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LCLOG="$(git -C "$LREPO" show HEAD:docs/CHANGELOG.md 2>/dev/null)"
chk "land-merge: CHANGELOG conflict exits 0" "$rc"
chk "land-merge: both changelog bullets kept once" \
  "$([ "$(printf '%s\n' "$LCLOG" | grep -cx -- '- branch bullet')" = 1 ] \
    && [ "$(printf '%s\n' "$LCLOG" | grep -cx -- '- origin bullet')" = 1 ]; echo $?)"
chk "land-merge: the base changelog line is kept" \
  "$(printf '%s\n' "$LCLOG" | grep -qx -- '- base'; echo $?)"

echo "--- land-merge: a clean merge still regenerates FEATURES"
# The branch adds specs/b.md without regenerating; origin adds specs/o.md and
# regenerates, so the merge itself is conflict-free and the post-merge pass is
# the only writer of the listed file.
LBRANCH='echo b > specs/b.md' build_land_reg cleanx2
LWT="$(cd "$TMPD/ld-repo-cleanx2/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-cleanx2"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen cleanx2 o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cleanx2" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: clean merge exits 0" "$rc"
chk "land-merge: FEATURES in the merge commit equals a fresh generate" \
  "$([ "$(git -C "$LREPO" show HEAD:docs/FEATURES.md)" = $'a.md\nb.md\no.md' ]; echo $?)"
chk_has "land-merge: the merge reports no conflicts" "$out" "0 conflict(s) resolved"

echo "--- land-merge: a real content conflict refuses and restores"
build_land realc --modify-base
LWT="$(cd "$TMPD/ld-repo-realc/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-realc"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv realc
echo "origin edit" > "$TMPD/ld-adv-realc/base.txt"
git -C "$TMPD/ld-adv-realc" commit -qam "origin: same line"
git -C "$TMPD/ld-adv-realc" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-realc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: a real conflict exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: REFUSED names the path" "$out" "REFUSED feat/land: conflict in base.txt"
chk_has "land-merge: the PR stays open" "$out" "PR #42 left open"
chk "land-merge: HEAD is back at the old tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: no merge is left in progress" \
  "$([ -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ] && echo 1 || echo 0)"
chk "land-merge: the worktree is clean" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"
chk "land-merge: origin still holds the old tip" \
  "$([ "$(git -C "$LWT" ls-remote origin refs/heads/feat/land | cut -f1)" = "$LTIP" ]; echo $?)"
chk "land-merge: exactly one pr merge call ran" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

echo "--- land-merge: a mixed conflict names only the real path"
LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && echo "branch edit" > base.txt' \
  build_land_reg mixed2
LWT="$(cd "$TMPD/ld-repo-mixed2/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen mixed2 o
echo "origin edit" > "$TMPD/ld-adv-mixed2/base.txt"
git -C "$TMPD/ld-adv-mixed2" commit -qam "origin: same line"
git -C "$TMPD/ld-adv-mixed2" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-mixed2" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: a mixed conflict exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the refusal names base.txt" "$out" "conflict in base.txt"
chk_no "land-merge: the refusal never names FEATURES" "$out" "conflict in docs/FEATURES.md"
chk "land-merge: the old tip is restored" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a no-op generator leaves markers, and the scan names the file"
# The FEATURES conflict is classified resolvable, so a generator that writes
# nothing leaves the conflict markers the merge wrote; the stage-set scan is the
# last line of defense before they could be committed. The fixture regen still
# runs (`.noop` only lands on the branch), so FEATURES exists and conflicts.
LGEN='[ -f "$root/.noop" ] || ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"; echo note > "$root/docs/GEN_OUT.txt"' \
  LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && touch .noop && rm -f docs/GEN_OUT.txt' \
  build_land_reg markx
LWT="$(cd "$TMPD/ld-repo-markx/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen markx o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-markx" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: markers left exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: MARKERS names FEATURES" "$out" "MARKERS feat/land: docs/FEATURES.md"
chk "land-merge: markers case restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: the generator side file was removed by the restore" \
  "$([ ! -e "$LWT/docs/GEN_OUT.txt" ]; echo $?)"
chk "land-merge: no marker ever reached the branch or origin" \
  "$(git -C "$LWT" log --format=%H -5 | while read -r c; do git -C "$LWT" grep -l '^<<<<<<< ' "$c" -- docs 2>/dev/null; done | wc -l | tr -d ' ')"

echo "--- land-merge: a configured conflict-marker-size is honored, both 9 and 5"
# The attribute rides in the base commit so both sides of the conflict carry it;
# the generator no-ops only once .noop is committed on the branch, so the
# fixture regen still writes FEATURES while the merge-time pass leaves markers.
for LMS in 9 5; do
  LGEN='[ -f "$root/.noop" ] && exit 0; ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"' \
  LBASE_ATTR="docs/FEATURES.md conflict-marker-size=$LMS" \
  LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && touch .noop' \
    build_land_reg "msz$LMS"
  LWT="$(cd "$TMPD/ld-repo-msz$LMS/wt" && pwd -P)"
  LTIP="$(git -C "$LWT" rev-parse HEAD)"
  land_adv_regen "msz$LMS" o
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
    GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
    GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
    KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
    GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-msz$LMS" \
    GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
  chk "land-merge: marker size $LMS exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
  chk_has "land-merge: MARKERS names FEATURES at size $LMS" "$out" "MARKERS feat/land: docs/FEATURES.md"
done

echo "--- land-merge: an eight-> blockquote line stays legal at the default size"
LGEN='{ ls "$root/specs" | LC_ALL=C sort; printf ">>>>>>>>\n"; } > "$root/docs/FEATURES.md"' \
  build_land_reg bq
LWT="$(cd "$TMPD/ld-repo-bq/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-bq"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen bq o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-bq" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: the nested blockquote case exits 0" "$rc"
chk_no "land-merge: no MARKERS refusal for an over-long marker run" "$out" "MARKERS"
chk "land-merge: the eight-> line reached the merge commit" \
  "$(git -C "$LREPO" show HEAD:docs/FEATURES.md 2>/dev/null | grep -qx '>>>>>>>>'; echo $?)"

echo "--- land-merge: a generator side effect on an auto-merged file still aborts"
# README.md merges cleanly on origin's side; the generator then rewrites it and
# dies, so the restore must put the staged auto-merge back before --abort works.
LGEN='echo gen > "$root/README.md"; exit 3' build_land_reg sidefx
LWT="$(cd "$TMPD/ld-repo-sidefx/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv sidefx
echo "origin readme" > "$TMPD/ld-adv-sidefx/README.md"
git -C "$TMPD/ld-adv-sidefx" add -A; git -C "$TMPD/ld-adv-sidefx" commit -qm "origin: readme"
git -C "$TMPD/ld-adv-sidefx" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-sidefx" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: the generator side-effect case exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: GENERATOR FAILED is reported" "$out" "GENERATOR FAILED feat/land"
chk "land-merge: the tip is restored after the abort" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: no merge is left in progress" \
  "$([ -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ] && echo 1 || echo 0)"
chk "land-merge: the worktree is clean after the abort" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"

echo "--- land-merge: a generator failing on a conflict aborts cleanly"
LGEN='[ -f "$root/.genfail" ] && exit 3; ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"' \
  LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && touch .genfail' \
  build_land_reg genfail
LWT="$(cd "$TMPD/ld-repo-genfail/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen genfail o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-genfail" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: the generator failure exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: GENERATOR FAILED on a conflict" "$out" "GENERATOR FAILED feat/land"
chk "land-merge: generator failure restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: generator failure left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"

echo "--- land-merge: untracked generator output lands in the merge commit"
LGEN='ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"; echo note > "$root/docs/GEN_OUT.txt"' \
  LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && rm -f docs/GEN_OUT.txt' \
  build_land_reg utr
LWT="$(cd "$TMPD/ld-repo-utr/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-utr"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen utr o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-utr" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: untracked-output case exits 0" "$rc"
chk "land-merge: the generator output is in the merge commit" \
  "$([ "$(git -C "$LREPO" show HEAD:docs/GEN_OUT.txt 2>/dev/null)" = "note" ]; echo $?)"
chk "land-merge: the landed checkout is clean" \
  "$([ -z "$(git -C "$LREPO" status --porcelain)" ]; echo $?)"

echo "--- land-merge: untracked output is gone after a refused conflict"
# With base.txt unmerged the classifier refuses before the generator runs, so
# GEN_OUT is never written; an ignored file in the worktree must be untouched.
LGEN='ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"; echo note > "$root/docs/GEN_OUT.txt"' \
  LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && rm -f docs/GEN_OUT.txt && echo "branch edit" > base.txt' \
  build_land_reg utref
LWT="$(cd "$TMPD/ld-repo-utref/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
echo keep > "$LWT/ignored.bin"
land_adv_regen utref o
echo "origin edit" > "$TMPD/ld-adv-utref/base.txt"
git -C "$TMPD/ld-adv-utref" commit -qam "origin: same line"
git -C "$TMPD/ld-adv-utref" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-utref" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: refused-with-output exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "land-merge: the untracked output is gone" "$([ ! -e "$LWT/docs/GEN_OUT.txt" ]; echo $?)"
chk "land-merge: the gitignored file is untouched" \
  "$([ "$(cat "$LWT/ignored.bin" 2>/dev/null)" = "keep" ]; echo $?)"

echo "--- land-merge: an untracked file hidden by config still trips the clean check"
build_land_reg hidden
LWT="$(cd "$TMPD/ld-repo-hidden/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
git -C "$LWT" config status.showUntrackedFiles no
echo loose > "$LWT/loose.txt"
land_adv_regen hidden o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-hidden" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: hidden-untracked exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the precondition names the dirty checkout" "$out" "is dirty; nothing merged"
chk "land-merge: the hidden file is untouched" \
  "$([ "$(cat "$LWT/loose.txt" 2>/dev/null)" = "loose" ]; echo $?)"
chk "land-merge: the hidden file was never committed" \
  "$(git -C "$LWT" log --all --oneline -- loose.txt | wc -l | tr -d ' ')"
chk "land-merge: hidden-untracked made no merge commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a refused merge commit restores the tip"
build_land_reg cref
LWT="$(cd "$TMPD/ld-repo-cref/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen cref o
mkdir -p "$TMPD/ld-repo-cref/.git/hooks"
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMPD/ld-repo-cref/.git/hooks/commit-msg"
chmod +x "$TMPD/ld-repo-cref/.git/hooks/commit-msg"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-cref" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: refused commit exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the refused commit is named" "$out" "the merge commit was refused"
chk "land-merge: commit refusal restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: commit refusal left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"

echo "--- land-merge: a refused dedupe commit undoes the merge commit"
# The union-marked board duplicates the flipped row on merge, so dedupe-all
# rewrites the file and the follow-up commit is refused by the hook; the staged
# paths go back from HEAD and the merge commit is reset away.
build_land_board() { # build_land_board <name>
  local name="$1" work="$TMPD/ld-work-$1" repo="$TMPD/ld-repo-$1"
  mkdir -p "$work/_meta"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/BACKLOG.md merge=union\n' > "$work/.gitattributes"
  printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-1 | row a | src | queued |\n' \
    > "$work/_meta/BACKLOG.md"
  echo base > "$work/base.txt"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/ld-bare-$name"
  git clone -q "$TMPD/ld-bare-$name" "$repo"; gitc "$repo"
  git -C "$repo" remote set-head origin main >/dev/null 2>&1
  git -C "$repo" worktree add -q -b feat/land "$repo/wt" main >/dev/null 2>&1
  sed -i.bak 's/ID-1 | row a | src | queued/ID-1 | row a | src | shipped/' "$repo/wt/_meta/BACKLOG.md"
  rm -f "$repo/wt/_meta/BACKLOG.md.bak"
  git -C "$repo/wt" commit -qam "branch flips ID-1"
}
build_land_board ddup
LWT="$(cd "$TMPD/ld-repo-ddup/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv ddup
sed -i.bak 's/ID-1 | row a | src | queued/ID-1 | row a | src | executing/' "$TMPD/ld-adv-ddup/_meta/BACKLOG.md"
rm -f "$TMPD/ld-adv-ddup/_meta/BACKLOG.md.bak"
git -C "$TMPD/ld-adv-ddup" commit -qam "origin flips ID-1 too"
git -C "$TMPD/ld-adv-ddup" push -q origin main
mkdir -p "$TMPD/ld-repo-ddup/.git/hooks"
cat > "$TMPD/ld-repo-ddup/.git/hooks/commit-msg" <<'HOOK'
#!/usr/bin/env bash
grep -q 'fix(board)' "$1" && exit 1
exit 0
HOOK
chmod +x "$TMPD/ld-repo-ddup/.git/hooks/commit-msg"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ddup" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: dedupe failure exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the failed dedupe commit is named" "$out" "the follow-up commit failed"
chk "land-merge: dedupe failure restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: dedupe failure left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain --untracked-files=all)" ]; echo $?)"

echo "--- land-merge: --verify green runs between the merge and the push"
build_land_reg vg
LWT="$(cd "$TMPD/ld-repo-vg/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-vg"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen vg o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-vg" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify 'test -f docs/FEATURES.md' 2>&1)"; rc=$?
chk "land-merge: verify green exits 0" "$rc"
chk_has "land-merge: the verified line reports the command" "$out" "verified in ${LWT}: test -f docs/FEATURES.md"
chk "land-merge: the verified line precedes the post-push wait" \
  "$(awk '/verified in/{v=NR} /waiting for GitHub/{w=NR} END{exit !(v && w && v<w)}' <<< "$out"; echo $?)"

echo "--- land-merge: --verify red undoes the merge and pushes nothing"
build_land_reg vr
LWT="$(cd "$TMPD/ld-repo-vr/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen vr o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-vr" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify false 2>&1)"; rc=$?
chk "land-merge: verify red exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: VERIFY FAILED names the worktree" "$out" "VERIFY FAILED feat/land: false exited 1 in ${LWT}"
chk "land-merge: verify red restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: verify red left the worktree clean" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"
chk "land-merge: verify red pushed nothing to origin" \
  "$([ "$(git -C "$LWT" ls-remote origin refs/heads/feat/land | cut -f1)" = "$LTIP" ]; echo $?)"
chk "land-merge: verify red made one pr merge call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

echo "--- land-merge: a verify that dirties a tracked file counts red"
build_land_reg vdirty
LWT="$(cd "$TMPD/ld-repo-vdirty/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen vdirty o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-vdirty" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify 'echo x >> base.txt' 2>&1)"; rc=$?
chk "land-merge: dirtying verify exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the changed-tracked-files verdict is named" "$out" "changed tracked files"
chk_has "land-merge: the undo names the leftover file" "$out" "base.txt"
chk "land-merge: dirtying verify restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: dirtying verify pushed nothing" \
  "$([ "$(git -C "$LWT" ls-remote origin refs/heads/feat/land | cut -f1)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a verify that commits counts red"
build_land_reg vcommit
LWT="$(cd "$TMPD/ld-repo-vcommit/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen vcommit o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-vcommit" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify 'echo v > v.txt && git add v.txt && git commit -qm verify' 2>&1)"; rc=$?
chk "land-merge: committing verify exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the moved-HEAD verdict is named" "$out" "moved HEAD"
chk "land-merge: committing verify restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: committing verify pushed nothing" \
  "$([ "$(git -C "$LWT" ls-remote origin refs/heads/feat/land | cut -f1)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a push rejected by another writer is undone, never forced"
build_land_reg prace
LWT="$(cd "$TMPD/ld-repo-prace/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen prace o
cat > "$TMPD/race-push.sh" <<SH
#!/usr/bin/env bash
set -e
d=\$(mktemp -d)
git clone -q "$TMPD/ld-bare-prace" "\$d/r"
git -C "\$d/r" config user.email t@t; git -C "\$d/r" config user.name t
git -C "\$d/r" checkout -q feat/land
echo raced > "\$d/r/raced.txt"
git -C "\$d/r" add -A; git -C "\$d/r" commit -qm raced
git -C "\$d/r" push -q origin feat/land
SH
chmod +x "$TMPD/race-push.sh"
mkdir -p "$TMPD/gshim-race"
cat > "$TMPD/gshim-race/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "push" ] && { printf '%s\n' "\$*" >> "$TMPD/push-args.log"; break; }; done
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-race/git"
: > "$TMPD/push-args.log"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-race:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-prace" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify "bash $TMPD/race-push.sh" 2>&1)"; rc=$?
LRACE="$(git -C "$TMPD/ld-bare-prace" rev-parse feat/land)"
chk "land-merge: the raced push exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: PUSH REFUSED names the moved head" "$out" "PUSH REFUSED: feat/land on origin moved to ${LRACE:0:7}"
chk "land-merge: raced push restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: origin keeps the other writer's commit" \
  "$([ "$(git -C "$TMPD/ld-adv-prace" rev-parse HEAD)" != "$LRACE" ] \
    && [ "$(git -C "$TMPD/ld-bare-prace" show feat/land:raced.txt 2>/dev/null)" = "raced" ]; echo $?)"
chk "land-merge: no push in the run carried a force or a plus refspec" \
  "$(grep -cE -- '--force|[[:space:]]\+' "$TMPD/push-args.log")"

echo "--- land-merge: an unreadable remote after a failed push resets nothing"
build_land_reg bgone
LWT="$(cd "$TMPD/ld-repo-bgone/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen bgone o
mkdir -p "$TMPD/gshim-bgone"
cat > "$TMPD/gshim-bgone/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in ls-remote|HEAD:refs/heads/*) exit 1 ;; esac; done
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-bgone/git"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-bgone:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-bgone" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: unreadable remote exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: PUSH FAILED names the uncertainty" "$out" "PUSH FAILED"
chk "land-merge: the merge commit stays when origin cannot be read" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" != "$LTIP" ]; echo $?)"
chk "land-merge: no merge is left in progress" \
  "$([ -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ] && echo 1 || echo 0)"

echo "--- land-merge: a push that landed but reported failure continues"
build_land_reg pland
LWT="$(cd "$TMPD/ld-repo-pland/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-pland"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen pland o
mkdir -p "$TMPD/gshim-pland"
cat > "$TMPD/gshim-pland/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in HEAD:refs/heads/*) hit=1 ;; esac; done
if [ -n "\${hit:-}" ]; then "$REAL_GIT_BIN" "\$@"; exit 1; fi
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-pland/git"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-pland:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-pland" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: landed-despite-failure exits 0" "$rc"
chk "land-merge: the landed merge commit is origin's main" \
  "$([ "$(git -C "$TMPD/ld-bare-pland" rev-parse main)" = "$(git -C "$LREPO" rev-parse HEAD)" ]; echo $?)"

echo "--- land-merge: TERM inside the merge cycle exits 130 and restores"
build_land_reg intc
LWT="$(cd "$TMPD/ld-repo-intc/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen intc o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-intc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --verify 'kill -TERM $PPID' 2>&1)"; rc=$?
chk "land-merge: an interrupted cycle exits 130" "$([ "$rc" -eq 130 ]; echo $?)"
chk "land-merge: interrupt restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: interrupt left no merge in progress" \
  "$([ -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ] && echo 1 || echo 0)"
chk "land-merge: interrupt left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ]; echo $?)"

echo "--- land-merge: a fetch failure inside the cycle merges nothing"
build_land_reg fetchf
LWT="$(cd "$TMPD/ld-repo-fetchf/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen fetchf o
mkdir -p "$TMPD/gshim-fetch"
cat > "$TMPD/gshim-fetch/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do [ "\$a" = "fetch" ] && exit 1; done
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-fetch/git"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-fetch:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-fetchf" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: fetch failure exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the failed fetch is named" "$out" "fetch origin main failed"
chk "land-merge: fetch failure made no merge commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a branch already containing origin/main routes to merge --apply"
# The first squash still refuses (GitHub's verdict is union-blind), but the
# local ancestor check sees origin/main already inside the tip: nothing to
# merge, so the cycle refuses before committing and names the recovery verb.
build_land_reg acon
LWT="$(cd "$TMPD/ld-repo-acon/wt" && pwd -P)"
land_adv_regen acon o
git -C "$LWT" fetch -q origin main
if ! git -C "$LWT" merge -q -m "chore(merge): merge origin/main" origin/main; then
  ( cd "$LWT" && bash lib/registry/feature-registry.sh generate )
  git -C "$LWT" add -A; git -C "$LWT" commit -qm "chore(merge): merge origin/main"
fi
LTIP="$(git -C "$LWT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-acon" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: already-contains exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: already-contains routes to merge --apply" "$out" "wrap merge --apply --pr 42"
chk "land-merge: already-contains made no new commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a PR still CONFLICTING after the push names the recovery"
build_land_reg stillc
LWT="$(cd "$TMPD/ld-repo-stillc/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen stillc o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2='{"number":42,"headRefOid":"%REMERGE_TIP%","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","statusCheckRollup":[]}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-stillc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LMERGED="$(git -C "$TMPD/ld-bare-stillc" rev-parse feat/land)"
chk "land-merge: still-CONFLICTING exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: still-CONFLICTING routes to merge --apply" "$out" "wrap merge --apply --pr 42"
chk_has "land-merge: still-CONFLICTING names the origin merge commit" "$out" "${LMERGED:0:7} is on origin"
chk "land-merge: still-CONFLICTING made exactly one pr merge call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

echo "--- land-merge: GitHub not caught up after the push exits 2 by name"
build_land_reg lagg
LWT="$(cd "$TMPD/ld-repo-lagg/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen lagg o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-lagg" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: not-caught-up exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the lag is named" "$out" "has not caught up"

echo "--- land-merge: a foreign head after the push exits 2 by name"
build_land_reg foreign
LWT="$(cd "$TMPD/ld-repo-foreign/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen foreign o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2='{"number":42,"headRefOid":"0123456789abcdef0123456789abcdef01234567","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-foreign" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: foreign head exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the other writer is named" "$out" "another writer pushed"

echo "--- land-merge: an unreadable PR after the push exits 2 by name"
build_land_reg unread2
LWT="$(cd "$TMPD/ld-repo-unread2/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen unread2 o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2='{}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-unread2" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: unreadable-after-push exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: unreadable-after-push is named" "$out" "unreadable after the push"

echo "--- land-merge: an unreadable PR after a refused merge merges nothing"
build_land_reg unread1
LWT="$(cd "$TMPD/ld-repo-unread1/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen unread1 o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-unread1" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: unreadable-after-refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the unreadable read is named" "$out" "unreadable"
chk "land-merge: unreadable made no merge commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a head stuck on an older sha exits 2 by name"
build_land_reg stale
LWT="$(cd "$TMPD/ld-repo-stale/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
LOLD="$(git -C "$LWT" rev-parse HEAD~1)"
land_adv_regen stale o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LOLD")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-stale" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: stale head exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the stale head is named" "$out" "GitHub still shows head ${LOLD:0:7}"
chk "land-merge: stale head made no merge commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a refused merge that is not CONFLICTING keeps the old failure"
build_land_reg notconf
LWT="$(cd "$TMPD/ld-repo-notconf/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen notconf o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-notconf" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: non-conflicting refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: non-conflicting refusal keeps MERGE FAILED" "$out" "MERGE FAILED #42: exit 1"
chk "land-merge: non-conflicting refusal made no merge commit" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a failed check on the merged head stops before the second merge"
build_land_reg redcheck
LWT="$(cd "$TMPD/ld-repo-redcheck/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen redcheck o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  GH_STUB_PR_42_2='{"number":42,"headRefOid":"%REMERGE_TIP%","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"FAILURE","completedAt":"2026-01-01T00:00:00Z"}]}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-redcheck" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LMERGED="$(git -C "$TMPD/ld-bare-redcheck" rev-parse feat/land)"
chk "land-merge: failed check exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the failed check names the merged head" "$out" "checks failed on the merged head ${LMERGED:0:7}: ci"
chk "land-merge: failed check made exactly one pr merge call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

echo "--- land-merge: no checks pending pays no hold, even with a long grace"
build_land_reg nocheck
LWT="$(cd "$TMPD/ld-repo-nocheck/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen nocheck o
mkdir -p "$TMPD/sleepshim"
printf '#!/bin/sh\necho slept >> "%s"\nexit 0\n' "$TMPD/sleep-calls.log" > "$TMPD/sleepshim/sleep"
chmod +x "$TMPD/sleepshim/sleep"; rm -f "$TMPD/sleep-calls.log"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/sleepshim:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=90 KIT_WRAP_CARRY_CHECKS_SECS=90 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-nocheck" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: no-checks exits 0" "$rc"
chk "land-merge: the empty rollup never slept" \
  "$([ ! -e "$TMPD/sleep-calls.log" ]; echo $?)"

echo "--- land-merge: a refused second merge names the origin merge commit"
build_land_reg m2fail
LWT="$(cd "$TMPD/ld-repo-m2fail/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen m2fail o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=2 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-m2fail" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LMERGED="$(git -C "$TMPD/ld-bare-m2fail" rev-parse feat/land)"
chk "land-merge: second refusal exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: second refusal routes to merge --apply" "$out" "wrap merge --apply --pr 42"
chk_has "land-merge: second refusal names the origin merge commit" "$out" "${LMERGED:0:7} is on origin"
chk "land-merge: a refused second merge makes no third call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 2 ]; echo $?)"

echo "--- land-merge: a clean first merge reads the PR zero times"
build_land_reg happy
LWT="$(cd "$TMPD/ld-repo-happy/wt" && pwd -P)"
land_adv happy
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-happy" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: happy path exits 0" "$rc"
chk "land-merge: happy path makes no pr view call before the merge" \
  "$(awk '/^pr merge 42 /{exit} /^pr view 42 /{c++} END{print c+0}' "$GH_STUB_CALLS")"

echo "--- land-merge: an adopted conflicting PR runs the same merge cycle"
build_land_reg adoptc
LWT="$(cd "$TMPD/ld-repo-adoptc/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-adoptc"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen adoptc o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 77 main me)" \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_77="$(lm_conf 77 "$LTIP")" GH_STUB_PR_77_2='{"number":77,"headRefOid":"%REMERGE_TIP%","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[]}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-adoptc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: adopted-conflict exits 0" "$rc"
chk_has "land-merge: the PR is adopted, not created" "$out" "adopted PR #77"
chk "land-merge: adopted-conflict lands on the merged head" \
  "$([ "$(git -C "$TMPD/ld-bare-adoptc" rev-parse main)" = "$(git -C "$LREPO" rev-parse HEAD)" ]; echo $?)"

echo "--- land-merge: --with-ci labels and waits before the merge and again after"
build_land_reg wci
LWT="$(cd "$TMPD/ld-repo-wci/wt" && pwd -P)"; LREPO="$TMPD/ld-repo-wci"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen wci o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=88 GH_STUB_LABELS='[{"name":"ci"}]' \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_88="$(lm_conf 88 "$LTIP")" \
  GH_STUB_PR_88_3="$(lm_conf 88 "$LTIP")" \
  GH_STUB_PR_88_4='{"number":88,"headRefOid":"%REMERGE_TIP%","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"ci","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-01-01T00:00:00Z"}]}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-wci" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" --with-ci 2>&1)"; rc=$?
chk "land-merge: with-ci conflict exits 0" "$rc"
chk "land-merge: the label sync ran twice (before the merge and on the merged head)" \
  "$([ "$(grep -c '^pr edit 88 .*add-label' "$GH_STUB_CALLS")" -eq 2 ]; echo $?)"
chk_has "land-merge: the merged head still lands under --with-ci" "$out" "merged #88"

echo "--- land-merge: a merge that un-ignores an operator file never commits it"
# origin drops the .gitignore rule covering the worktree's ignored.bin, so the merge
# surfaces it as untracked. It was ignored under the pre-merge rules: it is the operator's
# file, and the stage set must never sweep it into the merge commit that gets pushed.
build_land_reg ignx
LWT="$(cd "$TMPD/ld-repo-ignx/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
echo keep > "$LWT/ignored.bin"
land_adv ignx
git -C "$TMPD/ld-adv-ignx" rm -q .gitignore
echo b > "$TMPD/ld-adv-ignx/b.txt"
git -C "$TMPD/ld-adv-ignx" add -A; git -C "$TMPD/ld-adv-ignx" commit -qm "origin: drop the ignore rule"
git -C "$TMPD/ld-adv-ignx" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ignx" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: unignored-operator-file exits 0" "$rc"
chk "land-merge: the operator file never entered the pushed tree" \
  "$(git -C "$TMPD/ld-bare-ignx" cat-file -e main:ignored.bin 2>/dev/null && echo 1 || echo 0)"
chk "land-merge: the operator file never entered the merge commit" \
  "$(git -C "$TMPD/ld-bare-ignx" ls-tree -r main --name-only | grep -cx ignored.bin)"

echo "--- land-merge: a refusal restores without deleting an un-ignored operator file"
# Same un-ignore on origin's side, but a real conflict on base.txt: the refusal runs the
# restore, whose untracked sweep must skip what the pre-merge rules ignored.
LBRANCH='echo b > specs/b.md && bash lib/registry/feature-registry.sh generate && echo "branch edit" > base.txt' \
  build_land_reg ignr
LWT="$(cd "$TMPD/ld-repo-ignr/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
echo keep > "$LWT/ignored.bin"
land_adv ignr
git -C "$TMPD/ld-adv-ignr" rm -q .gitignore
echo "origin edit" > "$TMPD/ld-adv-ignr/base.txt"
git -C "$TMPD/ld-adv-ignr" add -A; git -C "$TMPD/ld-adv-ignr" commit -qm "origin: drop ignore, edit base"
git -C "$TMPD/ld-adv-ignr" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ignr" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: refused-unignore exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the refusal names the real conflict" "$out" "conflict in base.txt"
chk "land-merge: the un-ignored operator file survived the restore" \
  "$([ "$(cat "$LWT/ignored.bin" 2>/dev/null)" = "keep" ]; echo $?)"
chk "land-merge: refused-unignore restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"

echo "--- land-merge: a merge that would overwrite an ignored file refuses instead"
# origin now TRACKS ignored.bin while the worktree holds the operator's ignored copy.
# A default merge silently overwrites ignored files, so the cycle must refuse the path.
build_land_reg igno
LWT="$(cd "$TMPD/ld-repo-igno/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
echo operator-private > "$LWT/ignored.bin"
land_adv igno
echo upstream > "$TMPD/ld-adv-igno/ignored.bin"
git -C "$TMPD/ld-adv-igno" add -f ignored.bin
git -C "$TMPD/ld-adv-igno" commit -qm "origin: track the ignored path"
git -C "$TMPD/ld-adv-igno" push -q origin main
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-igno" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: overwrite-ignored exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk "land-merge: the ignored file kept the operator content" \
  "$([ "$(cat "$LWT/ignored.bin" 2>/dev/null)" = "operator-private" ]; echo $?)"
chk "land-merge: overwrite-ignored pushed nothing" \
  "$([ "$(git -C "$TMPD/ld-bare-igno" rev-parse feat/land 2>/dev/null)" = "$LTIP" ] \
     || ! git -C "$TMPD/ld-bare-igno" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"

echo "--- land-merge: a signal before the merge starts never runs one"
# The shim TERM's the wrap process on the cycle's second merge-base call, which is
# _merge_default's already-contains check -- inside the trap's coverage, before the
# ignored-path snapshot and the merge itself. Every git subcommand is logged, so a
# merge that ran anyway shows up by name.
build_land_reg sigp
LWT="$(cd "$TMPD/ld-repo-sigp/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen sigp o
mkdir -p "$TMPD/gshim-sigp"
cat > "$TMPD/gshim-sigp/git" <<SH
#!/usr/bin/env bash
prev=""; sub=""
for a in "\$@"; do
  case "\$prev" in -C|-c) prev=""; continue ;; esac
  case "\$a" in -C|-c) prev="\$a"; continue ;; -*) continue ;; *) sub="\$a"; break ;; esac
done
printf '%s\n' "\${sub:-?}" >> "$TMPD/glog-sigp"
if [ "\$sub" = "merge-base" ]; then
  n=\$(( \$(cat "$TMPD/gcnt-sigp" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$TMPD/gcnt-sigp"
  [ "\$n" = "2" ] && kill -TERM "\$PPID" 2>/dev/null
fi
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-sigp/git"
: > "$TMPD/glog-sigp"; rm -f "$TMPD/gcnt-sigp"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-sigp:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-sigp" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: a pre-merge signal exits 130" "$([ "$rc" -eq 130 ]; echo $?)"
chk "land-merge: the merge never ran" "$(grep -c '^merge$' "$TMPD/glog-sigp")"
chk "land-merge: the pre-merge signal left the tip alone" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: the pre-merge signal pushed nothing past the branch push" \
  "$([ "$(git -C "$TMPD/ld-bare-sigp" rev-parse feat/land)" = "$LTIP" ]; echo $?)"
chk "land-merge: the pre-merge signal left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ] \
     && [ ! -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ]; echo $?)"

echo "--- land-merge: an interrupted resolver is never GENERATOR FAILED"
# The fixture's generator rendezvouses with the test: it waits on a go file, the test
# TERM's wrap while it is blocked inside the resolve, then lets the resolver finish
# red (exit 1). An interrupt judged as a resolver failure would print GENERATOR FAILED
# or REFUSED before the cycle's 130.
LGEN='if [ -f "'"$TMPD"'/arm-sigres" ]; then touch "'"$TMPD"'/gen-waiting-sigres"; while [ ! -f "'"$TMPD"'/gen-go-sigres" ]; do sleep 0.05; done; exit 1; fi; ls "$root/specs" | LC_ALL=C sort > "$root/docs/FEATURES.md"'
build_land_reg sigres
unset LGEN
LWT="$(cd "$TMPD/ld-repo-sigres/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen sigres o
: > "$TMPD/arm-sigres"; : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
env GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-sigres" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT" > "$TMPD/out-sigres" 2>&1 &
WPID=$!
w=0; while [ ! -f "$TMPD/gen-waiting-sigres" ] && [ "$w" -lt 400 ]; do sleep 0.05; w=$(( w + 1 )); done
kill -TERM "$WPID" 2>/dev/null
: > "$TMPD/gen-go-sigres"
wait "$WPID"; rc=$?
out="$(cat "$TMPD/out-sigres")"
chk "land-merge: an interrupted resolver exits 130" "$([ "$rc" -eq 130 ]; echo $?)"
chk_no "land-merge: an interrupted resolver is no GENERATOR FAILED" "$out" "GENERATOR FAILED"
chk_no "land-merge: an interrupted resolver is no REFUSED" "$out" "REFUSED"
chk "land-merge: the interrupted resolver restored the tip" \
  "$([ "$(git -C "$LWT" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk "land-merge: the interrupted resolver left a clean worktree" \
  "$([ -z "$(git -C "$LWT" status --porcelain)" ] \
     && [ ! -e "$(git -C "$LWT" rev-parse --git-dir)/MERGE_HEAD" ]; echo $?)"

echo "--- land-merge: an unreadable merged-head rollup fails closed"
# The merge commit is already pushed when the rollup read returns nothing: an empty
# answer there is not "no checks", it is a read that failed, and the land must stop
# naming the commit it left on origin.
build_land_reg chkun
LWT="$(cd "$TMPD/ld-repo-chkun/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen chkun o
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  GH_STUB_FAIL_VIEW_42_3=1 \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-chkun" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
MOID="$(git -C "$LWT" rev-parse HEAD 2>/dev/null)"
chk "land-merge: the unreadable rollup exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the unreadable rollup names the merge commit" "$out" \
  "merged head ${MOID:0:7}"
chk "land-merge: the unreadable rollup left the merge commit on origin" \
  "$([ "$(git -C "$TMPD/ld-bare-chkun" rev-parse feat/land)" = "$MOID" ]; echo $?)"
chk "land-merge: the unreadable rollup never merged the PR" \
  "$([ "$(git -C "$TMPD/ld-bare-chkun" rev-parse main)" != "$MOID" ]; echo $?)"

echo "--- land-merge: checks still pending at the bound fail closed"
# A check that never completes is a verdict the land cannot read either: at the wait
# bound it stops and names the merge commit, the same shape as a red check.
build_land_reg chkpend
LWT="$(cd "$TMPD/ld-repo-chkpend/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen chkpend o
PEND='{"name":"build","status":"IN_PROGRESS","conclusion":null,"startedAt":"2026-09-29T10:00:00Z","completedAt":"0001-01-01T00:00:00Z","detailsUrl":"https://gh/job/9"}'
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" GH_STUB_PR_42_2="$(lm_ok 42)" \
  GH_STUB_PR_42_3="{\"number\":42,\"title\":\"x\",\"headRefName\":\"feat/land\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"UNSTABLE\",\"statusCheckRollup\":[${PEND}],\"headRefOid\":\"%REMERGE_TIP%\"}" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-chkpend" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
MOID="$(git -C "$LWT" rev-parse HEAD 2>/dev/null)"
chk "land-merge: still-pending exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: still-pending names the merge commit" "$out" \
  "merged head ${MOID:0:7}"
chk "land-merge: still-pending left the merge commit on origin" \
  "$([ "$(git -C "$TMPD/ld-bare-chkpend" rev-parse feat/land)" = "$MOID" ]; echo $?)"
chk "land-merge: still-pending never merged the PR" \
  "$([ "$(git -C "$TMPD/ld-bare-chkpend" rev-parse main)" != "$MOID" ]; echo $?)"

echo "--- land-merge: a push that landed under a foreign commit reads as landed"
# The shim lands the real push, lands a foreign commit on top of it, then reports
# failure -- the dropped-connection case where a second writer raced in. ls-remote
# shows a head that is neither the merge commit nor the old tip, but the merge commit
# is its ancestor, so the cycle calls it landed and the PR re-read names the foreign
# head instead of crying PUSH REFUSED.
build_land_reg fpush
LWT="$(cd "$TMPD/ld-repo-fpush/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
land_adv_regen fpush o
mkdir -p "$TMPD/gshim-fpush"
cat > "$TMPD/gshim-fpush/git" <<SH
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in HEAD:refs/heads/*) hit=1 ;; esac; done
if [ -n "\${hit:-}" ]; then
  "$REAL_GIT_BIN" "\$@" || exit 1
  f="$TMPD/fadv-fpush"; rm -rf "\$f"
  "$REAL_GIT_BIN" clone -q "$TMPD/ld-bare-fpush" "\$f"
  "$REAL_GIT_BIN" -C "\$f" config user.email t@t; "$REAL_GIT_BIN" -C "\$f" config user.name t; "$REAL_GIT_BIN" -C "\$f" config commit.gpgsign false
  "$REAL_GIT_BIN" -C "\$f" checkout -q -b feat/land origin/feat/land
  echo foreign > "\$f/foreign.txt"; "$REAL_GIT_BIN" -C "\$f" add foreign.txt
  "$REAL_GIT_BIN" -C "\$f" commit -qm "a foreign commit"
  "$REAL_GIT_BIN" -C "\$f" push -q origin feat/land
  exit 1
fi
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-fpush/git"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-fpush:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  GH_STUB_PR_42_2='{"number":42,"title":"x","headRefName":"feat/land","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","statusCheckRollup":[],"headRefOid":"%REMOTE_HEAD%"}' \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-fpush" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
MOID="$(git -C "$LWT" rev-parse HEAD 2>/dev/null)"
chk "land-merge: landed-under-foreign exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "land-merge: the re-read reports the foreign head" "$out" "another writer pushed"
chk_no "land-merge: a landed push is no PUSH REFUSED" "$out" "PUSH REFUSED"
chk "land-merge: the landed merge commit was not undone" \
  "$([ -n "$MOID" ] && [ "$MOID" != "$LTIP" ] \
     && git -C "$TMPD/ld-bare-fpush" merge-base --is-ancestor "$MOID" feat/land 2>/dev/null; echo $?)"

echo "--- land-merge: --verify with no value exits 64"
out="$("$WRAP" land --verify 2>&1)"; rc=$?
chk "land-merge: bare --verify exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk_has "land-merge: bare --verify names the missing value" "$out" "--verify needs a value"
out="$("$WRAP" land "$TMPD" --verify 2>&1)"; rc=$?
chk "land-merge: trailing --verify exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
chk "land-merge: the usage text documents --verify" \
  "$(sed -n '2,31p' "$WRAP" | grep -q -- '--verify'; echo $?)"


echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap-land: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap-land: all $PASS passed"
