#!/usr/bin/env bash
# test-wrap-land.sh -- the land cases; split out of tests/test-wrap.sh.
# Shares the harness in tests/lib/wrap-stub.sh (gh stub, fixtures, chk).
# modules under test: lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh
#
# Sections: every `sec_*` function below is one `=== ... ===` block. With no LAND_SECTION set
# this file is a driver (tests/lib/land-sections.sh): it runs the sections as parallel child
# processes (LAND_JOBS, default 4), each with its own TMPD, skips a section whose inputs are
# unchanged since its last pass (LAND_CACHE=0 or CI turns that off), and prints the same
# final line the serial file printed.
#   LAND_ONLY=<ERE> bash tests/test-wrap-land.sh   only sections whose id or title matches
#   bash tests/test-wrap-land.sh --list            the section ids and titles
#   LAND_SECTION=sec_<id> bash tests/test-wrap-land.sh   one section in this process (what a child runs)
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -z "${LAND_SECTION:-}" ]; then
  # A section run (LAND_ONLY) or --list is light: no lock.
  if [ -z "${LAND_ONLY:-}" ] && [ "${1:-}" != "--list" ]; then
    source "$KIT_DIR/tests/lib/run-lock.sh"; run_lock_exec "$KIT_DIR/tests/$(basename "${BASH_SOURCE[0]}")" "$@"
  fi
  source "$KIT_DIR/tests/lib/land-sections.sh"
  land_drive "$KIT_DIR/tests/$(basename "${BASH_SOURCE[0]}")" "$@"; exit $?
fi
source "$KIT_DIR/tests/lib/wrap-stub.sh"

# A fixture commit can spawn a detached `git maintenance`, which creates and removes
# objects/maintenance.lock while land_cached's `cp -R` copies the template (a flake under load).
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=maintenance.auto GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=gc.auto GIT_CONFIG_VALUE_1=0

# Helpers more than one section uses. Everything else a section needs is defined inside it.
open_pr_json() { # open_pr_json <number> <base> <author> [isDraft] [isCrossRepo]
  printf '[{"number":%s,"baseRefName":"%s","author":{"login":"%s"},"isDraft":%s,"isCrossRepository":%s}]' \
    "$1" "$2" "$3" "${4:-false}" "${5:-false}"
}
two_open_pr_json() {
  printf '[{"number":%s,"baseRefName":"main","author":{"login":"me"},"isDraft":false,"isCrossRepository":false},{"number":%s,"baseRefName":"main","author":{"login":"me"},"isDraft":false,"isCrossRepository":false}]' "$1" "$2"
}
# ---------------------------------------------------------------------------
# land-merge fixtures: the registry layout (the generator is a stub listing
# specs/), a clone on feat/land in its own worktree, and a second clone that
# advances origin/main. Every conflicting case fails the first `pr merge` with a
# non-transient refusal, then answers CONFLICTING at the pushed head and
# MERGEABLE at the re-merge head (%REMERGE_TIP% resolves to whatever feat/land
# points at when the read happens -- the old tip before the push, the merge
# commit after it).
_build_land_reg() {
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
build_land_reg() { land_cached _build_land_reg "$@"; }   # build_land_reg <name>
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

# ===========================================================================
sec_happy() {
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
} # end sec_happy

# ===========================================================================
sec_title() {
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
} # end sec_title

# ===========================================================================
sec_shiprec() {
echo "=== land: the ship-gate record a land writes ==="
# ===========================================================================
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
} # end sec_shiprec

# ===========================================================================
sec_adopt() {
echo "=== land: adopting an operator-owned open PR for the branch (SPEC-299) ==="
# ===========================================================================
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
} # end sec_adopt

sec_merge1() {
echo "=== land-merge: a CONFLICTING land merges origin/<def> in, then retries (part 1 of 4) ==="
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

} # end sec_merge1

# ===========================================================================
sec_merge2() {
echo "=== land-merge: a CONFLICTING land merges origin/<def> in, then retries (part 2 of 4) ==="
# ===========================================================================
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
_build_land_board() {
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
build_land_board() { land_cached _build_land_board "$@"; }   # build_land_board <name>
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

} # end sec_merge2

# ===========================================================================
sec_merge3() {
echo "=== land-merge: a CONFLICTING land merges origin/<def> in, then retries (part 3 of 4) ==="
# ===========================================================================
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

} # end sec_merge3

# ===========================================================================
sec_merge4() {
echo "=== land-merge: a CONFLICTING land merges origin/<def> in, then retries (part 4 of 4) ==="
# ===========================================================================
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
# The shim TERM's the wrap process on the second `merge-base --is-ancestor origin/main <sha>`
# call, which is _merge_default's already-contains check -- inside the trap's coverage,
# before the ignored-path snapshot and the merge itself. The first such call is the cycle's
# own route-out, before the trap; the landed-branch proof uses other argv, so skipping the
# proof cannot move the match. Every git subcommand is logged, so a merge that ran anyway
# shows up by name, and a fired marker shows the signal really came from that call.
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
if [ "\$sub" = "merge-base" ] && [[ " \$* " == *" --is-ancestor origin/main "* ]]; then
  n=\$(( \$(cat "$TMPD/gcnt-sigp" 2>/dev/null || echo 0) + 1 )); echo "\$n" > "$TMPD/gcnt-sigp"
  [ "\$n" = "2" ] && { : > "$TMPD/gfired-sigp"; kill -TERM "\$PPID" 2>/dev/null; }
fi
exec "$REAL_GIT_BIN" "\$@"
SH
chmod +x "$TMPD/gshim-sigp/git"
: > "$TMPD/glog-sigp"; rm -f "$TMPD/gcnt-sigp" "$TMPD/gfired-sigp"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(PATH="$TMPD/gshim-sigp:$PATH" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_MERGE_FAILS=1 GH_STUB_MERGE_ERR='Pull Request is not mergeable' \
  GH_STUB_PR_42="$(lm_conf 42 "$LTIP")" \
  KIT_WRAP_CI_GRACE_SECS=0 KIT_WRAP_CARRY_CHECKS_SECS=0 \
  GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-sigp" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
chk "land-merge: a pre-merge signal exits 130" "$([ "$rc" -eq 130 ]; echo $?)"
chk "land-merge: the signal fired on the already-contains check" "$([ -e "$TMPD/gfired-sigp" ]; echo $?)"
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


} # end sec_merge4

# ===========================================================================
sec_landed() {
echo "=== land: a branch already landed on the default branch is recognized (SPEC-376) ==="
# ===========================================================================
# A git shim forces ONE subcommand (matched on an argv substring) to a chosen exit code and
# execs the real git for everything else, so a read that cannot fail on a local remote
# (ls-remote, fetch) can be made to fail the way a network or auth error does.
REAL_GIT="$(command -v git)"; export REAL_GIT
mkdir -p "$TMPD/gitshim" "$TMPD/gitlate"
cat > "$TMPD/gitshim/git" <<'SHIM'
#!/usr/bin/env bash
args=("$@"); i=0
while [ "$i" -lt "$#" ]; do
  case "${args[$i]}" in -C|-c) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
done
if [ "${args[$i]:-}" = "${SHIM_SUB:-}" ] && [[ " $* " == *"${SHIM_MATCH:-}"* ]]; then
  echo "shim: forced ${SHIM_SUB} failure" >&2; exit "${SHIM_RC:-1}"
fi
exec "$REAL_GIT" "$@"
SHIM
# The late shim commits into $LATE_WT while `pull` runs: after the proof and the origin read,
# before the removal, which is the window the tidy's own recheck exists for. It also dirties
# $DIRTY_WT while the proof's ancestor probe runs, the window the first recheck covers.
cat > "$TMPD/gitlate/git" <<'SHIM'
#!/usr/bin/env bash
args=("$@"); i=0
while [ "$i" -lt "$#" ]; do
  case "${args[$i]}" in -C|-c) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
done
if [ "${args[$i]:-}" = "merge-base" ] && [[ " $* " == *" --is-ancestor "* ]] && [ -n "${DIRTY_WT:-}" ]; then
  echo x > "$DIRTY_WT/dirty.txt"
fi
if [ "${args[$i]:-}" = "ls-remote" ] && [ -n "${LS_WT:-}" ]; then
  echo x > "$LS_WT/ls-late.txt"
fi
if [ "${args[$i]:-}" = "pull" ] && [ -n "${LATE_WT:-}" ]; then
  echo late > "$LATE_WT/late.txt"; "$REAL_GIT" -C "$LATE_WT" add -A
  "$REAL_GIT" -C "$LATE_WT" commit -qm "late change"
fi
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$TMPD/gitshim/git" "$TMPD/gitlate/git"

# land_squashed <name> [--gh|--repush] -- a land fixture whose branch is pushed, and whose
# content reached origin/main as a SQUASH: a new commit with the branch's net change, no
# ancestry to the branch. Bare mode: nothing else landed since (the absorbed proof holds).
# --gh: one more commit edits the same path afterwards (absorbed fails; gh's record is the
# proof). --repush: the branch carries one more commit than what squashed.
land_squashed() {
  local name="$1" mode="${2:-}" wt="$TMPD/ld-repo-$1/wt" adv
  if [ "$mode" = "--repush" ]; then build_land "$name" "" feat/land "feat: b" "feat: c"
  else build_land "$name"; fi
  git -C "$wt" push -q origin feat/land
  land_adv "$name"
  adv="$TMPD/ld-adv-$name"
  if [ "$mode" = "--repush" ]; then echo "line 1" > "$adv/multi.txt"
  else echo "pr change" > "$adv/pr-file.txt"; fi
  git -C "$adv" add -A; git -C "$adv" commit -qm "squash of the branch"
  if [ "$mode" = "--gh" ]; then
    echo "later edit" >> "$adv/pr-file.txt"; git -C "$adv" add -A; git -C "$adv" commit -qm "later change"
  fi
  git -C "$adv" push -q origin main
}
merged_json() { # merged_json <head oid> -- gh's one merged-PR record into main
  printf '[{"headRefOid":"%s","baseRefName":"main","mergedAt":"2026-09-30T00:00:00Z"}]' "$1"
}

echo "--- TA1: a zero-commit worktree still refuses at ahead == 0, untouched"
build_land tafresh
LWT_TA1="$(cd "$TMPD/ld-repo-tafresh/wt" && pwd -P)"
git -C "$LWT_TA1" reset -q --hard origin/main
out="$("$WRAP" land "$LWT_TA1" 2>&1)"; rc=$?
chk "TA1: a zero-commit worktree exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "TA1: names the missing commits" "$out" "has no commits ahead of origin/main"
chk_no "TA1: never reaches the landed path" "$out" "already landed"
chk "TA1: the worktree is still there" "$([ -d "$LWT_TA1" ]; echo $?)"

echo "--- TA3: ahead reads full refs, so a tag named origin/main cannot fake a zero count"
build_land tatag
LWT_TA3="$(cd "$TMPD/ld-repo-tatag/wt" && pwd -P)"
git -C "$LWT_TA3" tag origin/main HEAD 2>/dev/null
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=43 GH_STUB_LAND_REPO="$LWT_TA3" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-tatag" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TA3" 2>&1)"; rc=$?
chk_no "TA3: a shadowing tag never reads as no commits ahead" "$out" "has no commits ahead"
chk_has "TA3: the branch is pushed" "$out" "pushed feat/land"

echo "--- TA2: an ancestor-shaped proof is treated as no proof at this call site"
build_land taanc
LWT_TA2="$(cd "$TMPD/ld-repo-taanc/wt" && pwd -P)"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=44 GH_STUB_LAND_REPO="$LWT_TA2" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-taanc" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main bash -c \
  'f="$1"; w="$2"; set --; source "$f"; _merge_proof() { printf "ancestor of origin/main\n"; }; cmd_land "$w"' \
  _ "$KIT_DIR/lib/wrap/wrap.sh" "$LWT_TA2" 2>&1)"; rc=$?
chk_no "TA2: an ancestor proof never prints already landed" "$out" "already landed"
chk_has "TA2: land takes the unchanged path and opens the PR" "$out" "opened PR #44"

echo "--- TB1: the origin ref GitHub already deleted reads as gone, never FAILED delete"
build_land tb1
LWT_TB1="$(cd "$TMPD/ld-repo-tb1/wt" && pwd -P)"
out="$(GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=45 GH_STUB_LAND_REPO="$LWT_TB1" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-tb1" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main GH_STUB_MERGE_DELETES_BRANCH=1 "$WRAP" land "$LWT_TB1" 2>&1)"; rc=$?
chk "TB1: land exits 0" "$rc"
chk_has "TB1: the missing origin ref is reported gone" "$out" "feat/land already gone from origin"
chk_no "TB1: never FAILED delete" "$out" "FAILED delete"
chk "TB1: the worktree is removed" "$([ ! -e "$LWT_TB1" ]; echo $?)"

echo "--- TB2: an ls-remote failure other than exit 2 is never read as gone"
build_land tb2
LWT_TB2="$(cd "$TMPD/ld-repo-tb2/wt" && pwd -P)"
out="$(PATH="$TMPD/gitshim:$PATH" SHIM_SUB=ls-remote SHIM_MATCH="refs/heads/feat/land" SHIM_RC=1 \
  GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=46 GH_STUB_LAND_REPO="$LWT_TB2" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-tb2" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main GH_STUB_MERGE_DELETES_BRANCH=1 "$WRAP" land "$LWT_TB2" 2>&1)"; rc=$?
chk_has "TB2: the delete is still attempted and reported failed" "$out" "FAILED delete feat/land on origin"
chk_no "TB2: never called gone" "$out" "already gone from origin"

echo "--- TC1: content already on origin/main, no PR opened, no push, clean tidy"
land_squashed tc1
LREPO_TC1="$TMPD/ld-repo-tc1"; LWT_TC1="$(cd "$LREPO_TC1/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$("$WRAP" land "$LWT_TC1" 2>&1)"; rc=$?
CALLS_TC1="$(cat "$GH_STUB_CALLS")"
chk "TC1: land exits 0" "$rc"
chk_has "TC1: reports the absorbed proof" "$out" "already landed: content already on origin/main; nothing to push, no PR opened"
chk_no "TC1: never calls pr create" "$CALLS_TC1" "pr create"
chk_no "TC1: never pushes the branch" "$out" "pushed feat/land"
chk_has "TC1: deletes the matching origin branch" "$out" "deleted feat/land on origin"
chk "TC1: the origin branch is gone" \
  "$(git -C "$TMPD/ld-bare-tc1" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk "TC1: the worktree is removed" "$([ ! -e "$LWT_TC1" ]; echo $?)"
chk "TC1: the local branch is deleted" \
  "$(git -C "$LREPO_TC1" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"

echo "--- TC2: a later edit to the same path, gh's squash record is the proof"
land_squashed tc2 --gh
LREPO_TC2="$TMPD/ld-repo-tc2"; LWT_TC2="$(cd "$LREPO_TC2/wt" && pwd -P)"
LTIP_TC2="$(git -C "$LWT_TC2" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGED_feat_land="$(merged_json "$LTIP_TC2")" "$WRAP" land "$LWT_TC2" 2>&1)"; rc=$?
chk "TC2: land exits 0" "$rc"
chk_has "TC2: reports the gh squash proof" "$out" "already landed: squash-merged per gh"
chk_no "TC2: never calls pr create" "$(cat "$GH_STUB_CALLS")" "pr create"
chk_has "TC2: deletes the origin branch" "$out" "deleted feat/land on origin"
chk "TC2: the worktree is removed" "$([ ! -e "$LWT_TC2" ]; echo $?)"

echo "--- TC4: re-pushed with a commit past what merged still opens a fresh PR"
land_squashed tc4 --repush
LREPO_TC4="$TMPD/ld-repo-tc4"; LWT_TC4="$(cd "$LREPO_TC4/wt" && pwd -P)"
OLD_TC4="$(git -C "$LWT_TC4" rev-parse HEAD~1)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_MERGED_feat_land="$(merged_json "$OLD_TC4")" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=47 \
  GH_STUB_LAND_REPO="$LWT_TC4" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-tc4" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  "$WRAP" land "$LWT_TC4" 2>&1)"; rc=$?
chk_no "TC4: never claims the branch landed" "$out" "already landed"
chk_has "TC4: opens a PR for the new commit" "$(cat "$GH_STUB_CALLS")" "pr create"
chk_has "TC4: reports the new PR" "$out" "opened PR #47"

echo "--- TC5: a failed open-PR lookup refuses BEFORE the branch is pushed"
build_land tc5
LWT_TC5="$(cd "$TMPD/ld-repo-tc5/wt" && pwd -P)"
out="$(GH_STUB_LIST_RC=1 "$WRAP" land "$LWT_TC5" 2>&1)"; rc=$?
chk "TC5: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TC5: names the lookup" "$out" "open-PR lookup for feat/land failed"
chk "TC5: origin never received the branch" \
  "$(git -C "$TMPD/ld-bare-tc5" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"

echo "--- TD1: the origin branch already gone is fine, no delete attempted"
land_squashed td1
LWT_TD1="$(cd "$TMPD/ld-repo-td1/wt" && pwd -P)"
git -C "$TMPD/ld-bare-td1" update-ref -d refs/heads/feat/land
out="$("$WRAP" land "$LWT_TD1" 2>&1)"; rc=$?
chk "TD1: land exits 0" "$rc"
chk_has "TD1: still reports already landed" "$out" "already landed: content already on origin/main"
chk_has "TD1: reports the ref gone from origin" "$out" "feat/land already gone from origin"
chk_no "TD1: never FAILED delete" "$out" "FAILED delete"
chk "TD1: the worktree is removed" "$([ ! -e "$LWT_TD1" ]; echo $?)"

echo "--- TD2: origin's branch moved past the proven tip: refuse, touch nothing"
land_squashed td2
LREPO_TD2="$TMPD/ld-repo-td2"; LWT_TD2="$(cd "$LREPO_TD2/wt" && pwd -P)"
LTIP_TD2="$(git -C "$LWT_TD2" rev-parse HEAD)"
git clone -q "$TMPD/ld-bare-td2" "$TMPD/ld-third-td2"; gitc "$TMPD/ld-third-td2"
git -C "$TMPD/ld-third-td2" checkout -q feat/land
echo "pushed elsewhere" > "$TMPD/ld-third-td2/extra.txt"
git -C "$TMPD/ld-third-td2" add -A; git -C "$TMPD/ld-third-td2" commit -qm "someone else"
git -C "$TMPD/ld-third-td2" push -q origin feat/land
OTHER_TD2="$(git -C "$TMPD/ld-bare-td2" rev-parse feat/land)"
out="$("$WRAP" land "$LWT_TD2" 2>&1)"; rc=$?
chk "TD2: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TD2: names the origin sha" "$out" "${OTHER_TD2:0:7}"
chk_has "TD2: says differs from the proven tip" "$out" "differs from the proven ${LTIP_TD2:0:7}"
chk_no "TD2: never claims already landed" "$out" "already landed"
chk "TD2: origin's branch is untouched" "$([ "$(git -C "$TMPD/ld-bare-td2" rev-parse feat/land)" = "$OTHER_TD2" ]; echo $?)"
chk "TD2: the worktree and branch stay" "$([ -d "$LWT_TD2" ] && git -C "$LREPO_TD2" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TD3: a failed origin read fails CLOSED"
land_squashed td3
LREPO_TD3="$TMPD/ld-repo-td3"; LWT_TD3="$(cd "$LREPO_TD3/wt" && pwd -P)"
out="$(PATH="$TMPD/gitshim:$PATH" SHIM_SUB=ls-remote SHIM_MATCH="refs/heads/feat/land" SHIM_RC=1 \
  "$WRAP" land "$LWT_TD3" 2>&1)"; rc=$?
chk "TD3: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TD3: says the origin branch could not be confirmed" "$out" "origin/feat/land could not be confirmed"
chk_no "TD3: never claims already landed" "$out" "already landed"
chk "TD3: origin's branch is untouched" "$(git -C "$TMPD/ld-bare-td3" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"
chk "TD3: the worktree and branch stay" "$([ -d "$LWT_TD3" ] && git -C "$LREPO_TD3" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TD5: a failed fetch skips the proof check and takes the unchanged path"
land_squashed td5
LWT_TD5="$(cd "$TMPD/ld-repo-td5/wt" && pwd -P)"
# The clone already knows the squash, so a skipped check is the only thing keeping the
# absorbed proof from firing off cached refs.
git -C "$TMPD/ld-repo-td5" fetch -q origin
: > "$GH_STUB_CALLS"
out="$(PATH="$TMPD/gitshim:$PATH" SHIM_SUB=fetch SHIM_MATCH=" origin main" SHIM_RC=1 GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=48 \
  "$WRAP" land "$LWT_TD5" 2>&1)"; rc=$?
chk_no "TD5: no already landed line" "$out" "already landed"
chk_has "TD5: the unchanged path pushes" "$out" "pushed feat/land"
chk_has "TD5: the unchanged path opens the PR" "$(cat "$GH_STUB_CALLS")" "pr create"

echo "--- TE1: a proof alongside a still-open PR reports both and refuses, touching nothing"
land_squashed te1
LREPO_TE1="$TMPD/ld-repo-te1"; LWT_TE1="$(cd "$LREPO_TE1/wt" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_HEAD_feat_land="$(open_pr_json 61 main me)" "$WRAP" land "$LWT_TE1" 2>&1)"; rc=$?
CALLS_TE1="$(cat "$GH_STUB_CALLS")"
chk "TE1: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TE1: reports the landed proof" "$out" "already landed: content already on origin/main"
chk_has "TE1: reports the open PR" "$out" "PR #61 still open for feat/land: left untouched"
chk_no "TE1: never creates a PR" "$CALLS_TE1" "pr create"
chk_no "TE1: never merges" "$CALLS_TE1" "pr merge"
chk "TE1: the origin branch is still there" "$(git -C "$TMPD/ld-bare-te1" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"
chk "TE1: the worktree and branch stay" "$([ -d "$LWT_TE1" ] && git -C "$LREPO_TE1" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TF1: a live Agent-tool lock does not block the already-landed tidy"
land_squashed tf1
LREPO_TF1="$TMPD/ld-repo-tf1"; LWT_TF1="$(cd "$LREPO_TF1/wt" && pwd -P)"
git -C "$LREPO_TF1" worktree lock --reason "claude agent test (pid $$ start x)" "$LWT_TF1"
out="$("$WRAP" land "$LWT_TF1" 2>&1)"; rc=$?
chk "TF1: land exits 0 despite the live lock" "$rc"
chk_has "TF1: reports already landed" "$out" "already landed: content already on origin/main"
chk "TF1: the locked worktree is removed" "$([ ! -e "$LWT_TF1" ]; echo $?)"

echo "--- TG1: the tidy's own recheck refuses a removal when the tip moved after the proof"
land_squashed tg1
LREPO_TG1="$TMPD/ld-repo-tg1"; LWT_TG1="$(cd "$LREPO_TG1/wt" && pwd -P)"
out="$(PATH="$TMPD/gitlate:$PATH" LATE_WT="$LWT_TG1" "$WRAP" land "$LWT_TG1" 2>&1)"; rc=$?
chk "TG1: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TG1: says the branch changed since it was checked" "$out" "feat/land changed since it was checked; worktree and branch left in place"
chk "TG1: the worktree survives" "$([ -d "$LWT_TG1" ]; echo $?)"
chk "TG1: the branch survives" "$(git -C "$LREPO_TG1" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TG2: a tree that went dirty while the proof was read refuses before anything moves"
land_squashed tg2
LREPO_TG2="$TMPD/ld-repo-tg2"; LWT_TG2="$(cd "$LREPO_TG2/wt" && pwd -P)"
out="$(PATH="$TMPD/gitlate:$PATH" DIRTY_WT="$LWT_TG2" "$WRAP" land "$LWT_TG2" 2>&1)"; rc=$?
chk "TG2: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TG2: says the branch changed while the proof was read" "$out" "feat/land changed while the merge proof was read"
chk_no "TG2: never claims already landed" "$out" "already landed"
chk "TG2: origin's branch is untouched" "$(git -C "$TMPD/ld-bare-tg2" rev-parse --verify feat/land >/dev/null 2>&1; echo $?)"
chk "TG2: the worktree survives" "$([ -d "$LWT_TG2" ]; echo $?)"

echo "--- TG3: a file written after the proof but before the tidy refuses the removal"
land_squashed tg3
LREPO_TG3="$TMPD/ld-repo-tg3"; LWT_TG3="$(cd "$LREPO_TG3/wt" && pwd -P)"
out="$(PATH="$TMPD/gitlate:$PATH" LS_WT="$LWT_TG3" "$WRAP" land "$LWT_TG3" 2>&1)"; rc=$?
chk "TG3: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TG3: says the branch changed since it was checked" "$out" "feat/land changed since it was checked"
chk_has "TG3: names the new path" "$out" "ls-late.txt"
chk "TG3: the late file survives" "$([ -f "$LWT_TG3/ls-late.txt" ]; echo $?)"
chk "TG3: the worktree survives" "$([ -d "$LWT_TG3" ]; echo $?)"
chk "TG3: the branch survives" "$(git -C "$LREPO_TG3" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TG4: a file written during the merge refuses the removal on the merge path"
mkdir -p "$TMPD/ghlate"
cat > "$TMPD/ghlate/gh" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "pr" ] && [ "\$2" = "merge" ] && [ -n "\${MERGE_WT:-}" ]; then echo x > "\$MERGE_WT/merge-late.txt"; fi
exec "$TMPD/stub/gh" "\$@"
SHIM
chmod +x "$TMPD/ghlate/gh"
build_land tg4
LREPO_TG4="$TMPD/ld-repo-tg4"; LWT_TG4="$(cd "$LREPO_TG4/wt" && pwd -P)"
out="$(PATH="$TMPD/ghlate:$PATH" MERGE_WT="$LWT_TG4" GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 \
  GH_STUB_LAND_REPO="$LWT_TG4" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-tg4" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_TG4" 2>&1)"; rc=$?
chk "TG4: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TG4: says the branch changed since it was checked" "$out" "feat/land changed since it was checked"
chk_has "TG4: names the new path" "$out" "merge-late.txt"
chk "TG4: the late file survives" "$([ -f "$LWT_TG4/merge-late.txt" ]; echo $?)"
chk "TG4: the worktree survives" "$([ -d "$LWT_TG4" ]; echo $?)"
chk "TG4: the branch survives" "$(git -C "$LREPO_TG4" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TH: the origin read matches refs/heads/<branch> exactly"
# A git shim that answers every ls-remote with $LS_OUT, so a tag named like a branch (which
# ls-remote's tail-matching pattern also lists) can be put in any position.
mkdir -p "$TMPD/gitls"
cat > "$TMPD/gitls/git" <<'SHIM'
#!/usr/bin/env bash
args=("$@"); i=0
while [ "$i" -lt "$#" ]; do
  case "${args[$i]}" in -C|-c) i=$((i + 2)) ;; -*) i=$((i + 1)) ;; *) break ;; esac
done
if [ "${args[$i]:-}" = "ls-remote" ] && [ -n "${LS_OUT+x}" ]; then
  [ -z "$LS_OUT" ] || printf '%b\n' "$LS_OUT"
  exit "${LS_RC:-0}"
fi
exec "$REAL_GIT" "$@"
SHIM
chmod +x "$TMPD/gitls/git"
OTHER_SHA=2222222222222222222222222222222222222222

echo "--- TH1: a tag carrying the tip ahead of a branch that differs still refuses"
land_squashed th1
LREPO_TH1="$TMPD/ld-repo-th1"; LWT_TH1="$(cd "$LREPO_TH1/wt" && pwd -P)"; TIP_TH1="$(git -C "$LWT_TH1" rev-parse HEAD)"
out="$(PATH="$TMPD/gitls:$PATH" LS_OUT="${TIP_TH1}\trefs/tags/refs/heads/feat/land\n${OTHER_SHA}\trefs/heads/feat/land" \
  "$WRAP" land "$LWT_TH1" 2>&1)"; rc=$?
chk "TH1: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TH1: says the origin branch differs from the proven tip" "$out" "differs from the proven ${TIP_TH1:0:7}"
chk "TH1: the worktree and branch stay" "$([ -d "$LWT_TH1" ] && git -C "$LREPO_TH1" rev-parse --verify -q feat/land >/dev/null; echo $?)"

echo "--- TH2: a tag with another sha ahead of the matching branch does not refuse"
land_squashed th2
LREPO_TH2="$TMPD/ld-repo-th2"; LWT_TH2="$(cd "$LREPO_TH2/wt" && pwd -P)"; TIP_TH2="$(git -C "$LWT_TH2" rev-parse HEAD)"
out="$(PATH="$TMPD/gitls:$PATH" LS_OUT="${OTHER_SHA}\trefs/tags/refs/heads/feat/land\n${TIP_TH2}\trefs/heads/feat/land" \
  "$WRAP" land "$LWT_TH2" 2>&1)"; rc=$?
chk "TH2: exits 0" "$rc"
chk "TH2: the worktree is removed" "$([ ! -e "$LWT_TH2" ]; echo $?)"

echo "--- TH3: only a tag matches, so the branch reads as absent"
land_squashed th3
LREPO_TH3="$TMPD/ld-repo-th3"; LWT_TH3="$(cd "$LREPO_TH3/wt" && pwd -P)"; TIP_TH3="$(git -C "$LWT_TH3" rev-parse HEAD)"
out="$(PATH="$TMPD/gitls:$PATH" LS_OUT="${TIP_TH3}\trefs/tags/refs/heads/feat/land" "$WRAP" land "$LWT_TH3" 2>&1)"; rc=$?
chk "TH3: exits 0" "$rc"
chk_has "TH3: the branch reads as gone from origin" "$out" "feat/land already gone from origin"

echo "--- TH4: two lines for the exact ref refuse"
land_squashed th4
LREPO_TH4="$TMPD/ld-repo-th4"; LWT_TH4="$(cd "$LREPO_TH4/wt" && pwd -P)"; TIP_TH4="$(git -C "$LWT_TH4" rev-parse HEAD)"
out="$(PATH="$TMPD/gitls:$PATH" LS_OUT="${TIP_TH4}\trefs/heads/feat/land\n${TIP_TH4}\trefs/heads/feat/land" "$WRAP" land "$LWT_TH4" 2>&1)"; rc=$?
chk "TH4: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "TH4: says the origin branch could not be confirmed" "$out" "origin/feat/land could not be confirmed"
chk "TH4: the worktree and branch stay" "$([ -d "$LWT_TH4" ] && git -C "$LREPO_TH4" rev-parse --verify -q feat/land >/dev/null; echo $?)"

} # end sec_landed

# ===========================================================================
sec_prgate() {
echo "=== land: no title-only PR body on a template repo; no merge before the PR's checks report ==="
# ===========================================================================
# pg_build <name> [template-path] [workflow-body] -- build_land plus an optional committed PR
# template and an optional committed .github/workflows/pr.yml, so the branch carries them.
pg_build() {
  local name="$1" tpl="${2:-}" wf="${3:-}" wt="$TMPD/ld-repo-$1/wt"
  build_land "$name"
  if [ -n "$tpl" ]; then
    mkdir -p "$wt/$(dirname "$tpl")"; printf '## What and why\n\n## How I verified it\n' > "$wt/$tpl"
  fi
  if [ -n "$wf" ]; then
    mkdir -p "$wt/.github/workflows"; printf '%s\n' "$wf" > "$wt/.github/workflows/pr.yml"
  fi
  git -C "$wt" add -A; git -C "$wt" commit -qm "chore: pr gate fixture" >/dev/null 2>&1
  PG_WT="$(cd "$wt" && pwd -P)"
}
# pg_land <name> [extra env as VAR=val ...] -- one land with the standard stub wiring
pg_land() {
  local name="$1"; shift
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  env GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$PG_WT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-$name" \
    GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main KIT_WRAP_LAND_GRACE_SECS=30 KIT_WRAP_CARRY_CHECKS_SECS=0 \
    PATH="$TMPD/nosleep:$PATH" "$@" "$WRAP" land "$PG_WT" 2>&1
}
PG_WF=$'on:\n  pull_request:\n    branches: [main]\njobs:\n  x:\n    runs-on: [self-hosted]'
PG_RED='{"number":42,"statusCheckRollup":[{"name":"PR evidence","status":"COMPLETED","conclusion":"FAILURE","completedAt":"2026-01-01T00:00:00Z"}]}'
PG_GREEN='{"number":42,"statusCheckRollup":[{"name":"PR evidence","status":"COMPLETED","conclusion":"SUCCESS","completedAt":"2026-01-01T00:00:00Z"}]}'

echo "--- PG1: a repo with a PR template and no --body-file refuses before push and before pr create"
pg_build pg1 .github/PULL_REQUEST_TEMPLATE.md
out="$(pg_land pg1)"; rc=$?
chk "PG1: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "PG1: names the template path" "$out" ".github/PULL_REQUEST_TEMPLATE.md exists"
chk_has "PG1: tells the operator to pass --body-file" "$out" "pass --body-file"
chk_no "PG1: never calls pr create" "$(cat "$GH_STUB_CALLS")" "pr create"
chk "PG1: nothing was pushed" "$(git -C "$TMPD/ld-bare-pg1" rev-parse --verify -q feat/land >/dev/null && echo 1 || echo 0)"
chk "PG1: the worktree stays" "$([ -d "$PG_WT" ]; echo $?)"

echo "--- PG1b: a lowercase template under docs/ is found too; --body-file is accepted"
pg_build pg1b docs/pull_request_template.md
out="$(pg_land pg1b)"; rc=$?
chk "PG1b: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "PG1b: names the docs/ template" "$out" "docs/pull_request_template.md exists"
printf '## What and why\nx\n## How I verified it\ny\n' > "$TMPD/pg1b-body.md"
: > "$GH_STUB_CALLS"
out="$(env GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$PG_WT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-pg1b" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$PG_WT" --body-file "$TMPD/pg1b-body.md" 2>&1)"; rc=$?
chk "PG1b: with --body-file the land passes" "$rc"
chk_has "PG1b: pr create carried the body file" "$(cat "$GH_STUB_CALLS")" "--body-file $TMPD/pg1b-body.md"

echo "--- PG2: no template keeps today's title-as-body fallback"
pg_build pg2
out="$(pg_land pg2)"; rc=$?
chk "PG2: exits 0" "$rc"
chk_has "PG2: pr create used the title as the body" "$(cat "$GH_STUB_CALLS")" "--body feat: the landed change"

echo "--- PG3: a red check refuses the merge and leaves the PR open"
pg_build pg3 "" "$PG_WF"
out="$(pg_land pg3 GH_STUB_PR_42="$PG_RED")"; rc=$?
chk "PG3: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "PG3: names the failed check" "$out" "MERGE REFUSED #42: checks failed: PR evidence; PR left open"
chk_no "PG3: never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"
chk "PG3: the worktree stays" "$([ -d "$PG_WT" ]; echo $?)"

echo "--- PG4: green checks merge"
pg_build pg4 "" "$PG_WF"
out="$(pg_land pg4 GH_STUB_PR_42="$PG_GREEN")"; rc=$?
chk "PG4: exits 0" "$rc"
chk_has "PG4: merged" "$out" "merged #42 ("

echo "--- PG4b: a check that registers late is waited for, then judged"
pg_build pg4b "" "$PG_WF"
out="$(pg_land pg4b GH_STUB_PR_42='{"number":42,"statusCheckRollup":[]}' GH_STUB_PR_42_3="$PG_RED")"; rc=$?
chk "PG4b: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "PG4b: the late red check refuses the merge" "$out" "checks failed: PR evidence"
chk_no "PG4b: never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- PG4c: a check still pending at the bound refuses"
pg_build pg4c "" "$PG_WF"
out="$(pg_land pg4c GH_STUB_PR_42='{"number":42,"statusCheckRollup":[{"name":"PR evidence","status":"IN_PROGRESS","conclusion":""}]}')"; rc=$?
chk "PG4c: exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "PG4c: says still pending" "$out" "checks still pending"
chk_no "PG4c: never merges" "$(cat "$GH_STUB_CALLS")" "pr merge"

echo "--- PG5: no pull_request workflow pays nothing: no rollup read before the merge"
pg_build pg5 "" $'on:\n  push:\n    branches: [main]\njobs:\n  x:\n    runs-on: [self-hosted]'
out="$(pg_land pg5 GH_STUB_PR_42="$PG_RED")"; rc=$?
chk "PG5: exits 0" "$rc"
chk "PG5: no statusCheckRollup read" "$(grep -q 'statusCheckRollup' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk_has "PG5: merged" "$out" "merged #42 ("
} # end sec_prgate

sec_proofbody() {
echo "=== land: the proof of done reaches the PR body and the closing block ==="
# ===========================================================================
# pb_build <name> -- build_land plus a committed proof file that holds captured output
pb_build() {
  local wt="$TMPD/ld-repo-$1/wt"
  build_land "$1"
  mkdir -p "$wt/docs/verification"
  printf '# Verification\nNEGATIVE CONTROL\nCommand: `bash t.sh`\nExit: 0\nOutput:\nt: all 3 passed\nVerdict: PASS\n' \
    > "$wt/docs/verification/land.md"
  git -C "$wt" add -A; git -C "$wt" commit -qm "docs: proof of done" >/dev/null 2>&1
  PB_WT="$(cd "$wt" && pwd -P)"
}
# pb_land <name> [VAR=val ...] [-- land flags] -- one land with the standard stub wiring
pb_land() {
  local name="$1"; shift
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  env GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$PB_WT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-$name" \
    GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$@" "$WRAP" land "$PB_WT" ${PB_FLAGS:-} 2>&1
}
pb_open() { # pb_open <number> <body> -- an open own PR titled like the branch's feature commit
  jq -cn --argjson n "$1" --arg b "$2" '[{number:$n,baseRefName:"main",author:{login:"me"},isDraft:false,
    isCrossRepository:false,title:"feat: the landed change",body:$b,url:("https://github.com/o/r/pull/"+($n|tostring))}]'
}

echo "--- PB1: a new PR with no --body-file takes its body from the proof file"
pb_build pb1
out="$(pb_land pb1)"; rc=$?
calls="$(cat "$GH_STUB_CALLS")"
chk "PB1: exits 0" "$rc"
chk_has "PB1: the body opens with the title as the summary" "$calls" "--body feat: the landed change"
chk_has "PB1: the body carries the proof section" "$calls" "## Proof of done"
chk_has "PB1: the body carries the captured output" "$calls" "t: all 3 passed"
chk_has "PB1: the land ends on the PROOF OF DONE block" "$(printf '%s\n' "$out" | tail -4)" "PROOF OF DONE"
chk_has "PB1: the block names the proof file" "$out" "  proof: docs/verification/land.md"
chk_has "PB1: the block names the PR" "$out" "  PR:    https://github.com/o/r/pull/42"
chk_has "PB1: the block shows the captured output" "$out" "    | t: all 3 passed"

echo "--- PB2: an adopted PR whose body is only its title takes the proof body"
pb_build pb2
out="$(pb_land pb2 GH_STUB_OPEN_HEAD_feat_land="$(pb_open 18 "feat: the landed change")")"; rc=$?
calls="$(cat "$GH_STUB_CALLS")"
chk "PB2: exits 0" "$rc"
chk_has "PB2: the body is set on the adopted PR" "$calls" "pr edit 18"
chk_has "PB2: the set body carries the proof section" "$calls" "## Proof of done"
chk_has "PB2: says the body was set" "$out" "PR #18 body set from the proof of done"
chk_has "PB2: the block names the adopted PR" "$out" "  PR:    https://github.com/o/r/pull/18"

echo "--- PB3: an adopted PR with a body of its own keeps it"
pb_build pb3
out="$(pb_land pb3 GH_STUB_OPEN_HEAD_feat_land="$(pb_open 19 "What changed and why, written by hand.")")"; rc=$?
calls="$(cat "$GH_STUB_CALLS")"
chk "PB3: exits 0" "$rc"
chk_no "PB3: the body is not replaced" "$calls" "## Proof of done"
chk_has "PB3: the block is still printed" "$out" "PROOF OF DONE"

echo "--- PB4: --body-file wins over the proof body; the block is still printed"
pb_build pb4
printf 'A hand-written body.\n' > "$TMPD/pb4-body.md"
out="$(PB_FLAGS="--body-file $TMPD/pb4-body.md" pb_land pb4)"; rc=$?
calls="$(cat "$GH_STUB_CALLS")"
chk "PB4: exits 0" "$rc"
chk_has "PB4: pr create carried the body file" "$calls" "--body-file $TMPD/pb4-body.md"
chk_no "PB4: the proof body is not sent" "$calls" "## Proof of done"
chk_has "PB4: the block is still printed" "$out" "PROOF OF DONE"

echo "--- PB5: a branch with no proof file lands as before: title as the body, no block"
build_land pb5
PB_WT="$(cd "$TMPD/ld-repo-pb5/wt" && pwd -P)"
out="$(pb_land pb5)"; rc=$?
chk "PB5: exits 0" "$rc"
chk "PB5: pr create used the title alone as the body" \
  "$(grep -qx -- '.*pr create .* --body feat: the landed change' "$GH_STUB_CALLS"; echo $?)"
chk_no "PB5: no block" "$out" "PROOF OF DONE"

echo "--- PB6: a local cache link becomes a named marker; a committed image still hotlinks"
# The body-builder runs with a github-shaped origin arg, so _land_web_url yields a web
# base and the rewrite loop actually runs (the fixture remotes are local paths).
pb_build pb6
PB6_WT="$TMPD/ld-repo-pb6/wt"
mkdir -p "$PB6_WT/.kit/proof-assets/ui"
printf '*\n' > "$PB6_WT/.kit/proof-assets/.gitignore"     # the put-written ignore: cache stays untracked
printf 'local-bytes' > "$PB6_WT/.kit/proof-assets/ui/shot-abc12345.webp"
printf 'PNG89a' > "$PB6_WT/docs/verification/after.png"
printf '![shot](.kit/proof-assets/ui/shot-abc12345.webp)\n\n![after](after.png)\n' \
  >> "$PB6_WT/docs/verification/land.md"
git -C "$PB6_WT" add -A; git -C "$PB6_WT" commit -qm "docs: images" >/dev/null 2>&1
PB6_BASE="$(git -C "$PB6_WT" rev-parse origin/main)"
PB6_SHA="$(git -C "$PB6_WT" rev-parse HEAD)"
PB6_BODY="$(PROOF_LEDGER_SH="$KIT_DIR/lib/gate/proof-ledger.sh" bash -c \
  'source "$1"; shift; _land_proof_body "$@"' _ \
  "$KIT_DIR/lib/wrap/wrap-land.sh" "$PB6_WT" "$PB6_BASE" "feat: the landed change" "$PB6_SHA" "git@github.com:o/r.git")"
chk_has "PB6: the local cache link is named, not hotlinked" \
  "$PB6_BODY" "_(local image, not uploaded: shot-abc12345.webp)_"
chk "PB6: no blob URL was minted for the cache file" \
  "$(printf '%s' "$PB6_BODY" | grep -c 'proof-assets.*raw=true')"
chk_has "PB6: the committed image still becomes a blob url" \
  "$PB6_BODY" "blob/${PB6_SHA}/docs/verification/after.png?raw=true"
} # end sec_proofbody

# ===========================================================================
sec_flush() {
echo "=== land: the visual-proof flush runs before the dirty check and the push ==="
# ===========================================================================
# The flush seam: land calls `bin/proof-asset flush` inside the landed worktree when the
# worktree's .kit.toml opts the project into visual proof. The stub logs each call and its
# cwd, prints a marker line the ordering checks can place, and exits FL_RC.
FL_BIN="$TMPD/proof-asset-stub"
cat > "$FL_BIN" <<'STUB'
#!/usr/bin/env bash
{ printf '%s\n' "$*"; pwd; } >> "${FL_CALLS:-/dev/null}"
printf 'flush says: %s\n' "${FL_SAYS:-ok}"
exit "${FL_RC:-0}"
STUB
chmod +x "$FL_BIN"
FL_CALLS="$TMPD/fl-calls.log"; export FL_CALLS
# The kit-root layer is pinned at an empty dir, so the real installed kit.toml can never
# flip the flag mid-suite either way.
FL_CFG="$TMPD/no-kit-root"; mkdir -p "$FL_CFG"

# fl_build <name> -- build_land plus a committed .kit.toml opting the branch's worktree
# into visual proof.
fl_build() {
  build_land "$1"
  printf '[proof]\nvisual = true\n' > "$TMPD/ld-repo-$1/wt/.kit.toml"
  git -C "$TMPD/ld-repo-$1/wt" add -A
  git -C "$TMPD/ld-repo-$1/wt" commit -qm "chore: opt into visual proof" >/dev/null 2>&1
}
# fl_land <name> <wt> [VAR=val ...] -- one land with the standard stub wiring
fl_land() {
  local name="$1" wt="$2"; shift 2
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  : > "$FL_CALLS"
  env GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$wt" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-$name" \
    GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main KIT_CONFIG_ROOT="$FL_CFG" \
    PROOF_ASSET_BIN="$FL_BIN" "$@" "$WRAP" land "$wt" 2>&1
}

echo "--- flush: opted in, the flush runs before the dirty check"
fl_build fok
FL_WT_FOK="$(cd "$TMPD/ld-repo-fok/wt" && pwd -P)"
echo dirt > "$TMPD/ld-repo-fok/wt/dirt.txt"
out="$(fl_land fok "$FL_WT_FOK")"; rc=$?
chk "flush: a dirty worktree still refuses with 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "flush: the dirty refusal still names the cause" "$out" "is dirty"
chk "flush: the flush ran even though the tree is dirty" \
  "$(grep -qx 'flush' "$FL_CALLS"; echo $?)"
chk_has "flush: its output landed ahead of the dirty refusal" \
  "$(printf '%s\n' "$out" | sed '/is dirty/q')" "flush says: ok"
chk "flush: it ran inside the landed worktree" \
  "$(sed -n 2p "$FL_CALLS" | grep -qxF "$FL_WT_FOK"; echo $?)"

echo "--- flush: opted in, a clean land flushes before the push"
rm -f "$TMPD/ld-repo-fok/wt/dirt.txt"
out="$(fl_land fok "$FL_WT_FOK")"; rc=$?
chk "flush: the opted-in land still exits 0" "$rc"
chk "flush: the flush was called once, with the flush verb" \
  "$([ "$(grep -cx 'flush' "$FL_CALLS")" -eq 1 ]; echo $?)"
chk_has "flush: its output precedes the push report" \
  "$(printf '%s\n' "$out" | sed '/pushed feat\/land/q')" "flush says: ok"
chk_has "flush: the land still pushed" "$out" "pushed feat/land"
chk_has "flush: the land still merged" "$out" "merged #42 ("

echo "--- flush: opted in, a failing flush stops the land before the push"
fl_build fbad
FL_WT_FBAD="$(cd "$TMPD/ld-repo-fbad/wt" && pwd -P)"
out="$(fl_land fbad "$FL_WT_FBAD" FL_RC=1 FL_SAYS="still pending: 1 asset")"; rc=$?
chk "flush: a failed flush exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "flush: the flush's own message surfaces" "$out" "still pending: 1 asset"
chk_has "flush: the refusal names the flush" "$out" "LAND REFUSED: proof-asset flush exited 1"
chk "flush: nothing was pushed" \
  "$(git -C "$TMPD/ld-bare-fbad" rev-parse --verify -q feat/land >/dev/null && echo 1 || echo 0)"
chk_no "flush: no PR was opened" "$(cat "$GH_STUB_CALLS")" "pr create"
chk "flush: the worktree stays" "$([ -d "$FL_WT_FBAD" ]; echo $?)"

echo "--- flush: opted out, land never calls the seam"
build_land foff
FL_WT_FOFF="$(cd "$TMPD/ld-repo-foff/wt" && pwd -P)"
out="$(fl_land foff "$FL_WT_FOFF" FL_RC=1 FL_SAYS="must not run")"; rc=$?
chk "flush: an opted-out land still exits 0" "$rc"
chk "flush: the seam was never called" "$([ ! -s "$FL_CALLS" ]; echo $?)"
chk_has "flush: the land still pushed" "$out" "pushed feat/land"

echo "--- flush: a real offline put drains through the real flush inside land"
# No PROOF_ASSET_BIN here: the land runs the shipped bin/proof-asset. The origin is a
# symlinked copy of the fixture's bare remote under <tmp>/acme/widgets.git, so
# owner/repo derive as acme/widgets (the real remote's tmp-dir name holds dots, which
# the dotted-key config split cannot read back) while fetch/push stay hermetic.
fl_build frt
RT_WT="$TMPD/ld-repo-frt/wt"; RT_WT_P="$(cd "$RT_WT" && pwd -P)"
mkdir -p "$TMPD/acme"
ln -sfn "$TMPD/ld-bare-frt" "$TMPD/acme/widgets.git"
git -C "$RT_WT" remote set-url origin "$TMPD/acme/widgets.git"
FL_OP="$TMPD/op-proof"; mkdir -p "$FL_OP"
cat > "$FL_OP/kit.toml" <<EOF
[proof]
account_acme = "acct-test-123"
base_url_acme = "https://proof.test"
EOF
RT_UP="$TMPD/rt-uploader"; RT_CONV="$TMPD/rt-conv"; RT_FAIL="$TMPD/rt-up.fail"
cat > "$RT_UP" <<'STUB'
#!/usr/bin/env bash
[ -f "$RT_FAIL" ] && exit 1
exit 0
STUB
cat > "$RT_CONV" <<'STUB'
#!/usr/bin/env bash
{ printf 'RIFF\x00\x00\x00\x00WEBPVP8L'; head -c 256 /dev/zero; } > "$2"
STUB
chmod +x "$RT_UP" "$RT_CONV"
{ printf '\x89PNG\r\n\x1a\n'; head -c 2000 /dev/zero; } > "$TMPD/rt-shot.png"
: > "$RT_FAIL"
out="$(cd "$RT_WT" && KIT_CONFIG_OPERATOR="$FL_OP" KIT_CONFIG_ROOT="$FL_CFG" \
  RT_FAIL="$RT_FAIL" PROOF_ASSET_UPLOADER="$RT_UP" PROOF_ASSET_CONVERT="$RT_CONV" \
  bash "$KIT_DIR/bin/proof-asset" put land "$TMPD/rt-shot.png" --name shot 2>&1)"; rc=$?
chk "round-trip: the offline put still exits 0" "$rc"
chk_has "round-trip: its stderr reports the queue" "$out" "queued:"
chk "round-trip: the queue file holds the pending file" \
  "$(test -s "$RT_WT/.kit/proof-assets/land/.pending"; echo $?)"
git -C "$RT_WT" add -A; git -C "$RT_WT" commit -qm "docs: proof" >/dev/null 2>&1
chk "round-trip: the committed tree is clean (the cache ignores itself)" \
  "$(test -z "$(git -C "$RT_WT" status --porcelain)"; echo $?)"
chk "round-trip: land's dirty check would pass already" \
  "$(test -z "$(git -C "$RT_WT" status --porcelain --ignored=matching | grep -v '^!! ')"; echo $?)"
rm -f "$RT_FAIL"
: > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
out="$(env GH_STUB_OPEN_PRS='[]' GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$RT_WT_P" \
  GH_STUB_LAND_REMOTE="$TMPD/ld-bare-frt" GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main \
  KIT_CONFIG_ROOT="$FL_CFG" KIT_CONFIG_OPERATOR="$FL_OP" \
  RT_FAIL="$RT_FAIL" PROOF_ASSET_UPLOADER="$RT_UP" "$WRAP" land "$RT_WT_P" 2>&1)"; rc=$?
chk "round-trip: the real land exits 0" "$rc"
chk_has "round-trip: the real flush printed the paste line" "$out" "![shot](https://proof.test/"
chk_has "round-trip: the land still pushed" "$out" "pushed feat/land"
chk_has "round-trip: the land still merged" "$out" "merged #42 ("
} # end sec_flush

# One section, in this process. The driver sets LAND_SECTION per child; the last line is the
# child's result for the driver to sum (it is not the suite's final line).
[ "$(type -t "$LAND_SECTION")" = function ] || { echo "test-wrap-land: no such section: $LAND_SECTION" >&2; exit 64; }
"$LAND_SECTION"
echo "land-section-result: $PASS $FAIL $TOTAL"
[ "$FAIL" -eq 0 ]
