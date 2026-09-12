#!/usr/bin/env bash
# test-wrap.sh -- SPEC-246 TASK-001: the whole acceptance matrix for `bin/wrap` and
# `lib/wrap/wrap.sh`.
#
# Fixture: three bare remotes whose default branches are `main`, `master` and `develop`,
# each with the branch set the gates discriminate on (merged-ancestor, unmerged, squash-ok,
# squash-stale, stacked-child, wt-clean, wt-dirty), clones with three secondary worktrees
# (clean, dirty, detached), a clone whose origin/HEAD dangles, and a repo with no remote.
# `gh` is a stub on PATH driven by env vars; it records every call so the merge case can
# assert the exact flags.
#
# Run: bash tests/test-wrap.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAP="$KIT_DIR/bin/wrap"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
chk_has() { chk "$1" "$({ trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$3"; echo $?)"; }
chk_no()  { chk "$1" "$({ trap '' PIPE; printf '%s' "$2" 2>/dev/null || :; } | grep -qF -- "$3" && echo 1 || echo 0)"; }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-wrap-test.XXXXXX")"
TMPD="$(cd "$TMPD" && pwd)"
trap 'chmod -R u+w "$TMPD" 2>/dev/null; rm -rf "$TMPD"' EXIT

# Pin the operator config overlay at a path that does not exist, so the operator's REAL
# ~/.config/dwarves-kit/kit.toml can never reach a case that does not set it deliberately.
KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"; export KIT_CONFIG_OPERATOR

# --------------------------------------------------------------------------- gh stub
mkdir -p "$TMPD/stub"
cat > "$TMPD/stub/gh" <<'STUB'
#!/usr/bin/env bash
# gh stub: answers exactly what wrap.sh asks and records every call.
printf '%s\n' "$*" >> "${GH_STUB_CALLS:-/dev/null}"
sub="${1:-}"; [ $# -gt 0 ] && shift
case "$sub" in
  auth)
    [ "${GH_STUB_UNAUTH:-0}" = "1" ] && exit 1
    exit 0 ;;
  pr)
    verb="${1:-}"; [ $# -gt 0 ] && shift
    case "$verb" in
      list)
        head=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --head) head="${2:-}"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [ -n "$head" ]; then
          key="GH_STUB_MERGED_$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')"
          eval "val=\"\${$key:-}\""
          [ -n "$val" ] || val="[]"
          printf '%s\n' "$val"
        else
          printf '%s\n' "${GH_STUB_OPEN_PRS:-[]}"
        fi
        exit 0 ;;
      view)
        n="${1:-}"; [ $# -gt 0 ] && shift
        fields=""
        while [ $# -gt 0 ]; do
          case "$1" in --json) fields="${2:-}"; shift 2 ;; *) shift ;; esac
        done
        case "$fields" in
          state,mergeCommit)
            default_state='{"state":"MERGED","mergeCommit":{"oid":"1a2b3c4d5e6f"}}'
            printf '%s\n' "${GH_STUB_VIEW_STATE:-$default_state}" ;;
          *)
            key="GH_STUB_PR_$n"; eval "val=\"\${$key:-}\""
            [ -n "$val" ] || val="{}"
            printf '%s\n' "$val" ;;
        esac
        exit 0 ;;
      merge) exit "${GH_STUB_MERGE_RC:-0}" ;;
    esac
    exit 1 ;;
esac
exit 1
STUB
chmod +x "$TMPD/stub/gh"
PATH="$TMPD/stub:$PATH"; export PATH
GH_STUB_CALLS="$TMPD/gh-calls.log"; export GH_STUB_CALLS; : > "$GH_STUB_CALLS"

# --------------------------------------------------------------------------- fixture
gitc() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }

build_remote() { # build_remote <name> <default branch>
  local name="$1" def="$2" work="$TMPD/work-$1" b
  mkdir -p "$work"
  git -C "$work" init -q
  gitc "$work"
  git -C "$work" symbolic-ref HEAD "refs/heads/$def"
  echo base > "$work/a.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" branch merged-ancestor
  echo second >> "$work/a.txt"; git -C "$work" commit -qam second
  for b in unmerged squash-ok squash-stale stacked-child wt-clean wt-dirty; do
    git -C "$work" branch "$b"
    git -C "$work" checkout -q "$b"
    echo "$b" > "$work/$b.txt"; git -C "$work" add -A; git -C "$work" commit -qm "$b"
  done
  git -C "$work" checkout -q "$def"
  git clone -q --bare "$work" "$TMPD/bare-$name"
}

make_clone() { # make_clone <name> <remote name> <default branch> <checkout branch>
  local name="$1" rname="$2" def="$3" co="$4" clone="$TMPD/clone-$1" b
  git clone -q "$TMPD/bare-$rname" "$clone"
  gitc "$clone"
  git -C "$clone" remote set-head origin "$def" >/dev/null 2>&1
  for b in merged-ancestor unmerged squash-ok squash-stale stacked-child wt-clean wt-dirty; do
    git -C "$clone" branch "$b" "origin/$b" >/dev/null 2>&1
  done
  git -C "$clone" worktree add "$TMPD/wt-$name-clean" wt-clean >/dev/null 2>&1
  # Locked, because the Agent tool locks every worktree it creates. A single `--force` declines
  # to remove a locked worktree, so the clean case only tests the tidy once it survives a lock.
  git -C "$clone" worktree lock "$TMPD/wt-$name-clean" >/dev/null 2>&1
  git -C "$clone" worktree add "$TMPD/wt-$name-dirty" wt-dirty >/dev/null 2>&1
  echo dirt > "$TMPD/wt-$name-dirty/dirt.txt"
  git -C "$clone" worktree add --detach "$TMPD/wt-$name-det" HEAD >/dev/null 2>&1
  git -C "$clone" checkout -q "$co"
}

set_stub() { # set_stub <remote name> <default branch>
  local bare="$TMPD/bare-$1" def="$2"
  export GH_STUB_MERGED_squash_ok="[{\"headRefOid\":\"$(git -C "$bare" rev-parse squash-ok)\",\"baseRefName\":\"$def\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]"
  export GH_STUB_MERGED_squash_stale="[{\"headRefOid\":\"1111111111111111111111111111111111111111\",\"baseRefName\":\"$def\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]"
  export GH_STUB_MERGED_stacked_child="[{\"headRefOid\":\"$(git -C "$bare" rev-parse stacked-child)\",\"baseRefName\":\"feat/parent\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]"
}

build_remote rmain main
build_remote rmaster master
build_remote rdev develop

export GH_STUB_OPEN_PRS='[{"number":7,"title":"wrap the session","headRefName":"feat/wrap"}]'
PR7_OID=deadbeefcafe1234567890abcdef1234567890ab
export GH_STUB_PR_7="{\"number\":7,\"title\":\"wrap the session\",\"headRefName\":\"feat/wrap\",\"headRefOid\":\"$PR7_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"},{\"conclusion\":\"SKIPPED\"}]}"

# ===========================================================================
echo "=== scan: every verdict, for main, master and develop defaults ==="
# ===========================================================================
for pair in "rmain main" "rmaster master" "rdev develop"; do
  set -- $pair
  rname="$1"; def="$2"
  make_clone "scan-$def" "$rname" "$def" unmerged
  set_stub "$rname" "$def"
  out="$("$WRAP" scan "$TMPD/clone-scan-$def" 2>&1)"
  chk_has "scan/$def: ahead-behind line names origin/$def" "$out" "-- vs origin/$def: ahead="
  chk_has "scan/$def: merged-ancestor is SAFE-d" "$out" "merged-ancestor  [SAFE-d: ancestor of origin/$def]"
  chk_has "scan/$def: squash-ok is squash-merged" "$out" "squash-ok  [SQUASH-MERGED per gh: safe to -D]"
  chk_has "scan/$def: squash-stale is LEAVE" "$out" "squash-stale  [NOT merged / unknown: LEAVE]"
  chk_has "scan/$def: unmerged is LEAVE" "$out" "unmerged  [NOT merged / unknown: LEAVE]"
  chk_has "scan/$def: the open PR is listed" "$out" "#7 wrap the session [feat/wrap]"
  chk_has "scan/$def: checkout line" "$out" "-- checkout on: unmerged"
done

echo "=== scan: the gh calls carry the origin URL the repo actually has ==="
set_stub rmain main
SCAN_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"
: > "$GH_STUB_CALLS"
"$WRAP" scan "$TMPD/clone-scan-main" >/dev/null 2>&1
SCAN_CALLS="$(cat "$GH_STUB_CALLS")"
chk_has "scan: pr list names --repo and --head" "$SCAN_CALLS" \
  "pr list --repo ${SCAN_URL} --head squash-ok"
chk_has "scan: the open-PR query names --repo" "$SCAN_CALLS" "pr list --repo ${SCAN_URL} --author"

echo "=== scan: a non-repo argument is skipped, the repo after it still reports ==="
out="$("$WRAP" scan "$TMPD/not-a-repo" "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan: non-repo prints the skip line" "$out" "not a git repo, skipped"
chk_has "scan: the following repo still reports" "$out" "-- vs origin/main: ahead="

# ===========================================================================
echo "=== apply dry-run: every SKIP reason, and no write ==="
# ===========================================================================
set_stub rmain main
DRY="$TMPD/clone-scan-main"
before_b="$(git -C "$DRY" branch --list)"
before_w="$(git -C "$DRY" worktree list)"
out="$("$WRAP" apply "$DRY" 2>&1)"; rc=$?
chk "apply dry-run exits 0" "$rc"
chk_has "apply dry-run: wt-clean skipped without --worktrees" "$out" "--worktrees not given"
chk_has "apply dry-run: the checked-out branch is skipped" "$out" "SKIP unmerged: currently checked out"
chk_has "apply dry-run: squash-stale names both short SHAs" "$out" "SKIP squash-stale: tip $(git -C "$DRY" rev-parse squash-stale | cut -c1-7) != merged PR head 1111111"
chk_has "apply dry-run: stacked-child names the other base" "$out" "SKIP stacked-child: merged into feat/parent, not the default branch"
chk_has "apply dry-run: pull skipped off the default branch" "$out" "SKIP pull: checkout on 'unmerged', not the default branch main"
chk_has "apply dry-run: the deletes are announced, not run" "$out" "[DRY-RUN] delete merged-ancestor"

out="$("$WRAP" apply --worktrees "$DRY" 2>&1)"; rc=$?
chk "apply dry-run --worktrees exits 0" "$rc"
chk_has "apply dry-run: the dirty worktree is skipped" "$out" "dirty (another session's work stays)"
chk_has "apply dry-run: the detached worktree is skipped" "$out" "detached HEAD (removal could orphan the commit)"
after_b="$(git -C "$DRY" branch --list)"
after_w="$(git -C "$DRY" worktree list)"
chk "apply without --apply changes no branch (byte-equal)" "$([ "$before_b" = "$after_b" ]; echo $?)"
chk "apply without --apply changes no worktree (byte-equal)" "$([ "$before_w" = "$after_w" ]; echo $?)"

# ===========================================================================
echo "=== apply --apply --worktrees: only the proven deletes, and a ff pull ==="
# ===========================================================================
make_clone apply-main rmain main main
# Advance the remote default branch so the pull has something to fast-forward to.
git clone -q "$TMPD/bare-rmain" "$TMPD/pusher"
gitc "$TMPD/pusher"
echo advance >> "$TMPD/pusher/a.txt"
git -C "$TMPD/pusher" commit -qam advance
git -C "$TMPD/pusher" push -q origin main
NEW_TIP="$(git -C "$TMPD/bare-rmain" rev-parse main)"

set_stub rmain main
APPLYREPO="$TMPD/clone-apply-main"
out="$("$WRAP" apply --apply --worktrees "$APPLYREPO" 2>&1)"; rc=$?
chk "apply --apply exits 0 on a healthy repo" "$rc"
branches="$(git -C "$APPLYREPO" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
chk "apply --apply deleted merged-ancestor and squash-ok only" \
  "$([ "$branches" = "main squash-stale stacked-child unmerged wt-clean wt-dirty " ]; echo $?)"
chk_no "apply --apply never touched the default branch" "$out" "delete main"
chk "apply --apply removed the clean worktree only" \
  "$([ ! -d "$TMPD/wt-apply-main-clean" ] && [ -d "$TMPD/wt-apply-main-dirty" ] && [ -d "$TMPD/wt-apply-main-det" ]; echo $?)"
chk "apply --apply fast-forwarded the default branch" \
  "$([ "$(git -C "$APPLYREPO" rev-parse HEAD)" = "$NEW_TIP" ]; echo $?)"

# ===========================================================================
echo "=== apply --apply: a non-ff default branch is FAILED, exit 2, never forced ==="
# ===========================================================================
make_clone apply-nonff rmaster master master
OLD_MASTER="$(git -C "$TMPD/clone-apply-nonff" rev-parse master)"
git clone -q "$TMPD/bare-rmaster" "$TMPD/rewriter"
gitc "$TMPD/rewriter"
git -C "$TMPD/rewriter" reset -q --hard HEAD~1
echo divergent > "$TMPD/rewriter/divergent.txt"
git -C "$TMPD/rewriter" add -A; git -C "$TMPD/rewriter" commit -qm divergent
git -C "$TMPD/rewriter" push -q --force origin HEAD:refs/heads/master
set_stub rmaster master
out="$("$WRAP" apply --apply "$TMPD/clone-apply-nonff" 2>&1)"; rc=$?
chk "apply --apply exits 2 when a write fails" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "apply --apply reports the failed pull" "$out" "FAILED pull --ff-only"
chk "apply --apply never reset the local default branch" \
  "$([ "$(git -C "$TMPD/clone-apply-nonff" rev-parse master)" = "$OLD_MASTER" ]; echo $?)"

# ===========================================================================
echo "=== apply: a tip that moved during the run is skipped, not deleted ==="
# ===========================================================================
make_clone tips rmain main unmerged
set_stub rmain main
TIPSREPO="$TMPD/clone-tips"
STALE_TIPS="$TMPD/stale-tips.txt"
git -C "$TIPSREPO" for-each-ref --format='%(refname:short) %(objectname)' refs/heads/ > "$STALE_TIPS"
# Rewrite merged-ancestor's recorded tip so the pre-delete re-check sees a moved branch.
sed 's/^merged-ancestor .*/merged-ancestor 2222222222222222222222222222222222222222/' \
  "$STALE_TIPS" > "$STALE_TIPS.new" && mv -f "$STALE_TIPS.new" "$STALE_TIPS"
out="$("$WRAP" apply --apply --tips-file "$STALE_TIPS" "$TIPSREPO" 2>&1)"
chk_has "apply: a moved tip is skipped" "$out" "SKIP merged-ancestor: tip moved during this run"
chk "apply: the moved-tip branch survives" \
  "$(git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/merged-ancestor; echo $?)"
chk "apply: the unmoved squash-ok branch still went" \
  "$(git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/squash-ok && echo 1 || echo 0)"

# ===========================================================================
echo "=== apply: index.lock age decides, and a non-repo never reaches a write ==="
# ===========================================================================
make_clone lock rmain main unmerged
set_stub rmain main
LOCKREPO="$TMPD/clone-lock"
touch -t 202601010000 "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
chk_has "apply: a stale index.lock refuses every write" "$out" "index.lock held by another writer"
LOCK_BRANCHES="$(git -C "$LOCKREPO" for-each-ref --format='%(refname:short)' refs/heads/ | sort | tr '\n' ' ')"
chk "apply: a stale index.lock deleted nothing" \
  "$([ "$LOCK_BRANCHES" = "main merged-ancestor squash-ok squash-stale stacked-child unmerged wt-clean wt-dirty " ]; echo $?)"

# A young lock that clears within the window is ordinary traffic: release it after 2 s from
# the background and the write proceeds. A young lock that persists is a writer (next case).
rm -f "$LOCKREPO/.git/index.lock"; touch "$LOCKREPO/.git/index.lock"
( sleep 2; rm -f "$LOCKREPO/.git/index.lock" ) &
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
wait
chk_no "apply: a fresh index.lock that clears does not refuse the write" "$out" "index.lock held by another writer"
chk "apply: a fresh index.lock that clears still deleted the proven branches" \
  "$(git -C "$LOCKREPO" show-ref --verify --quiet refs/heads/merged-ancestor && echo 1 || echo 0)"
touch "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply "$LOCKREPO" 2>&1)"
chk_has "apply: a fresh index.lock that persists past the window refuses the write" "$out" "index.lock held by another writer"
rm -f "$LOCKREPO/.git/index.lock"

out="$("$WRAP" apply --apply "$TMPD/not-a-repo" "$LOCKREPO" 2>&1)"
chk_has "apply: a non-repo argument is skipped before any write" "$out" "not a git repo, skipped"
chk_has "apply: the repo after the non-repo still runs" "$out" "-- branches:"

# ===========================================================================
echo "=== apply: a broken origin URL fails the fetch and deletes nothing ==="
# ===========================================================================
make_clone brokenremote rmain main unmerged
set_stub rmain main
BROKEN="$TMPD/clone-brokenremote"
BROKEN_BEFORE="$(git -C "$BROKEN" for-each-ref --format='%(refname:short)' refs/heads/ | sort)"
git -C "$BROKEN" remote set-url origin /nonexistent
out="$("$WRAP" apply --apply "$BROKEN" 2>&1)"
chk_has "apply: the failed fetch is reported" "$out" "(fetch failed; every delete is skipped)"
chk_has "apply: the ancestor branch names the stale-data reason" "$out" \
  "SKIP merged-ancestor: fetch failed, stale ancestor data"
chk "apply: the broken-remote repo lost no branch" \
  "$([ "$BROKEN_BEFORE" = "$(git -C "$BROKEN" for-each-ref --format='%(refname:short)' refs/heads/ | sort)" ]; echo $?)"

# ===========================================================================
echo "=== apply: a union-marked log is carried across the pull, nothing else is ==="
# ===========================================================================
# Real repos on disk, not a stubbed `git`: the whole point is what git itself does to a dirty
# checkout during a pull, which a command-text stub would never exercise.
LAB_BASE=$'# Lab log\n\n---\n\n2026-09-01 · base: the first line\n'
LAB_REMOTE=$'# Lab log\n\n---\n\n2026-09-02 · remote: the incoming line\n2026-09-01 · base: the first line\n'
LAB_LOCAL=$'# Lab log\n\n---\n\n2026-09-03 · local: the other session line\n2026-09-01 · base: the first line\n'

build_union_repo() { # build_union_repo <name> -- bare origin plus a clone on main
  local name="$1" work clone
  work="$TMPD/uwork-$name"; clone="$TMPD/uclone-$name"
  mkdir -p "$work/_meta"
  git -C "$work" init -q
  gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
  printf '%s' "$LAB_BASE" > "$work/_meta/LAB_LOG.md"
  printf 'readme base\n' > "$work/README.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/ubare-$name"
  git clone -q "$TMPD/ubare-$name" "$clone"
  gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
}

advance_union_repo() { # advance_union_repo <name> -- one incoming commit touching both files
  local name="$1" push
  push="$TMPD/upush-$name"
  git clone -q "$TMPD/ubare-$name" "$push"
  gitc "$push"
  printf '%s' "$LAB_REMOTE" > "$push/_meta/LAB_LOG.md"
  printf 'readme remote\n' > "$push/README.md"
  git -C "$push" commit -qam advance
  git -C "$push" push -q origin main
}

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
chk_no "mixed: no carry-back happened" "$out" "carried"
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
echo "=== gh absent: every non-ancestor is LEAVE, merge refuses ==="
# ===========================================================================
mkdir -p "$TMPD/nogh"
for t in bash env git jq sed awk grep date stat mktemp readlink mv rm cat tr sort head cut basename dirname chmod; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$TMPD/nogh/$t"
done
chk "the gh-free PATH really has no gh" "$(PATH="$TMPD/nogh" command -v gh >/dev/null 2>&1 && echo 1 || echo 0)"
out="$(PATH="$TMPD/nogh" "$WRAP" scan "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan without gh: squash-ok falls back to LEAVE" "$out" "squash-ok  [NOT merged / unknown: LEAVE]"
chk_has "scan without gh: the PR line says so" "$out" "(gh unavailable)"
out="$(PATH="$TMPD/nogh" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge without gh exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge without gh names the reason" "$out" "(gh unavailable)"

echo "=== gh unauthenticated: the same verdicts, merge still refuses ==="
out="$(GH_STUB_UNAUTH=1 "$WRAP" scan "$TMPD/clone-scan-main" 2>&1)"
chk_has "scan unauthenticated: squash-ok falls back to LEAVE" "$out" "squash-ok  [NOT merged / unknown: LEAVE]"
chk_has "scan unauthenticated: the PR line says so" "$out" "(gh unauthenticated)"
out="$(GH_STUB_UNAUTH=1 "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge unauthenticated exits 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "merge unauthenticated names the reason" "$out" "(gh unauthenticated)"

# ===========================================================================
echo "=== merge: dry-run lists the eligible PR, --apply merges exactly one ==="
# ===========================================================================
: > "$GH_STUB_CALLS"
out="$("$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge dry-run exits 0" "$rc"
chk_has "merge dry-run lists the PR as eligible" "$out" "eligible #7 wrap the session [feat/wrap]"
chk "merge dry-run calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

: > "$GH_STUB_CALLS"
out="$("$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --apply exits 0" "$rc"
chk_has "merge --apply reports the merge SHA" "$out" "merged #7 1a2b3c4d5e6f"
chk "merge --apply called pr merge exactly once" "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "merge --apply passed --squash" "$(grep -q '^pr merge 7 .*--squash' "$GH_STUB_CALLS"; echo $?)"
chk "merge --apply passed no --delete-branch" "$(grep -q -- '--delete-branch' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --apply passed no --auto" "$(grep -q -- '--auto' "$GH_STUB_CALLS" && echo 1 || echo 0)"
chk "merge --apply verified through pr view" "$(grep -q '^pr view 7 .*state,mergeCommit' "$GH_STUB_CALLS"; echo $?)"
MERGE_URL="$(git -C "$TMPD/clone-scan-main" remote get-url origin)"
MERGE_CALLS="$(cat "$GH_STUB_CALLS")"
chk_has "merge --apply pinned the head it gated on" "$MERGE_CALLS" \
  "pr merge 7 --repo ${MERGE_URL} --squash --match-head-commit ${PR7_OID}"
chk_has "merge: the detail read names --repo" "$MERGE_CALLS" "pr view 7 --repo ${MERGE_URL}"
chk "merge reads each PR detail exactly once" \
  "$([ "$(grep -c "^pr view 7 --repo ${MERGE_URL} --json number,title" "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"

echo "=== merge: the checks gate refuses pending, failing, empty-and-unstable, and changes requested ==="
gate_verdict() { # gate_verdict <pr json>
  GH_STUB_OPEN_PRS='[{"number":9,"title":"gate case","headRefName":"feat/gate"}]' \
  GH_STUB_PR_9="$1" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1
}
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"},{"status":"PENDING"}]}')"
chk_has "merge: a pending check skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"FAILURE"}]}')"
chk_has "merge: a failing check skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"UNSTABLE","reviewDecision":"APPROVED","statusCheckRollup":[]}')"
chk_has "merge: an empty rollup on a non-CLEAN state skips" "$out" "SKIP #9 gate case: checks are pending or failing"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":null}')"
chk_has "merge: a null rollup on a CLEAN state stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}')"
chk_has "merge: an empty rollup on a CLEAN state stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}')"
chk_has "merge: changes requested skips" "$out" "SKIP #9 gate case: changes requested"

echo "=== merge: unparseable PR JSON skips instead of passing the gate ==="
out="$(gate_verdict 'not json at all')"
chk_has "merge: unreadable JSON skips" "$out" "SKIP #9: unreadable PR JSON"

echo "=== merge: a stacked parent with an open dependent skips, naming the retarget rule ==="
STACK_OPEN='[{"number":7,"title":"parent","headRefName":"feat/wrap"},{"number":8,"title":"child","headRefName":"feat/child"}]'
STACK_8='{"number":8,"title":"child","headRefName":"feat/child","baseRefName":"feat/wrap","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
STACK_7='{"number":7,"title":"parent","headRefName":"feat/wrap","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
out="$(GH_STUB_OPEN_PRS="$STACK_OPEN" GH_STUB_PR_7="$STACK_7" GH_STUB_PR_8="$STACK_8" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge skips the stacked parent" "$out" "SKIP #7 parent: dependents open, retarget them first (SPEC-065)"
chk_has "merge skips the child whose base is not the default branch" "$out" "SKIP #8 child: base is feat/wrap, not the default branch main"

echo "=== merge: the post-merge state check fails closed ==="
: > "$GH_STUB_CALLS"
out="$(GH_STUB_VIEW_STATE='{"state":"OPEN","mergeCommit":null}' "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --apply exits 2 when the PR is not MERGED after the call" "$([ "$rc" -eq 2 ]; echo $?)"

# ===========================================================================
echo "=== default-branch: detection, fall-through, and the no-remote refusal ==="
# ===========================================================================
chk "default-branch prints main" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-main")" = "main" ]; echo $?)"
chk "default-branch prints master" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-master")" = "master" ]; echo $?)"
chk "default-branch prints develop" "$([ "$("$WRAP" default-branch "$TMPD/clone-scan-develop")" = "develop" ]; echo $?)"

git clone -q "$TMPD/bare-rmain" "$TMPD/clone-dangling"
gitc "$TMPD/clone-dangling"
git -C "$TMPD/clone-dangling" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/renamed-away
chk "default-branch falls through to main when origin/HEAD dangles" \
  "$([ "$("$WRAP" default-branch "$TMPD/clone-dangling")" = "main" ]; echo $?)"

mkdir -p "$TMPD/remoteless"
git -C "$TMPD/remoteless" init -q; gitc "$TMPD/remoteless"
echo x > "$TMPD/remoteless/x.txt"; git -C "$TMPD/remoteless" add -A; git -C "$TMPD/remoteless" commit -qm x
out="$("$WRAP" default-branch "$TMPD/remoteless" 2>&1)"; rc=$?
chk "default-branch exits 1 on a repo with no remote" "$([ "$rc" -eq 1 ]; echo $?)"

# ===========================================================================
echo "=== log: the activity line, its path rules and its text rules ==="
# ===========================================================================
LOGHOME="$TMPD/home"; mkdir -p "$LOGHOME"
mkdir -p "$TMPD/outside"
KITROOT="$TMPD/kitroot"; mkdir -p "$KITROOT"
LOGFILE="$LOGHOME/ACTIVITY.md"
printf 'first old line\n' > "$LOGFILE"
printf 'old\n' > "$TMPD/outside/ACTIVITY.md"

set_log_key() { printf '[wrap]\nactivity_log = "%s"\n' "$1" > "$KITROOT/kit.toml"; }
wrap_log() { HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "$@"; }

set_log_key "$LOGFILE"
out="$(wrap_log "wrap: landed the session" 2>&1)"; rc=$?
chk "log exits 0 with the key set" "$rc"
chk "log prepends the dated line as line 1" \
  "$([ "$(head -1 "$LOGFILE")" = "$(date +%F) · wrap: landed the session" ]; echo $?)"
chk "log keeps the old first line" "$(grep -qx 'first old line' "$LOGFILE"; echo $?)"

wrap_log --date 2026-01-02 "wrap: backdated" >/dev/null 2>&1
chk "log --date overrides the prefix" \
  "$([ "$(head -1 "$LOGFILE")" = "2026-01-02 · wrap: backdated" ]; echo $?)"

DATE_BEFORE="$(cat "$LOGFILE")"
out="$(wrap_log --date "$(printf '2026-01-01\nFORGED')" "wrap: forged date" 2>&1)"; rc=$?
chk "log refuses a multi-line --date (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log names the --date format" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'wrap log: --date must be YYYY-MM-DD'; echo $?)"
chk "log wrote nothing on the forged date" "$([ "$DATE_BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"
out="$(wrap_log --date 2026-13-45 "wrap: impossible date" 2>&1)"; rc=$?
chk "log refuses an out-of-range --date (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the out-of-range date" "$([ "$DATE_BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

BEFORE="$(cat "$LOGFILE")"
# The dash is assembled from its bytes: a literal one in this file would violate the
# repo-wide formatting rule the verb under test enforces.
EM="$(printf '\xe2\x80\x94')"
out="$(wrap_log "wrap: an em dash ${EM} here" 2>&1)"; rc=$?
chk "log refuses an em dash (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the em dash" "$([ "$BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

out="$(wrap_log "$(printf 'wrap: two\nlines')" 2>&1)"; rc=$?
chk "log refuses a newline (exit 1)" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log wrote nothing on the newline" "$([ "$BEFORE" = "$(cat "$LOGFILE")" ]; echo $?)"

LONG="wrap: $(head -c 320 < /dev/zero | tr '\0' 'x')"
out="$(wrap_log "$LONG" 2>&1)"; rc=$?
chk "log writes a 320-char text" "$rc"
chk "log warns over the 300-char budget" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'over the 300-char routine budget'; echo $?)"

set_log_key "$LOGHOME/no-such-file.md"
out="$(wrap_log "wrap: missing target" 2>&1)"; rc=$?
chk "log exits 1 on a missing file" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log names the resolved path" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'no-such-file.md'; echo $?)"

set_log_key "$TMPD/outside/ACTIVITY.md"
out="$(wrap_log "wrap: outside home" 2>&1)"; rc=$?
chk "log exits 1 on an absolute path outside HOME" "$([ "$rc" -eq 1 ]; echo $?)"
chk "log left the outside file untouched" "$([ "$(cat "$TMPD/outside/ACTIVITY.md")" = "old" ]; echo $?)"

set_log_key "$LOGHOME/../outside/ACTIVITY.md"
out="$(wrap_log "wrap: dotdot" 2>&1)"; rc=$?
chk "log exits 1 on a .. path that escapes HOME" "$([ "$rc" -eq 1 ]; echo $?)"

set_log_key "relative/ACTIVITY.md"
out="$(wrap_log "wrap: relative" 2>&1)"; rc=$?
chk "log exits 1 on a relative path" "$([ "$rc" -eq 1 ]; echo $?)"

mkdir -p "$TMPD/projrepo"
printf '[wrap]\nactivity_log = "%s"\n' "$LOGHOME/PROJECT.md" > "$TMPD/projrepo/.kit.toml"
printf 'untouched\n' > "$LOGHOME/PROJECT.md"
printf '[wrap]\n' > "$KITROOT/kit.toml"
out="$(cd "$TMPD/projrepo" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: project toml" 2>&1)"; rc=$?
chk "log ignores a project .kit.toml key (exit 0)" "$rc"
chk "log says the line did not land" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q 'no wrap.activity_log key in the kit-root kit.toml; line not written'; echo $?)"
chk "log still prints the line it would have written" "$({ trap '' PIPE; printf '%s' "$out" 2>/dev/null || :; } | grep -q ' · wrap: project toml'; echo $?)"
chk "log left the project-named file untouched" "$([ "$(cat "$LOGHOME/PROJECT.md")" = "untouched" ]; echo $?)"

# The operator config overlay (SPEC-248) owns this key too: it is as trusted as the kit root,
# so its value overrides a kit-root value for the same key.
OPCONF="$TMPD/opconfig"; mkdir -p "$OPCONF"
printf 'operator base\n' > "$LOGHOME/OPERATOR.md"
printf 'kit-root base\n' > "$LOGHOME/KITROOT.md"
set_log_key "$LOGHOME/KITROOT.md"
printf '[wrap]\nactivity_log = "%s"\n' "$LOGHOME/OPERATOR.md" > "$OPCONF/kit.toml"
out="$(HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" KIT_CONFIG_OPERATOR="$OPCONF" \
  "$WRAP" log "wrap: operator toml" 2>&1)"; rc=$?
chk "log exits 0 with the operator kit.toml key set" "$rc"
chk "log prepends to the operator-named file" \
  "$([ "$(head -1 "$LOGHOME/OPERATOR.md")" = "$(date +%F) · wrap: operator toml" ]; echo $?)"
chk "log left the kit-root-named file untouched (operator wins)" \
  "$([ "$(cat "$LOGHOME/KITROOT.md")" = "kit-root base" ]; echo $?)"

# The configured log sits inside a repo's main checkout; a session working in a worktree of
# that repo gets the same repo-relative file inside its worktree, so the line is committable.
LOGREPO="$LOGHOME/logrepo"
git init -q "$LOGREPO" && git -C "$LOGREPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$LOGREPO/_meta" && printf 'main copy
' > "$LOGREPO/_meta/LOG.md"
git -C "$LOGREPO" add _meta/LOG.md && git -C "$LOGREPO" -c user.name=t -c user.email=t@t commit -q -m log
git -C "$LOGREPO" worktree add -q -b side "$LOGHOME/logrepo-wt"
set_log_key "$LOGREPO/_meta/LOG.md"
( cd "$LOGHOME/logrepo-wt" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: from a worktree" >/dev/null 2>&1 )
chk "log from a worktree prepends to the worktree's copy" \
  "$([ "$(head -1 "$LOGHOME/logrepo-wt/_meta/LOG.md")" = "$(date +%F) · wrap: from a worktree" ]; echo $?)"
chk "log from a worktree leaves the main checkout's copy untouched" \
  "$([ "$(cat "$LOGREPO/_meta/LOG.md")" = "main copy" ]; echo $?)"
( cd "$LOGHOME" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: from outside" >/dev/null 2>&1 )
chk "log from outside the repo prepends to the configured file itself" \
  "$([ "$(head -1 "$LOGREPO/_meta/LOG.md")" = "$(date +%F) · wrap: from outside" ]; echo $?)"

# ===========================================================================
echo "=== log: the --- anchor lands the entry below the header, not above it ==="
# ===========================================================================
ANCHFILE="$LOGHOME/ANCHOR.md"
printf '# LAB_LOG\n\nChronological log. Newest first.\n\n---\n\n2026-01-01 · old entry\n' > "$ANCHFILE"
set_log_key "$ANCHFILE"
wrap_log "wrap: anchored entry" >/dev/null 2>&1
chk "log: the title stays line 1, not pushed down" \
  "$([ "$(sed -n '1p' "$ANCHFILE")" = "# LAB_LOG" ]; echo $?)"
chk "log: the new entry lands right after the --- and its blank line" \
  "$([ "$(sed -n '7p' "$ANCHFILE")" = "$(date +%F) · wrap: anchored entry" ]; echo $?)"
chk "log: the previously-newest entry is now second" \
  "$([ "$(sed -n '8p' "$ANCHFILE")" = "2026-01-01 · old entry" ]; echo $?)"

FMFILE="$LOGHOME/FRONTMATTER.md"
printf -- '---\nkind: log\n---\n2026-01-01 · old entry\n' > "$FMFILE"
set_log_key "$FMFILE"
wrap_log "wrap: past the frontmatter" >/dev/null 2>&1
chk "log: frontmatter's opening --- is not mistaken for the anchor" \
  "$([ "$(sed -n '1p' "$FMFILE")" = "---" ]; echo $?)"
chk "log: the entry lands after the frontmatter's closing ---, not inside it" \
  "$([ "$(sed -n '4p' "$FMFILE")" = "$(date +%F) · wrap: past the frontmatter" ]; echo $?)"
chk "log: the frontmatter body is untouched" \
  "$([ "$(sed -n '2p' "$FMFILE")" = "kind: log" ]; echo $?)"

NOANCHFILE="$LOGHOME/NOANCHOR.md"
printf 'just a plain log, no header at all\n' > "$NOANCHFILE"
set_log_key "$NOANCHFILE"
wrap_log "wrap: no anchor falls back to prepend" >/dev/null 2>&1
chk "log: no --- anchor falls back to the old prepend-at-line-1 behavior" \
  "$([ "$(sed -n '1p' "$NOANCHFILE")" = "$(date +%F) · wrap: no anchor falls back to prepend" ]; echo $?)"

HDRONLYFILE="$LOGHOME/HDRONLY.md"
printf '# LAB_LOG\n\nChronological log.\n\n---\n' > "$HDRONLYFILE"
set_log_key "$HDRONLYFILE"
wrap_log "wrap: first entry in a header-only file" >/dev/null 2>&1
chk "log: a header-only file (no entries yet) still gets the entry after ---" \
  "$([ "$(sed -n '6p' "$HDRONLYFILE")" = "$(date +%F) · wrap: first entry in a header-only file" ]; echo $?)"

EMPTYFILE="$LOGHOME/EMPTY.md"
: > "$EMPTYFILE"
set_log_key "$EMPTYFILE"
wrap_log "wrap: an empty file still works" >/dev/null 2>&1
chk "log: an empty file gets the entry as line 1" \
  "$([ "$(sed -n '1p' "$EMPTYFILE")" = "$(date +%F) · wrap: an empty file still works" ]; echo $?)"

# ===========================================================================
echo "=== knowledge-root: the key, the HOME fence, and the repo argument ==="
# ===========================================================================
KRHOME="$TMPD/kr-home"; mkdir -p "$KRHOME/root-ok"
KROUTSIDE="$TMPD/kr-outside"; mkdir -p "$KROUTSIDE"
KRKITROOT="$TMPD/kr-kitroot"; mkdir -p "$KRKITROOT"
KRREPO="$TMPD/kr-repo"; mkdir -p "$KRREPO"
git -C "$KRREPO" init -q; gitc "$KRREPO"

set_kr_key() { printf '[knowledge]\nroot = "%s"\n' "$1" > "$KRKITROOT/kit.toml"; }
kr() { HOME="$KRHOME" KIT_CONFIG_ROOT="$KRKITROOT" "$WRAP" knowledge-root "$@"; }

printf '[knowledge]\n' > "$KRKITROOT/kit.toml"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: key empty exits 0" "$rc"
chk_has "knowledge-root: key empty prints the repo-local fallback" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: key empty creates nothing" "$([ ! -e "$KRREPO/.claude/memory" ]; echo $?)"

set_kr_key "$KRHOME/root-ok"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled, under HOME, existing, exits 0" "$rc"
chk_has "knowledge-root: prints <root>/projects/<basename>" "$out" "root-ok/projects/kr-repo"
chk "knowledge-root: creates <root>/projects/<basename>" "$([ -d "$KRHOME/root-ok/projects/kr-repo" ]; echo $?)"

set_kr_key "$KRHOME/missing-root"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled but missing still exits 0 (fallback, not an error)" "$rc"
chk_has "knowledge-root: filled but missing falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk_has "knowledge-root: filled but missing names the reason on stderr" "$out" "knowledge-root:"
chk "knowledge-root: filled but missing creates nothing under the still-missing root" \
  "$([ ! -e "$KRHOME/missing-root" ]; echo $?)"

set_kr_key "$KROUTSIDE"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: filled but outside HOME falls back, exit 0" "$rc"
chk_has "knowledge-root: outside HOME falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: outside HOME creates nothing there" "$([ ! -e "$KROUTSIDE/projects" ]; echo $?)"

ln -s "$KROUTSIDE" "$KRHOME/link-outside"
set_kr_key "$KRHOME/link-outside"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a symlink resolving outside HOME falls back, exit 0" "$rc"
chk_has "knowledge-root: symlink-outside falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: symlink-outside creates nothing under the real target" \
  "$([ ! -e "$KROUTSIDE/projects" ]; echo $?)"

# The fence resolves `<root>` only. `mkdir -p` walks straight through a symlink at
# `<root>/projects`, so the created directory lands wherever that symlink points.
KRESC="$TMPD/kr-escape"; mkdir -p "$KRESC"
mkdir -p "$KRHOME/root-esc"; ln -s "$KRESC" "$KRHOME/root-esc/projects"
set_kr_key "$KRHOME/root-esc"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a symlinked projects dir falls back, exit 0" "$rc"
chk_has "knowledge-root: symlinked projects falls back on stdout" "$out" "$KRREPO/.claude/memory"
chk "knowledge-root: creates nothing under the symlink target" \
  "$([ ! -e "$KRESC/kr-repo" ]; echo $?)"

# `config seams` calls a root equal to $HOME `filled`, so the consumer must accept it too:
# an advisor that disagrees with the thing it advises on is the bug this closes.
KRHOME_REAL="$(cd "$KRHOME" && pwd -P)"
set_kr_key "$KRHOME"
out="$(kr "$KRREPO" 2>&1)"; rc=$?
chk "knowledge-root: a root equal to HOME itself exits 0" "$rc"
chk_has "knowledge-root: HOME-as-root prints <HOME>/projects/<basename>" \
  "$out" "$KRHOME_REAL/projects/kr-repo"
chk "knowledge-root: HOME-as-root creates the directory" \
  "$([ -d "$KRHOME_REAL/projects/kr-repo" ]; echo $?)"

out="$(kr 2>&1)"; rc=$?
chk "knowledge-root: missing repo argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

out="$(kr "$KRREPO/no-such-subdir/.." 2>&1)"; rc=$?
chk "knowledge-root: repo arg ending in /.. exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

out="$(kr / 2>&1)"; rc=$?
chk "knowledge-root: repo arg resolving to / exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

# The only write this verb does is `mkdir -p` under `<root>/projects/<base>`, which sits
# OUTSIDE `<repo>` entirely -- so a `<repo>` with no `.git` at all must not block it. The
# old `_write_guard "$repo_real"` call shelled out to `git -C "$repo" rev-parse`, which
# fails on a non-git dir and printed the misleading "index.lock held by another writer".
KRNONGIT="$TMPD/kr-nongit-repo"; mkdir -p "$KRNONGIT"
set_kr_key "$KRHOME/root-ok"
out="$(kr "$KRNONGIT" 2>&1)"; rc=$?
chk "knowledge-root: non-git repo dir, filled+existing root, exits 0" "$rc"
chk_has "knowledge-root: non-git repo prints <root>/projects/<basename>" \
  "$out" "root-ok/projects/kr-nongit-repo"
chk "knowledge-root: non-git repo creates <root>/projects/<basename>" \
  "$([ -d "$KRHOME/root-ok/projects/kr-nongit-repo" ]; echo $?)"
chk_no "knowledge-root: non-git repo never prints the index.lock message" \
  "$out" "index.lock held by another writer"

# ===========================================================================
echo "=== stage: default paths, dedupe, the fences, and the worktree copy ==="
# ===========================================================================
STAGEHOME="$TMPD/stage-home"; mkdir -p "$STAGEHOME"
mk_stage_repo() { # mk_stage_repo <name> -- prints the new repo's path
  local d="$TMPD/stage-$1"
  mkdir -p "$d"; git -C "$d" init -q; gitc "$d"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s' "$d"
}

R1="$(mk_stage_repo one)"
out="$(cd "$R1" && "$WRAP" stage "My First Title" "the intent" "the home" 2>&1)"; rc=$?
chk "stage: default paths exits 0" "$rc"
chk "stage: creates _meta/backlog-staging.md" "$([ -f "$R1/_meta/backlog-staging.md" ]; echo $?)"
chk_has "stage: appends the rendered block" "$(cat "$R1/_meta/backlog-staging.md")" "## [staged] My First Title"

out="$(cd "$R1" && "$WRAP" stage "my   FIRST title!!" "x" "y" 2>&1)"; rc=$?
chk "stage: a dup differing in case/spacing/punctuation exits 0" "$rc"
chk_has "stage: the dup prints already staged" "$out" "already staged"
DUP_COUNT="$(grep -c '^## \[staged\]' "$R1/_meta/backlog-staging.md")"
chk "stage: the dup wrote no second block" "$([ "$DUP_COUNT" -eq 1 ]; echo $?)"

R2="$(mk_stage_repo two)"
mkdir -p "$STAGEHOME/override-home"
: > "$STAGEHOME/override-home/staging.md"
out="$(cd "$R2" && BACKLOG_STAGE_STAGING="$STAGEHOME/override-home/staging.md" HOME="$STAGEHOME" \
  "$WRAP" stage "Override Path Title" "i" "h" 2>&1)"; rc=$?
chk "stage: BACKLOG_STAGE_STAGING under HOME honoured, exit 0" "$rc"
chk_has "stage: writes the overridden path" \
  "$(cat "$STAGEHOME/override-home/staging.md")" "## [staged] Override Path Title"
chk "stage: never touches the repo default path" "$([ ! -e "$R2/_meta/backlog-staging.md" ]; echo $?)"

# The override reaches wrap through the environment, which a repo `.envrc` writes. An absent
# leaf under HOME is exactly the shape that would let it seed a staging block into an agent
# instruction file, so the override may only append to a file that already exists.
R2B="$(mk_stage_repo two-b)"
ABSENT="$STAGEHOME/override-home/absent-instructions.md"
out="$(cd "$R2B" && BACKLOG_STAGE_STAGING="$ABSENT" HOME="$STAGEHOME" \
  "$WRAP" stage "Injected Row" "i" "h" 2>&1)"; rc=$?
chk "stage: an env-override at an absent file refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the existing-regular-file rule" "$out" "not an existing regular file"
chk "stage: the absent override path is still absent" "$([ ! -e "$ABSENT" ]; echo $?)"

R3="$(mk_stage_repo three)"
mkdir -p "$R3/_meta"; ln -s /etc/hosts "$R3/_meta/backlog-staging.md"
out="$(cd "$R3" && "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: a symlinked target refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the reason on stderr" "$out" "wrap stage:"
chk "stage: the symlink itself is left alone" "$([ -L "$R3/_meta/backlog-staging.md" ]; echo $?)"

R4="$(mk_stage_repo four)"
mkdir -p "$STAGEHOME/elsewhere" "$STAGEHOME/some-other-home"
out="$(cd "$R4" && BACKLOG_STAGE_STAGING="$STAGEHOME/elsewhere/staging.md" HOME="$STAGEHOME/some-other-home" \
  "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: outside the repo and outside HOME refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk "stage: nothing written outside" "$([ ! -e "$STAGEHOME/elsewhere/staging.md" ]; echo $?)"

out="$("$WRAP" stage "T" "i" "h" --repo "$TMPD/not-a-repo" 2>&1)"; rc=$?
chk "stage: a non-git --repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

R5="$(mk_stage_repo five)"
mkdir -p "$R5/_meta"; : > "$R5/_meta/backlog-staging.md"; chmod 400 "$R5/_meta/backlog-staging.md"
out="$(cd "$R5" && "$WRAP" stage "T" "i" "h" 2>&1)"; rc=$?
chk "stage: an unwritable target relays FAILED, exit 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "stage: relays the FAILED line" "$out" "FAILED"
chmod 644 "$R5/_meta/backlog-staging.md"

R6MAIN="$TMPD/stage-six"
git init -q "$R6MAIN" && git -C "$R6MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R6MAIN/_meta"
printf '# Backlog staging\n\n' > "$R6MAIN/_meta/backlog-staging.md"
git -C "$R6MAIN" add _meta/backlog-staging.md
git -C "$R6MAIN" -c user.name=t -c user.email=t@t commit -q -m stage
git -C "$R6MAIN" worktree add -q -b stage-side "$TMPD/stage-six-wt"
out="$(cd "$TMPD/stage-six-wt" && "$WRAP" stage --repo "$R6MAIN" "From The Worktree" "i" "h" 2>&1)"; rc=$?
chk "stage: run from a worktree exits 0" "$rc"
chk_has "stage: writes the worktree's own copy" \
  "$(cat "$TMPD/stage-six-wt/_meta/backlog-staging.md")" "## [staged] From The Worktree"
chk_no "stage: the main checkout's copy is left alone" \
  "$(cat "$R6MAIN/_meta/backlog-staging.md")" "## [staged] From The Worktree"

# The checks above run on the path BEFORE `_worktree_copy` swaps in the current worktree's own
# copy. A symlink at that copy redirects the append anywhere, so the refusal runs again after.
WTHOME="$TMPD/wt-home"; mkdir -p "$WTHOME"
CANARY="$TMPD/wt-canary.md"; printf 'canary untouched\n' > "$CANARY"
R7MAIN="$WTHOME/stage-seven"
git init -q "$R7MAIN" && git -C "$R7MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R7MAIN/_meta"
printf '# Backlog staging\n\n' > "$R7MAIN/_meta/backlog-staging.md"
git -C "$R7MAIN" add _meta/backlog-staging.md
git -C "$R7MAIN" -c user.name=t -c user.email=t@t commit -q -m stage
git -C "$R7MAIN" worktree add -q -b stage-evil "$WTHOME/stage-seven-wt"
rm -f "$WTHOME/stage-seven-wt/_meta/backlog-staging.md"
ln -s "$CANARY" "$WTHOME/stage-seven-wt/_meta/backlog-staging.md"
CANARY_BEFORE="$(shasum -a 256 "$CANARY" | cut -d' ' -f1)"
out="$(cd "$WTHOME/stage-seven-wt" && HOME="$WTHOME" "$WRAP" stage --repo "$R7MAIN" "Redirected Row" "i" "h" 2>&1)"; rc=$?
chk "stage: a symlinked worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names the symlink on stderr" "$out" "is a symlink"
chk "stage: the canary outside HOME is byte-identical" \
  "$([ "$CANARY_BEFORE" = "$(shasum -a 256 "$CANARY" | cut -d' ' -f1)" ]; echo $?)"

# Same shape for `wrap log`: the configured activity_log is fenced, its worktree copy is not.
LOGWTKIT="$TMPD/wt-kitroot"; mkdir -p "$LOGWTKIT"
LOGCANARY="$TMPD/wt-log-canary.md"; printf 'log canary untouched\n' > "$LOGCANARY"
R8MAIN="$WTHOME/log-eight"
git init -q "$R8MAIN" && git -C "$R8MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R8MAIN/_meta"
printf 'main copy\n' > "$R8MAIN/_meta/LOG.md"
git -C "$R8MAIN" add _meta/LOG.md
git -C "$R8MAIN" -c user.name=t -c user.email=t@t commit -q -m log
git -C "$R8MAIN" worktree add -q -b log-evil "$WTHOME/log-eight-wt"
rm -f "$WTHOME/log-eight-wt/_meta/LOG.md"
ln -s "$LOGCANARY" "$WTHOME/log-eight-wt/_meta/LOG.md"
printf '[wrap]\nactivity_log = "%s"\n' "$R8MAIN/_meta/LOG.md" > "$LOGWTKIT/kit.toml"
LOGCANARY_BEFORE="$(shasum -a 256 "$LOGCANARY" | cut -d' ' -f1)"
out="$(cd "$WTHOME/log-eight-wt" && HOME="$WTHOME" KIT_CONFIG_ROOT="$LOGWTKIT" "$WRAP" log "wrap: redirected" 2>&1)"; rc=$?
chk "log: a symlinked worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "log: names the symlink on stderr" "$out" "is a symlink"
chk "log: the canary outside HOME is byte-identical" \
  "$([ "$LOGCANARY_BEFORE" = "$(shasum -a 256 "$LOGCANARY" | cut -d' ' -f1)" ]; echo $?)"

# A symlink at a PARENT directory of the worktree copy escapes a leaf-only refusal and a
# prefix fence run on the unresolved string: `wt/_meta` pointing at a directory outside HOME
# still leaves `wt/_meta/<file>` looking like a plain file under the worktree. Both verbs must
# resolve the copied path before they fence it.
PDHOME="$TMPD/pd-home"; mkdir -p "$PDHOME"
PDOUT="$TMPD/pd-outside/_meta"; mkdir -p "$PDOUT"
printf 'staging canary untouched\n' > "$PDOUT/backlog-staging.md"
printf 'log canary untouched\n' > "$PDOUT/LOG.md"
R9MAIN="$PDHOME/pd-main"
git init -q "$R9MAIN" && git -C "$R9MAIN" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$R9MAIN/_meta"
printf '# Backlog staging\n\n' > "$R9MAIN/_meta/backlog-staging.md"
printf 'main copy\n' > "$R9MAIN/_meta/LOG.md"
git -C "$R9MAIN" add _meta
git -C "$R9MAIN" -c user.name=t -c user.email=t@t commit -q -m meta
git -C "$R9MAIN" worktree add -q -b pd-side "$PDHOME/pd-wt"
rm -rf "$PDHOME/pd-wt/_meta"
ln -s "$TMPD/pd-outside/_meta" "$PDHOME/pd-wt/_meta"
git -C "$PDHOME/pd-wt" add _meta 2>/dev/null
git -C "$PDHOME/pd-wt" -c user.name=t -c user.email=t@t commit -q -m symlinked-meta 2>/dev/null
PD_STAGE_BEFORE="$(shasum -a 256 "$PDOUT/backlog-staging.md" | cut -d' ' -f1)"
PD_LOG_BEFORE="$(shasum -a 256 "$PDOUT/LOG.md" | cut -d' ' -f1)"

out="$(cd "$PDHOME/pd-wt" && HOME="$PDHOME" "$WRAP" stage --repo "$R9MAIN" "Parent Symlink Row" "i" "h" 2>&1)"; rc=$?
chk "stage: a parent-dir symlink on the worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "stage: names a reason on stderr" "$out" "wrap stage:"
chk "stage: the staging canary outside HOME is byte-identical" \
  "$([ "$PD_STAGE_BEFORE" = "$(shasum -a 256 "$PDOUT/backlog-staging.md" | cut -d' ' -f1)" ]; echo $?)"

PDKIT="$TMPD/pd-kitroot"; mkdir -p "$PDKIT"
printf '[wrap]\nactivity_log = "%s"\n' "$R9MAIN/_meta/LOG.md" > "$PDKIT/kit.toml"
out="$(cd "$PDHOME/pd-wt" && HOME="$PDHOME" KIT_CONFIG_ROOT="$PDKIT" "$WRAP" log "wrap: parent symlink" 2>&1)"; rc=$?
chk "log: a parent-dir symlink on the worktree copy refuses, exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "log: names a reason on stderr" "$out" "wrap log:"
chk "log: the log canary outside HOME is byte-identical" \
  "$([ "$PD_LOG_BEFORE" = "$(shasum -a 256 "$PDOUT/LOG.md" | cut -d' ' -f1)" ]; echo $?)"

# ===========================================================================
echo "=== help and usage ==="
# ===========================================================================
out="$("$WRAP" --help 2>&1)"; rc=$?
chk "--help exits 0" "$rc"
for verb in scan apply merge log default-branch knowledge-root stage; do
  chk_has "--help names $verb" "$out" "$verb"
done
out="$("$WRAP" scan 2>&1)"; rc=$?
chk "scan with no argument exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" apply 2>&1)"; rc=$?
chk "apply with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" merge 2>&1)"; rc=$?
chk "merge with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" log 2>&1)"; rc=$?
chk "log with no text exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" knowledge-root 2>&1)"; rc=$?
chk "knowledge-root with no repo exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" stage 2>&1)"; rc=$?
chk "stage with no args exits 64" "$([ "$rc" -eq 64 ]; echo $?)"
out="$("$WRAP" bogus 2>&1)"; rc=$?
chk "an unknown verb exits 64" "$([ "$rc" -eq 64 ]; echo $?)"

# ------------------------------------------------------- autonomy knobs (wrap.*)
# The three knobs `commands/wrap.md` reads at step -1. They govern a write each, so the
# fence that matters is the third block: a project `.kit.toml` rides inside a pull request
# and must never widen what wrap does to the machine running it.
echo
echo "=== autonomy knobs ==="
# shellcheck source=/dev/null
. "$KIT_DIR/lib/config/kit-config.sh"
KNOB_OP="$TMPD/knob-operator"; KNOB_PROJ="$TMPD/knob-project"
mkdir -p "$KNOB_OP" "$KNOB_PROJ"
printf '[wrap]\nmerge_own_prs = false\ntidy_worktrees = false\nbuild_candidates = false\n' > "$KNOB_OP/kit.toml"
printf '[wrap]\nmerge_own_prs = false\ntidy_worktrees = false\nbuild_candidates = false\n' > "$KNOB_PROJ/.kit.toml"
for knob in merge_own_prs tidy_worktrees build_candidates; do
  v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob ships as true" "$([ "$v" = "true" ]; echo $?)"
  v="$(KIT_CONFIG_OPERATOR="$KNOB_OP" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob honours the operator kit.toml" "$([ "$v" = "false" ]; echo $?)"
  v="$(KIT_PROJECT_ROOT="$KNOB_PROJ" kit_config_get_root "wrap.$knob" true)"
  chk "wrap.$knob ignores a project .kit.toml" "$([ "$v" = "true" ]; echo $?)"
done
for knob in merge_own_prs tidy_worktrees build_candidates; do
  chk_has "commands/wrap.md reads wrap.$knob" "$(cat "$KIT_DIR/commands/wrap.md")" "wrap.$knob"
  chk_has "kit.toml declares $knob" "$(cat "$KIT_DIR/kit.toml")" "$knob"
done

# ------------------------------------------------- main-checkout resolver recipe
# `commands/wrap.md` step 5 prescribes one recipe for turning the session cwd into the
# repo argument `wrap apply` needs: `--git-common-dir` minus the trailing `/.git`. Run from
# a worktree the naive `$PWD` yields the feature branch, `apply` takes its non-default-branch
# path, and the checkout never pulls. This asserts the recipe, not the model following it.
echo
echo "=== main-checkout resolver ==="
RES="$TMPD/resolver"; mkdir -p "$RES"
(
  cd "$RES" || exit 1
  git init -q -b main . && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git worktree add -q wt -b feature >/dev/null 2>&1
) >/dev/null 2>&1
main_real="$(cd "$RES" && pwd -P)"
resolved="$(git -C "$RES/wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
resolved="${resolved%/.git}"
resolved="$(cd "$resolved" 2>/dev/null && pwd -P)"
chk "the recipe resolves a worktree to the main checkout" "$([ "$resolved" = "$main_real" ]; echo $?)"
chk "the main checkout is on the default branch, so apply pulls" \
  "$([ "$(git -C "$main_real" branch --show-current)" = "main" ]; echo $?)"
chk "the naive cwd would have been the feature branch" \
  "$([ "$(git -C "$RES/wt" branch --show-current)" = "feature" ]; echo $?)"
chk_has "commands/wrap.md prescribes the recipe" "$(cat "$KIT_DIR/commands/wrap.md")" "--git-common-dir"

# ------------------------------------------------------------- report lint
# The `Needs you` admission test, mechanised. The first case is the REAL defect that
# started this work: a green own PR parked behind "say go and I merge it".
echo
echo "=== report lint ==="
LINT="$KIT_DIR/lib/wrap/report-lint.sh"
# Every fixture carries a `**Built:**` and a `**Seam:**` line because commands/wrap.md makes
# both REQUIRED of any wrap report: step 7b must report which of built / NOTHING / SKIPPED
# happened, and step -1 owes the same three states for the before/after seams. The fixtures
# below exercise the `Needs you` lens, so they satisfy both rules and leave them alone. Each
# rule gets its own cases further down.
_report() { printf '## Wrap: t\n\n%s\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- %s\n' "$1" "${2:-body}"; }

out="$(_report '🔴 **Needs you:**
a. REVIEW then merge #523. Say go and I merge it.' | bash "$LINT" 2>&1)"; rc=$?
chk "the original defect fails the lint" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending item" "$out" "asks permission instead of naming a blocker"

out="$(_report '✅ **Needs you:** NOTHING' 'say go and I merge it' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING passes, and What happened is never judged" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '🔴 **Needs you:**
a. UNBLOCK the deploy. It is blocked on a credential only you can read.' | bash "$LINT" 2>&1)"; rc=$?
chk "a real blocker passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '🔴 **Needs you:**
a. RUN gh pr merge 12 --squash.' | bash "$LINT" 2>&1)"; rc=$?
chk "a self-runnable command with no blocker warns, does not fail" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the command class" "$out" "names a command the kit can run"

out="$(_report '🔴 **Needs you:**
a. RUN gh pr merge 12 once security signs off; it is blocked on their approval.' | bash "$LINT" 2>&1)"; rc=$?
chk_no "a stated blocker clears the warn" "$out" "names a command the kit can run"

out="$(printf 'no needs-you section at all\n\n**Built:** SKIPPED: build_candidates knob is false\n\n**Seam:** SKIPPED: no seam\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Needs you block is clean" "$([ "$rc" -eq 0 ]; echo $?)"

# The Built rule itself. commands/wrap.md: step 7b owes exactly one of built / NOTHING /
# SKIPPED, so a skipped 7b can never read as an empty one. The lint shipped with no test.
out="$(printf 'no needs-you section at all\n\n**Seam:** NOTHING: no seam configured\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Built line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names step 7b" "$out" "step 7b (build the candidates) owes an outcome"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's/^\*\*Built:\*\* .*/**Built:**/' | bash "$LINT" 2>&1)"; rc=$?
chk "an empty Built line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty; name what was built"

# The three states must stay distinguishable, and a non-empty line must name the home it
# joins. `SKIPPED: nothing to build` (two states in one) appeared thirteen times in two weeks
# of real reports; `Built: <path> @ <sha>` with no ENHANCE/NEW was every "built" line in the
# same window, and each one was the session's own deliverable, not a 7b candidate.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** lib/wrap/report-lint.sh @ abc1234|' | bash "$LINT" 2>&1)"; rc=$?
chk "a Built line that is only a path and a commit fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding asks for the ENHANCE or NEW token" "$out" "no ENHANCE <home> or NEW (precedent: ...) token"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: nothing to build|' | bash "$LINT" 2>&1)"; rc=$?
chk "SKIPPED: nothing to build fails (an empty scan is NOTHING)" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the two-states-in-one shape" "$out" "an empty scan is 'NOTHING: no candidates', not a skip"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line naming the home and insertion point passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (staged)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying the precedent miss passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: build_candidates knob is false|' | bash "$LINT" 2>&1)"; rc=$?
chk "a real SKIPPED reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The lane suffix. commands/wrap.md step 7b routes every candidate through
# lib/classify/lane-classify.sh: a tiny-lane candidate is built here and carries the check
# that proved it, anything heavier is staged with its goal drafted. Both shapes append to the
# same line, so the ENHANCE/NEW token must survive the suffix, and the suffix alone must never
# stand in for the token.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=tiny and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged + goal drafted: .claude/goals/cron-fire.md)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=normal and its goal draft passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged: build_candidates off)|' | bash "$LINT" 2>&1)"; rc=$?
chk "the knob-false shape, a lane with no goal draft, passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** lib/wrap/report-lint.sh (lane=tiny, verified: bash tests/test-wrap.sh, abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane suffix with no ENHANCE or NEW still fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still asks for the ENHANCE or NEW token" "$out" "no ENHANCE <home> or NEW (precedent: ...) token"

# The lane closure rule. `wrap.build_lanes` lets an operator list heavier lanes for step 7b to
# build inline, so `lane=normal` and `lane=bug` are now legal on a verified item and the lint
# can no longer treat `tiny` as the only buildable lane. What it does enforce is the pairing: a
# lane token says the candidate was sized and nothing about what became of it, so every item
# naming a lane owes `verified:` or a `staged` form.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=normal, verified: bash tests/test-alert.sh, #418)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=normal and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=bug, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=bug and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, staged: build_lanes excludes full)|' | bash "$LINT" 2>&1)"; rc=$?
chk "the build_lanes exclusion shape passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane with neither a check nor a staged form fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the missing closure" "$out" "names a lane with no closure"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- alpha ENHANCE tools/x: file.sh (lane=normal, verified: bash tests/test-x.sh, #12)\n- beta NEW (precedent: nothing matched): tools/beta (lane=bug)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "one unclosed lane among good bullets fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "item 2"

chk_has "commands/wrap.md classifies each candidate's lane" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/classify/lane-classify.sh classify"
chk_has "commands/wrap.md names the worker model tiers" "$(cat "$KIT_DIR/commands/wrap.md")" "Sonnet is the default worker"
chk_has "commands/wrap.md reads the build_lanes knob" "$(cat "$KIT_DIR/commands/wrap.md")" "kit_config_get_root wrap.build_lanes"
chk_has "kit.toml ships build_lanes defaulting to tiny" "$(cat "$KIT_DIR/kit.toml")" 'build_lanes = "tiny"'
# The LIST form: a bare `**Built:**` header followed by `- ` bullets, one candidate per
# line. Added after a real report crammed three candidates onto one unreadable line. Each
# bullet owes the same ENHANCE/NEW token as the inline form, checked per bullet, so one bare
# item among several good ones cannot hide the way it did when the whole line was one string.
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- untracked-blocks-ff-pull NEW (precedent: nothing matched): dwarvesf/dwarves-kit lib/wrap, the pull path in wrap apply (staged)\n- mini-script-run-loop ENHANCE ops-toolkit tools/mac-mini-substrate/mini-run (no change needed, precedent hit is the helper itself)\n- sandbox-overlap-probe ENHANCE dwarvesf/foundation-ops fleet/knowledge-guard (already homed as OPS-16)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a three-bullet Built list passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- alpha ENHANCE tools/x: file.sh (abc1234)\n- lib/wrap/report-lint.sh @ def5678\n- gamma NEW (precedent: nothing matched): tools/gamma (staged)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a list with one bare path-and-commit bullet fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "bullet 2"
chk_has "the finding quotes the bare bullet" "$out" "lib/wrap/report-lint.sh @ def5678"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a bare Built header with no bullets and no inline content fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:** NOTHING: no candidates\n- stray ENHANCE tools/x: file.sh (abc1234)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING inline mixed with bullets fails, the two grammars never combine" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the mixed-grammar shape" "$out" "both inline content and bullets"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "NOTHING inline alone still passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The prose rule. `bin/precedent` indexes memory notes and research files as hit kinds, so a
# step 7b whose top hit is a note turns a build into a write and still carries the ENHANCE
# token. On 2026-09-10 a procedure run six times by hand, which had already cost a bad
# production deploy, produced two memory notes and one research note and zero mechanism, and
# the report linted clean. The same precedent output named `lib/wrap/wrap.sh` one line below
# the note, and the real fix landed there later: a code home beats a prose home.
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "an all-prose Built list fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the prose rule" "$out" "a precedent hit on a note is not a build"
chk_has "the finding says the code home wins" "$out" "the code home wins"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n- PROSE-ONLY: the call is one human judgment per run, no mechanism fits it\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "the same all-prose Built passes with a real PROSE-ONLY reason" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- PROSE-ONLY: none\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a too-short PROSE-ONLY reason cannot silence the rule" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)\n- pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a mixed Built passes, because something was built" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a single memory note fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the inline finding names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234) PROSE-ONLY: the pull path already guards itself, only the trap was new|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline PROSE-ONLY token with a real reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a code path still passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The harness-shape check: a `NEW (precedent: nothing matched)` candidate that turns out to
# speak CDP already has a home (browser-harness-js learnings), so it warns instead of passing
# clean, but it never fails the lint (the precedent check itself was still honest).
HARNESS_FIX="$TMPD/harness-fixture"; mkdir -p "$HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$HARNESS_FIX/probe.js"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (staged)|" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW item whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home" "$out" "browser-harness-js skills/cdp/learnings"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: ${HARNESS_FIX} (a1b2c3d)|" | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE item is never checked for harness shape, even over the same CDP content" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "no harness warn on an ENHANCE line" "$out" "browser-harness-js skills/cdp/learnings"

# The harness-shape check on a LIST-form bullet: the same token match, on a `- ` line.
LIST_HARNESS_FIX="$TMPD/harness-fixture-list"; mkdir -p "$LIST_HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$LIST_HARNESS_FIX/probe.js"
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- site-probe NEW (precedent: nothing matched): %s (staged)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' "$LIST_HARNESS_FIX" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW bullet whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home for a bullet item" "$out" "browser-harness-js skills/cdp/learnings"

printf 'echo "plain shell content, no CDP calls here"\n' > "$HARNESS_FIX/probe.js"
out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (staged)|" | bash "$LINT" 2>&1)"; rc=$?
chk "the same NEW path with plain content does not warn" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "no harness warn printed" "$out" "browser-harness-js skills/cdp/learnings"

# The Seam rule. Same three states as Built, for the same reason one level up: a seam that was
# never configured and a seam that was silently dropped read identically without the line, and
# the seam is where an operator's whole distill half lives.
out="$(printf 'no needs-you section at all\n\n**Built:** NOTHING: no candidates\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no Seam line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names step -1" "$out" "step -1 (the before/after seams) owes an outcome"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's/^\*\*Seam:\*\* .*/**Seam:**/' | bash "$LINT" 2>&1)"; rc=$?
chk "an empty Seam line fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty; name the side and skill that ran"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Seam:\*\* .*|**Seam:** after learning-ledger ran: KEPT 2 of 7 queued|' | bash "$LINT" 2>&1)"; rc=$?
chk "a Seam line naming the side and skill passes" "$([ "$rc" -eq 0 ]; echo $?)"

rc=0; bash "$LINT" /nonexistent-report-file >/dev/null 2>&1 || rc=$?
chk "a missing file exits 2" "$([ "$rc" -eq 2 ]; echo $?)"

chk_has "commands/wrap.md wires the lint into step 9" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/wrap/report-lint.sh"
chk_has "the FYI contract requires each follow-up to name its home" "$(cat "$KIT_DIR/commands/wrap.md")" "NAMES ITS HOME"
chk_no "FYI is not described as never a task" "$(cat "$KIT_DIR/commands/wrap.md")" "never a task"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap: all $PASS passed"
