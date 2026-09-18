#!/usr/bin/env bash
# test-wrap.sh -- SPEC-246 TASK-001: the whole acceptance matrix for `bin/wrap` and
# `lib/wrap/wrap.sh`.
#
# Fixture: three bare remotes whose default branches are `main`, `master` and `develop`,
# each with the branch set the gates discriminate on (merged-ancestor, unmerged, squash-ok,
# squash-stale, stacked-child, wt-clean, wt-dirty), clones with three secondary worktrees
# (clean, dirty, detached), a locked-worktree matrix clone (proven, dirty, unproven), a clone whose
# removal leaves the path behind, a clone whose origin/HEAD dangles, and a repo with no remote.
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
# git records a worktree path fully resolved, so a report line naming one carries the
# symlink-free form of TMPD on macOS (/private/var...), not the logical one.
TMPD_P="$(cd "$TMPD" && pwd -P)"
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
  api)
    # Only `user --jq .login` is asked for, so the login is the whole answer. A failing
    # call prints nothing, the way gh answers when the identity read fails.
    [ "${GH_STUB_API_RC:-0}" = "0" ] || exit "${GH_STUB_API_RC}"
    printf '%s\n' "${GH_STUB_LOGIN:-me}"
    exit 0 ;;
  pr)
    verb="${1:-}"; [ $# -gt 0 ] && shift
    case "$verb" in
      list)
        head=""; author=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --head) head="${2:-}"; shift 2 ;;
            --author) author="${2:-}"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [ -n "$head" ]; then
          key="GH_STUB_MERGED_$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')"
          eval "val=\"\${$key:-}\""
          [ -n "$val" ] || val="[]"
          printf '%s\n' "$val"
        else
          # --author sends real gh to the GraphQL search index, which lags a PR opened
          # seconds ago; the plain list reads the repository itself and never lags.
          if [ -n "$author" ]; then
            val="${GH_STUB_OPEN_PRS_SEARCH-${GH_STUB_OPEN_PRS:-[]}}"
          else
            val="${GH_STUB_OPEN_PRS:-[]}"
          fi
          # Real gh always answers with an author; default the fixtures that omit one.
          printf '%s\n' "$val" | jq -c --arg me "${GH_STUB_LOGIN:-me}" \
            '[.[] | if .author then . else . + {author: {login: $me}} end]'
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
            # A second detail read may serve a different body, so a case can model the PR
            # whose mergeability changes once the re-merge push lands.
            cnt_f="${GH_STUB_CALLS:-/dev/null}.view-$n"
            cnt=$(( $(cat "$cnt_f" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$cnt_f" 2>/dev/null
            if [ "$cnt" -gt 1 ]; then
              key2="GH_STUB_PR_${n}_2"; eval "val2=\"\${$key2:-}\""
              [ -n "${val2:-}" ] && val="$val2"
            fi
            [ -n "$val" ] || val="{}"
            # A %REMERGE_TIP% marker resolves against the real branch tip, because a
            # re-merge test cannot know the recovered commit's SHA before wrap creates it.
            if [ -n "${GH_STUB_LAND_REPO:-}" ]; then
              real_oid="$(git -C "$GH_STUB_LAND_REPO" rev-parse "${GH_STUB_LAND_BRANCH:-feat/union}" 2>/dev/null)"
              val="${val//%REMERGE_TIP%/$real_oid}"
            fi
            printf '%s\n' "$val" ;;
        esac
        exit 0 ;;
      create)
        # `land` reads the number off the printed URL, so the stub answers with one.
        printf '%s\n' "https://github.com/o/r/pull/${GH_STUB_CREATE_NUM:-42}"
        exit "${GH_STUB_CREATE_RC:-0}" ;;
      merge)
        # Stands in for GitHub's own squash landing on the default branch, so the
        # tree-verify step downstream has a real tree to compare against.
        if [ -n "${GH_STUB_LAND_REPO:-}" ]; then
          git -C "$GH_STUB_LAND_REPO" push -q "${GH_STUB_LAND_REMOTE:-origin}" \
            "${GH_STUB_LAND_BRANCH:-feat/union}:refs/heads/${GH_STUB_LAND_DEF:-main}" 2>/dev/null
        fi
        exit "${GH_STUB_MERGE_RC:-0}" ;;
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
  # The clean worktree's own branch is squash-merged too: a locked worktree is removed only under
  # the same merge proof a branch delete needs, so an unproven wt-clean would now be left alone.
  export GH_STUB_MERGED_wt_clean="[{\"headRefOid\":\"$(git -C "$bare" rev-parse wt-clean)\",\"baseRefName\":\"$def\",\"mergedAt\":\"2026-01-01T00:00:00Z\"}]"
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
chk_has "scan: the open-PR query names --repo" "$SCAN_CALLS" "pr list --repo ${SCAN_URL} --state open"

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
chk_has "apply dry-run: the proven locked worktree prints WOULD with path, branch and locked" "$out" \
  "WOULD remove worktree $TMPD_P/wt-scan-main-clean [wt-clean, locked] and delete wt-clean (squash-merged per gh)"
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
chk "apply --apply deleted merged-ancestor, squash-ok and the removed worktree's wt-clean" \
  "$([ "$branches" = "main squash-stale stacked-child unmerged wt-dirty " ]; echo $?)"
chk_no "apply --apply never touched the default branch" "$out" "delete main"
chk "apply --apply removed the clean worktree only" \
  "$([ ! -d "$TMPD/wt-apply-main-clean" ] && [ -d "$TMPD/wt-apply-main-dirty" ] && [ -d "$TMPD/wt-apply-main-det" ]; echo $?)"
chk_has "apply --apply names the removed worktree's path, branch and lock" "$out" \
  "remove worktree $TMPD_P/wt-apply-main-clean [wt-clean, locked] and delete wt-clean"
chk "apply --apply fast-forwarded the default branch" \
  "$([ "$(git -C "$APPLYREPO" rev-parse HEAD)" = "$NEW_TIP" ]; echo $?)"

# ===========================================================================
echo "=== apply --worktrees: the locked-worktree matrix (proven, dirty, unproven) ==="
# ===========================================================================
# One clone, three locked worktrees: the Agent tool locks every worktree it creates, so a lock is
# the normal state here and the merge proof, not the lock, decides.
git clone -q "$TMPD/bare-rmain" "$TMPD/clone-wtmatrix"
MTX="$TMPD/clone-wtmatrix"
gitc "$MTX"
git -C "$MTX" remote set-head origin main >/dev/null 2>&1
for b in merged-ancestor squash-stale wt-clean wt-dirty; do
  git -C "$MTX" branch "$b" "origin/$b" >/dev/null 2>&1
done
for pair in "proven wt-clean" "dirty wt-dirty" "unproven squash-stale"; do
  set -- $pair
  git -C "$MTX" worktree add "$TMPD/mtx-$1" "$2" >/dev/null 2>&1
  git -C "$MTX" worktree lock "$TMPD/mtx-$1" >/dev/null 2>&1
done
# Unlocked and proven: the report reads the real lock state rather than assuming one.
git -C "$MTX" worktree add "$TMPD/mtx-unlocked" merged-ancestor >/dev/null 2>&1
echo dirt > "$TMPD/mtx-dirty/dirt.txt"
set_stub rmain main

out="$("$WRAP" apply --worktrees "$MTX" 2>&1)"
chk_has "matrix dry-run: the proven locked worktree is a WOULD line" "$out" \
  "WOULD remove worktree $TMPD_P/mtx-proven [wt-clean, locked] and delete wt-clean"
chk_has "matrix dry-run: the locked dirty worktree still skips as dirty" "$out" \
  "SKIP $TMPD_P/mtx-dirty: dirty (another session's work stays)"
chk_has "matrix dry-run: the locked unproven worktree skips unproven" "$out" \
  "SKIP $TMPD_P/mtx-unproven: squash-stale is not proven merged into main (leave it)"
chk_has "matrix dry-run: an unlocked proven worktree reads as unlocked" "$out" \
  "WOULD remove worktree $TMPD_P/mtx-unlocked [merged-ancestor, unlocked] and delete merged-ancestor (ancestor of origin/main)"
chk "matrix dry-run removed nothing" \
  "$([ -d "$TMPD/mtx-proven" ] && [ -d "$TMPD/mtx-dirty" ] && [ -d "$TMPD/mtx-unproven" ]; echo $?)"

out="$("$WRAP" apply --apply --worktrees "$MTX" 2>&1)"; rc=$?
chk "matrix apply exits 0" "$rc"
chk "matrix apply removed the proven locked worktree" "$([ ! -e "$TMPD/mtx-proven" ]; echo $?)"
chk "matrix apply deleted the removed worktree's branch" \
  "$(git -C "$MTX" show-ref --verify --quiet refs/heads/wt-clean && echo 1 || echo 0)"
chk_has "matrix apply names the branch delete with its proof" "$out" \
  "delete wt-clean (squash-merged per gh, its locked worktree is gone)"
chk "matrix apply kept the dirty and unproven worktrees" \
  "$([ -d "$TMPD/mtx-dirty" ] && [ -d "$TMPD/mtx-unproven" ]; echo $?)"
chk "matrix apply kept the unproven worktree's branch" \
  "$(git -C "$MTX" show-ref --verify --quiet refs/heads/squash-stale; echo $?)"

# ===========================================================================
echo "=== apply --worktrees: the default branch and the main checkout's branch are off limits ==="
# ===========================================================================
# git allows a second worktree on an already-checked-out branch under --force, which is the only
# way either guard can be reached. Both would otherwise pass the merge proof: the default branch is
# an ancestor of itself, and a session's own branch may well be merged already.
make_clone guards rmain main unmerged
GUARDS="$TMPD/clone-guards"
git -C "$GUARDS" worktree add --force "$TMPD/wt-guards-default" main >/dev/null 2>&1
git -C "$GUARDS" worktree lock "$TMPD/wt-guards-default" >/dev/null 2>&1
git -C "$GUARDS" worktree add --force "$TMPD/wt-guards-cur" unmerged >/dev/null 2>&1
git -C "$GUARDS" worktree lock "$TMPD/wt-guards-cur" >/dev/null 2>&1
set_stub rmain main
out="$("$WRAP" apply --apply --worktrees "$GUARDS" 2>&1)"
chk_has "apply --worktrees: a worktree on the default branch is skipped" "$out" \
  "SKIP $TMPD_P/wt-guards-default: main is the default or a protected branch name"
chk_has "apply --worktrees: a worktree on the main checkout's branch is skipped" "$out" \
  "SKIP $TMPD_P/wt-guards-cur: unmerged is the main checkout's branch"
chk "apply --worktrees: both guarded worktrees and their branches survive" \
  "$([ -d "$TMPD/wt-guards-default" ] && [ -d "$TMPD/wt-guards-cur" ] \
     && git -C "$GUARDS" show-ref --verify --quiet refs/heads/main \
     && git -C "$GUARDS" show-ref --verify --quiet refs/heads/unmerged; echo $?)"

# ===========================================================================
echo "=== apply --apply --worktrees: a removal that leaves the path is FAILED, exit 2 ==="
# ===========================================================================
# The postcondition is the point: git prunes the admin entry even when it cannot delete the
# directory, so a report that trusted the exit code alone would call this worktree removed.
git clone -q "$TMPD/bare-rmain" "$TMPD/clone-wtpost"
POST="$TMPD/clone-wtpost"
gitc "$POST"
git -C "$POST" remote set-head origin main >/dev/null 2>&1
git -C "$POST" branch wt-clean origin/wt-clean >/dev/null 2>&1
mkdir -p "$TMPD/ro-parent"
git -C "$POST" worktree add "$TMPD/ro-parent/stuck" wt-clean >/dev/null 2>&1
git -C "$POST" worktree lock "$TMPD/ro-parent/stuck" >/dev/null 2>&1
set_stub rmain main
chmod 500 "$TMPD/ro-parent"
out="$("$WRAP" apply --apply --worktrees "$POST" 2>&1)"; rc=$?
chmod 700 "$TMPD/ro-parent"
chk "apply exits 2 when the postcondition fails" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "the failed postcondition is reported, not silent" "$out" \
  "FAILED remove worktree $TMPD_P/ro-parent/stuck [wt-clean, locked] and delete wt-clean (squash-merged per gh): $TMPD_P/ro-parent/stuck survived the removal, wt-clean not deleted"
chk "the stuck worktree path is still there" "$([ -d "$TMPD/ro-parent/stuck" ]; echo $?)"
# The branch delete is the half a silent postcondition would cost, so the worktree step must not
# reach it. The later branch pass may still delete the same proven branch under its own gate,
# which is why the assertion reads the step's own line rather than the ref.
chk_no "a failed postcondition never reaches the worktree step's branch delete" "$out" \
  "delete wt-clean (squash-merged per gh, its locked worktree is gone)"

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

# The worktree gate re-reads the tip after the merge proof, because the proof can cost a network
# round trip and `-D` discards a commit made inside that window.
sed 's/^wt-clean .*/wt-clean 3333333333333333333333333333333333333333/' \
  "$STALE_TIPS" > "$STALE_TIPS.new" && mv -f "$STALE_TIPS.new" "$STALE_TIPS"
out="$("$WRAP" apply --apply --worktrees --tips-file "$STALE_TIPS" "$TIPSREPO" 2>&1)"
chk_has "apply --worktrees: a worktree whose branch tip moved is skipped" "$out" \
  "SKIP $TMPD_P/wt-tips-clean: wt-clean tip moved during this run (3333333"
chk "apply --worktrees: the moved-tip worktree and branch survive" \
  "$([ -d "$TMPD/wt-tips-clean" ] && git -C "$TIPSREPO" show-ref --verify --quiet refs/heads/wt-clean; echo $?)"

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

# The same guard, at the worktree write site: the clean locked worktree is proven, so only the
# lock stands between it and a removal.
touch -t 202601010000 "$LOCKREPO/.git/index.lock"
out="$("$WRAP" apply --apply --worktrees "$LOCKREPO" 2>&1)"
rm -f "$LOCKREPO/.git/index.lock"
chk_has "apply --worktrees: a stale index.lock refuses the worktree removal" "$out" \
  "SKIP $TMPD_P/wt-lock-clean: index.lock held by another writer"
chk "apply --worktrees: the refused worktree is still there" "$([ -d "$TMPD/wt-lock-clean" ]; echo $?)"

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
out="$("$WRAP" apply --apply --worktrees "$BROKEN" 2>&1)"
chk_has "apply --worktrees: a failed fetch skips the worktree with the stale-proof reason" "$out" \
  "SKIP $TMPD_P/wt-brokenremote-clean: fetch failed, stale merge proof for wt-clean"
chk "apply --worktrees: the broken-remote repo lost no worktree" \
  "$([ -d "$TMPD/wt-brokenremote-clean" ]; echo $?)"
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
echo "=== apply: wrap.pull_past_dirty stashes only the blocking files ==="
# ===========================================================================
# Real repos again, for the same reason: what git refuses to overwrite during a fast-forward
# is the subject, and no stubbed `git` refuses anything.
A_BASE=$'a1\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'
A_REMOTE=$'a1 remote\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'
A_LOCAL_FAR=$'a1\na2\na3\na4\na5\na6\na7\na8\na9\na10 local\n'
A_LOCAL_SAME=$'a1 local\na2\na3\na4\na5\na6\na7\na8\na9\na10\n'

PD_ON="$TMPD/pd-knob-on"; mkdir -p "$PD_ON"
printf '[wrap]\npull_past_dirty = true\n' > "$PD_ON/kit.toml"
PD_PROJ="$TMPD/pd-knob-project"; mkdir -p "$PD_PROJ"
printf '[wrap]\npull_past_dirty = true\n' > "$PD_PROJ/.kit.toml"

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

echo "--- knob on: a union-marked file blocked by the same pull resolves during the pop"
build_pd_repo union; advance_pd_repo union also-lab
PU="$TMPD/pdclone-union"
printf '%s' "$A_LOCAL_FAR" > "$PU/A.md"
printf '%s' "$LAB_LOCAL" > "$PU/_meta/LAB_LOG.md"
out="$(KIT_CONFIG_OPERATOR="$PD_ON" "$WRAP" apply --apply "$PU" 2>&1)"; rc=$?
chk "union pop: apply exits 0" "$rc"
chk_has "union pop: both blocking files were stashed" "$out" "stashed 2 dirty tracked file(s)"
chk_no "union pop: the union file never conflicted" "$out" "POP CONFLICT"
chk "union pop: the incoming log line landed" \
  "$(grep -qF 'remote: the incoming line' "$PU/_meta/LAB_LOG.md"; echo $?)"
chk "union pop: the local log line survived" \
  "$(grep -qF 'local: the other session line' "$PU/_meta/LAB_LOG.md"; echo $?)"
chk "union pop: no stash is left behind" "$([ "$(pd_stash_count "$PU")" = "0" ]; echo $?)"

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

# feat/wrap stops being a fake OID here: `merge --apply`'s tree-verify needs a real local
# commit to check, so give the branch one and land its exact content on the remote's main,
# standing in for the squash `gh pr merge` performs on GitHub's own side (this stub never
# pushes anything for real).
MERGE_CUR="$(git -C "$TMPD/clone-scan-main" branch --show-current)"
git -C "$TMPD/clone-scan-main" fetch -q origin main
git -C "$TMPD/clone-scan-main" checkout -q -b feat/wrap origin/main
echo "wrap the session" > "$TMPD/clone-scan-main/wrap-note.txt"
git -C "$TMPD/clone-scan-main" add -A
git -C "$TMPD/clone-scan-main" commit -qm "wrap the session"
PR7_OID="$(git -C "$TMPD/clone-scan-main" rev-parse feat/wrap)"
git -C "$TMPD/clone-scan-main" checkout -q "$MERGE_CUR"
export GH_STUB_PR_7="{\"number\":7,\"title\":\"wrap the session\",\"headRefName\":\"feat/wrap\",\"headRefOid\":\"$PR7_OID\",\"baseRefName\":\"main\",\"mergeable\":\"MERGEABLE\",\"mergeStateStatus\":\"CLEAN\",\"reviewDecision\":\"APPROVED\",\"statusCheckRollup\":[{\"conclusion\":\"SUCCESS\"},{\"conclusion\":\"SKIPPED\"}]}"
git -C "$TMPD/clone-scan-main" push -q "$TMPD/bare-rmain" feat/wrap:refs/heads/main

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
chk_has "merge --apply reports the merge, tree verified" "$out" "merged #7 (1a2b3c4d5e6f): tree verified"
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

echo "=== merge: a draft PR skips even when GitHub reports it mergeable and clean ==="
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":true}')"
chk_has "merge: a draft skips" "$out" "SKIP #9 gate case: draft"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}')"
chk_has "merge: isDraft=false stays eligible" "$out" "eligible #9 gate case [feat/gate]"
out="$(gate_verdict '{"number":9,"title":"gate case","headRefName":"feat/gate","headRefOid":"aa","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}')"
chk_has "merge: a missing isDraft field (older fixture) stays eligible" "$out" "eligible #9 gate case [feat/gate]"

echo "=== merge: a newer draft does not block an older ready PR ==="
DRAFT_OPEN='[{"number":19,"title":"wip","headRefName":"feat/wip"},{"number":18,"title":"ready","headRefName":"feat/ready"}]'
DRAFT_PR_19='{"number":19,"title":"wip","headRefName":"feat/wip","headRefOid":"dd","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[],"isDraft":true}'
DRAFT_PR_18='{"number":18,"title":"ready","headRefName":"feat/ready","headRefOid":"ee","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[],"isDraft":false}'
out="$(GH_STUB_OPEN_PRS="$DRAFT_OPEN" GH_STUB_PR_19="$DRAFT_PR_19" GH_STUB_PR_18="$DRAFT_PR_18" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge: the newer draft is skipped" "$out" "SKIP #19 wip: draft"
chk_has "merge: the older ready PR is picked" "$out" "eligible #18 ready [feat/ready]"

echo "=== merge: a PR the search index has not indexed yet is still found ==="
# The reported shape: an own green PR opened minutes earlier is absent from the
# author-filtered answer and present in the repository's own open-PR list.
LAG_OPEN='[{"number":31,"title":"fresh work","headRefName":"chore/fresh","author":{"login":"me"}}]'
LAG_PR_31='{"number":31,"title":"fresh work","headRefName":"chore/fresh","headRefOid":"ff","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}'
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$LAG_OPEN" GH_STUB_OPEN_PRS_SEARCH='[]' GH_STUB_PR_31="$LAG_PR_31" \
  "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge: a PR missing from the search index is still eligible" "$out" "eligible #31 fresh work [chore/fresh]"
chk "merge: the open-PR list carries no --author filter" \
  "$(grep -q '^pr list .*--author' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "=== merge: a PR someone else authored is never listed ==="
FOREIGN_OPEN='[{"number":32,"title":"not mine","headRefName":"chore/theirs","author":{"login":"someone-else"}}]'
FOREIGN_PR_32='{"number":32,"title":"not mine","headRefName":"chore/theirs","headRefOid":"ff","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}],"isDraft":false}'
out="$(GH_STUB_OPEN_PRS="$FOREIGN_OPEN" GH_STUB_PR_32="$FOREIGN_PR_32" \
  "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_no "merge: a PR authored by someone else is not eligible" "$out" "eligible #32"
chk_has "merge: a foreign-only list reports no own PRs" "$out" "no open PRs authored by the operator"

echo "=== merge: a repo with no open PRs is not a failed query ==="
out="$(GH_STUB_OPEN_PRS='[]' "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge: an empty board exits 0" "$rc"
chk_has "merge: an empty board says so" "$out" "no open PRs authored by the operator"
chk_no "merge: an empty board is not reported as a failed query" "$out" "the open-PR query on"

echo "=== merge: a failed identity read is reported, never read as an empty board ==="
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$LAG_OPEN" GH_STUB_API_RC=1 GH_STUB_PR_31="$LAG_PR_31" \
  "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge: a failed identity read exits non-zero" "$([ "$rc" -ne 0 ]; echo $?)"
chk_has "merge: a failed identity read names the query" "$out" "the open-PR query on"
chk_no "merge: a failed identity read is not reported as no own PRs" "$out" "no open PRs authored by the operator"
chk "merge: a failed identity read calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

echo "=== merge: unparseable PR JSON skips instead of passing the gate ==="
out="$(gate_verdict 'not json at all')"
chk_has "merge: unreadable JSON skips" "$out" "SKIP #9: unreadable PR JSON"

echo "=== merge: a stacked parent with an open dependent skips, naming the retarget rule ==="
STACK_OPEN='[{"number":7,"title":"parent","headRefName":"feat/wrap"},{"number":8,"title":"child","headRefName":"feat/child"}]'
STACK_8='{"number":8,"title":"child","headRefName":"feat/child","baseRefName":"feat/wrap","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
STACK_7='{"number":7,"title":"parent","headRefName":"feat/wrap","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[]}'
out="$(GH_STUB_OPEN_PRS="$STACK_OPEN" GH_STUB_PR_7="$STACK_7" GH_STUB_PR_8="$STACK_8" "$WRAP" merge "$TMPD/clone-scan-main" 2>&1)"
chk_has "merge skips the stacked parent" "$out" "SKIP #7 parent: dependents open, retarget them first"
chk_has "merge skips the child whose base is not the default branch" "$out" "SKIP #8 child: base is feat/wrap, not the default branch main"

echo "=== merge: the post-merge state check fails closed ==="
: > "$GH_STUB_CALLS"
out="$(GH_STUB_VIEW_STATE='{"state":"OPEN","mergeCommit":null}' "$WRAP" merge --apply "$TMPD/clone-scan-main" 2>&1)"; rc=$?
chk "merge --apply exits 2 when the PR is not MERGED after the call" "$([ "$rc" -eq 2 ]; echo $?)"

# ===========================================================================
echo "=== merge: one bounded re-merge when GitHub conflicts on a union-marked log ==="
# ===========================================================================
# GitHub squash-merges without reading .gitattributes, so a log both sides appended to
# conflicts on the PR while `git merge` resolves it by union. Each case gets its own remote
# and its own PR number, because the stub counts detail reads per number.
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
conflict_json() { # conflict_json <number>
  printf '{"number":%s,"title":"log entry","headRefName":"feat/union","headRefOid":"%s","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2"
}
open_one() { printf '[{"number":%s,"title":"log entry","headRefName":"feat/union"}]' "$1"; }

# --- dry run: the retry is announced, never run
build_remerge dry
RM_DRY="$TMPD/rm-clone-dry"; RM_DRY_TIP="$(git -C "$RM_DRY" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 11)" GH_STUB_PR_11="$(conflict_json 11 "$RM_DRY_TIP")" \
  "$WRAP" merge "$RM_DRY" 2>&1)"
chk_has "re-merge dry run names the branch it would re-merge" "$out" \
  "note: #11 conflicts; --apply would try one re-merge of main into feat/union"
chk "re-merge dry run left the branch tip alone" \
  "$([ "$(git -C "$RM_DRY" rev-parse feat/union)" = "$RM_DRY_TIP" ]; echo $?)"
chk "re-merge dry run called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: the union log resolves, the push lands, the re-gate passes, one merge follows
# headRefOid is a %REMERGE_TIP% marker: the recovered commit's real SHA does not exist
# until wrap creates it mid-run, so the stub resolves the marker against the live branch
# tip, and its `pr merge` lands that same tip on main so tree-verify has a real match.
build_remerge ok
RM_OK="$TMPD/rm-clone-ok"; RM_OK_TIP="$(git -C "$RM_OK" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 12)" GH_STUB_PR_12="$(conflict_json 12 "$RM_OK_TIP")" \
  GH_STUB_PR_12_2='{"number":12,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RM_OK" GH_STUB_LAND_REMOTE="$TMPD/rm-bare-ok" GH_STUB_LAND_BRANCH="feat/union" GH_STUB_LAND_DEF="main" \
  "$WRAP" merge --apply "$RM_OK" 2>&1)"; rc=$?
RM_OK_RECOVERED="$(git -C "$RM_OK" rev-parse feat/union)"
chk "re-merge --apply exits 0" "$rc"
chk_has "re-merge --apply reports the push" "$out" "re-merged origin/main into feat/union, pushed"
chk_has "re-merge --apply re-gates the PR" "$out" "eligible #12 after the re-merge"
chk_has "re-merge --apply merges the recovered PR" "$out" "merged #12 (1a2b3c4d5e6f): tree verified"
chk "re-merge --apply called pr merge exactly once" \
  "$([ "$(grep -c '^pr merge' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk "re-merge --apply pinned the head the re-gate read, not the stale one" \
  "$(grep -q -- "--match-head-commit ${RM_OK_RECOVERED}" "$GH_STUB_CALLS"; echo $?)"
chk "re-merge --apply advanced the remote branch" \
  "$([ "$(git -C "$TMPD/rm-bare-ok" rev-parse feat/union)" != "$RM_OK_TIP" ]; echo $?)"
chk "re-merge --apply kept both log lines" \
  "$(grep -q 'branch line' "$RM_OK/_meta/LAB_LOG.md" && grep -q 'main line' "$RM_OK/_meta/LAB_LOG.md"; echo $?)"
chk_no "re-merge --apply reports no dedupe (LAB_LOG is not a kanban table)" "$out" "deduped union-merged rows"

# --- apply: a conflict outside the union-marked files aborts and changes nothing
build_remerge bad --also-conflict
RM_BAD="$TMPD/rm-clone-bad"; RM_BAD_TIP="$(git -C "$RM_BAD" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 13)" GH_STUB_PR_13="$(conflict_json 13 "$RM_BAD_TIP")" \
  "$WRAP" merge --apply "$RM_BAD" 2>&1)"; rc=$?
chk "re-merge with a real conflict exits 0 without merging" "$rc"
chk_has "re-merge with a real conflict says it aborted" "$out" \
  "conflicts beyond the union-marked files, aborted"
chk "re-merge with a real conflict left the branch tip alone" \
  "$([ "$(git -C "$RM_BAD" rev-parse feat/union)" = "$RM_BAD_TIP" ]; echo $?)"
chk "re-merge with a real conflict left no half-merged tree" \
  "$([ -z "$(git -C "$RM_BAD" status --porcelain)" ]; echo $?)"
chk "re-merge with a real conflict called no pr merge" \
  "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: a tip that is not the gated head is never pushed
build_remerge tip
RM_TIP="$TMPD/rm-clone-tip"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 14)" \
  GH_STUB_PR_14="$(conflict_json 14 3333333333333333333333333333333333333333)" \
  "$WRAP" merge --apply "$RM_TIP" 2>&1)"
chk_has "re-merge refuses a branch whose tip is not the PR head" "$out" "is not the PR head"
chk "re-merge tip mismatch called no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# --- apply: two conflicting PRs leave the branch ambiguous, so nothing is retried
build_remerge two
RM_TWO="$TMPD/rm-clone-two"; RM_TWO_TIP="$(git -C "$RM_TWO" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS='[{"number":15,"title":"log entry","headRefName":"feat/union"},{"number":16,"title":"other","headRefName":"feat/other"}]' \
  GH_STUB_PR_15="$(conflict_json 15 "$RM_TWO_TIP")" \
  GH_STUB_PR_16='{"number":16,"title":"other","headRefName":"feat/other","headRefOid":"bb","baseRefName":"main","mergeable":"CONFLICTING","mergeStateStatus":"DIRTY","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  "$WRAP" merge --apply "$RM_TWO" 2>&1)"
chk_no "two conflicting PRs retry neither" "$out" "one re-merge of main"
chk "two conflicting PRs left the branch tip alone" \
  "$([ "$(git -C "$RM_TWO" rev-parse feat/union)" = "$RM_TWO_TIP" ]; echo $?)"

# --- apply: the re-gate after the push is the authority, not the merge that succeeded
build_remerge gate
RM_GATE="$TMPD/rm-clone-gate"; RM_GATE_TIP="$(git -C "$RM_GATE" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 17)" GH_STUB_PR_17="$(conflict_json 17 "$RM_GATE_TIP")" \
  GH_STUB_PR_17_2='{"number":17,"title":"log entry","headRefName":"feat/union","headRefOid":"cc","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"CHANGES_REQUESTED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  "$WRAP" merge --apply "$RM_GATE" 2>&1)"
chk_has "a re-gate that refuses after the push names the reason" "$out" \
  "SKIP #17 after the re-merge: changes requested"
chk "a refused re-gate calls no pr merge" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 1 || echo 0)"

# ===========================================================================
echo "=== merge: the re-merge dedupes a union-merged kanban row before pushing ==="
# ===========================================================================
# Two adjacent kanban rows edited on each side sit inside ONE conflicting hunk on a short
# file (git's merge context, not the row content, is what overlaps), so the union driver
# resolves it by keeping ours-then-theirs whole and duplicates BOTH ids. This is the exact
# defect measured by hand 12 times on 2026-09-12; `_union_dedupe_rows` fixes it.
build_remerge_board() { # build_remerge_board <name>
  local name="$1" work="$TMPD/rb-work-$1" clone="$TMPD/rb-clone-$1"
  mkdir -p "$work/_meta"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  printf '_meta/BACKLOG.md merge=union\n' > "$work/.gitattributes"
  printf '## Active queue\n\n| ID | Title | Source | Status |\n|----|-------|--------|--------|\n| ID-401 | row a | src | queued |\n| ID-402 | row b | src | queued |\n' \
    > "$work/_meta/BACKLOG.md"
  git -C "$work" add -A; git -C "$work" commit -qm base
  git -C "$work" checkout -q -b feat/union
  sed -i.bak 's/ID-401 | row a | src | queued/ID-401 | row a | src | shipped/' "$work/_meta/BACKLOG.md"
  rm -f "$work/_meta/BACKLOG.md.bak"
  git -C "$work" commit -qam "branch flips 401"
  git -C "$work" checkout -q main
  sed -i.bak 's/ID-402 | row b | src | queued/ID-402 | row b | src | executing/' "$work/_meta/BACKLOG.md"
  rm -f "$work/_meta/BACKLOG.md.bak"
  git -C "$work" commit -qam "main flips 402"
  git clone -q --bare "$work" "$TMPD/rb-bare-$name"
  git clone -q "$TMPD/rb-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/union origin/feat/union
}

build_remerge_board board
RB="$TMPD/rb-clone-board"; RB_TIP="$(git -C "$RB" rev-parse feat/union)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_OPEN_PRS="$(open_one 20)" GH_STUB_PR_20="$(conflict_json 20 "$RB_TIP")" \
  GH_STUB_PR_20_2='{"number":20,"title":"log entry","headRefName":"feat/union","headRefOid":"%REMERGE_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' \
  GH_STUB_LAND_REPO="$RB" GH_STUB_LAND_REMOTE="$TMPD/rb-bare-board" GH_STUB_LAND_BRANCH="feat/union" GH_STUB_LAND_DEF="main" \
  "$WRAP" merge --apply "$RB" 2>&1)"; rc=$?
chk "board re-merge --apply exits 0" "$rc"
chk_has "board re-merge reports the dedupe" "$out" "deduped union-merged rows"
chk "board re-merge left exactly one ID-401 row" \
  "$([ "$(grep -c '^| ID-401 ' "$RB/_meta/BACKLOG.md")" -eq 1 ]; echo $?)"
chk "board re-merge left exactly one ID-402 row" \
  "$([ "$(grep -c '^| ID-402 ' "$RB/_meta/BACKLOG.md")" -eq 1 ]; echo $?)"
chk "board re-merge kept the flipped ID-401 status, dropped the queued copy" \
  "$(grep -q '^| ID-401 | row a | src | shipped |$' "$RB/_meta/BACKLOG.md"; echo $?)"
chk "board re-merge kept the flipped ID-402 status, dropped the queued copy" \
  "$(grep -q '^| ID-402 | row b | src | executing |$' "$RB/_meta/BACKLOG.md"; echo $?)"
# git's own process (not a builtin) can take a SIGPIPE from a `grep -q` that stops reading
# after its match, so the subjects are captured into a variable FIRST and grepped from there
# (a builtin write), never piped straight from a live `git log`.
board_subjects="$(git -C "$RB" log --format=%s -3)"
chk "the dedupe landed as its own commit, the merge commit stays untouched" \
  "$(printf '%s\n' "$board_subjects" | grep -qx 'fix(board): dedupe union-merged rows'; echo $?)"
chk "the re-merge still pushed and merged" "$(grep -q '^pr merge' "$GH_STUB_CALLS" && echo 0 || echo 1)"

# ===========================================================================
echo "=== merge: gh saying MERGED is not proof the default branch holds the PR head ==="
# ===========================================================================
# Real git repos throughout: what a tree actually holds after a squash is the whole
# subject, so nothing about the tree state is stubbed. `gh` stays stubbed (it always
# reports MERGED via GH_STUB_VIEW_STATE's default), which is the point: the mismatch
# and unverifiable cases below are exactly what gh's own word cannot catch.
tv_pr_json() { # tv_pr_json <number> <head branch> <head oid>
  printf '{"number":%s,"title":"tv case","headRefName":"%s","headRefOid":"%s","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"APPROVED","statusCheckRollup":[{"conclusion":"SUCCESS"}]}' "$1" "$2" "$3"
}
tv_open_one() { printf '[{"number":%s,"title":"tv case","headRefName":"%s"}]' "$1" "$2"; }
build_tv_repo() { # build_tv_repo <name> -- bare + clone, base.txt on main, feat/tv adds pr-file.txt
  local name="$1" work="$TMPD/tv-work-$1" clone="$TMPD/tv-clone-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/base.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/tv-bare-$name"
  git clone -q "$TMPD/tv-bare-$name" "$clone"; gitc "$clone"
  git -C "$clone" remote set-head origin main >/dev/null 2>&1
  git -C "$clone" checkout -q -b feat/tv main
  echo "pr change" > "$clone/pr-file.txt"
  git -C "$clone" add -A; git -C "$clone" commit -qm "pr change"
}

echo "--- a real mismatch: main never got the PR's content, exits 3, branch untouched"
build_tv_repo mismatch
TVM="$TMPD/tv-clone-mismatch"; TVM_OID="$(git -C "$TVM" rev-parse feat/tv)"
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 21 feat/tv)" GH_STUB_PR_21="$(tv_pr_json 21 feat/tv "$TVM_OID")" \
  "$WRAP" merge --apply "$TVM" 2>&1)"; rc=$?
chk "tree-verify: a real mismatch exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: mismatch names the count and that main lacks the head" "$out" \
  "TREE MISMATCH, 1 paths differ; main does not hold the PR head"
chk "tree-verify: mismatch leaves the branch in place" \
  "$(git -C "$TVM" rev-parse --verify feat/tv >/dev/null 2>&1; echo $?)"

echo "--- an unreachable head object: never a false pass, exits 3"
BOGUS_OID="0000000000000000000000000000000000000f"
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 22 feat/tv)" GH_STUB_PR_22="$(tv_pr_json 22 feat/tv "$BOGUS_OID")" \
  "$WRAP" merge --apply "$TVM" 2>&1)"; rc=$?
chk "tree-verify: an unreachable head object exits 3" "$([ "$rc" -eq 3 ]; echo $?)"
chk_has "tree-verify: names it unverifiable rather than passing silently" "$out" \
  "tree UNVERIFIABLE the PR head is not a local object"

echo "--- scoped match: another PR landed on main meanwhile, only the touched path must agree"
build_tv_repo scoped
TVS="$TMPD/tv-clone-scoped"; TVS_OID="$(git -C "$TVS" rev-parse feat/tv)"
git clone -q "$TMPD/tv-bare-scoped" "$TMPD/tv-land-scoped" >/dev/null 2>&1
gitc "$TMPD/tv-land-scoped"
echo "someone else's change" > "$TMPD/tv-land-scoped/other-file.txt"
git -C "$TMPD/tv-land-scoped" add -A; git -C "$TMPD/tv-land-scoped" commit -qm "other change"
cp "$TVS/pr-file.txt" "$TMPD/tv-land-scoped/pr-file.txt"
git -C "$TMPD/tv-land-scoped" add -A; git -C "$TMPD/tv-land-scoped" commit -qm "squash: pr change"
git -C "$TMPD/tv-land-scoped" push -q origin main
out="$(GH_STUB_OPEN_PRS="$(tv_open_one 23 feat/tv)" GH_STUB_PR_23="$(tv_pr_json 23 feat/tv "$TVS_OID")" \
  "$WRAP" merge --apply "$TVS" 2>&1)"; rc=$?
chk "tree-verify: a scoped match (another PR landed meanwhile) exits 0" "$rc"
chk_has "tree-verify: scoped match reports verified" "$out" "tree verified"

# ===========================================================================
echo "=== land: one hand-made worktree, from a committed branch to landed ==="
# ===========================================================================
# Real git throughout, `gh` stubbed: the push, the fast-forward, the worktree removal and
# the branch delete are the subject, so nothing about the tree state is faked.
build_land() { # build_land <name> [--modify-base]
  local name="$1" mode="${2:-}" work="$TMPD/ld-work-$1" repo="$TMPD/ld-repo-$1"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/base.txt"; git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/ld-bare-$name"
  git clone -q "$TMPD/ld-bare-$name" "$repo"; gitc "$repo"
  git -C "$repo" remote set-head origin main >/dev/null 2>&1
  git -C "$repo" worktree add -q -b feat/land "$repo/wt" main >/dev/null 2>&1
  if [ "$mode" = "--modify-base" ]; then
    echo "branch edit" > "$repo/wt/base.txt"
  else
    echo "pr change" > "$repo/wt/pr-file.txt"
  fi
  git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "feat: the landed change"
}
echo "--- happy path: pushed, PR opened with --head, merged alone, pulled, tidied"
build_land ok
LREPO="$TMPD/ld-repo-ok"; LREPO_P="$(cd "$LREPO" && pwd -P)"; LWT="$(cd "$LREPO/wt" && pwd -P)"
LTIP="$(git -C "$LWT" rev-parse HEAD)"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_CREATE_NUM=42 GH_STUB_LAND_REPO="$LWT" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-ok" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT" 2>&1)"; rc=$?
LAND_CALLS="$(cat "$GH_STUB_CALLS")"
chk "land exits 0 on the happy path" "$rc"
chk_has "land reports the push with the tip" "$out" "pushed feat/land (${LTIP:0:7})"
chk "land pushed the named branch to the remote" \
  "$([ "$(git -C "$TMPD/ld-bare-ok" rev-parse feat/land)" = "$LTIP" ]; echo $?)"
chk_has "land opened the PR with --head" "$LAND_CALLS" "pr create --repo"
chk_has "the create call names the branch as head" "$LAND_CALLS" "--head feat/land"
chk_no "the create call never names a base" "$LAND_CALLS" "--base"
chk_has "land reports the PR number" "$out" "opened PR #42"
chk "land ran the squash merge as its own call" \
  "$([ "$(grep -c '^pr merge 42 ' "$GH_STUB_CALLS")" -eq 1 ]; echo $?)"
chk_has "the merge call is a squash" "$LAND_CALLS" "pr merge 42 --repo"
chk_has "the merge call pins the pushed head" "$LAND_CALLS" "--squash --match-head-commit ${LTIP}"
chk_has "land verifies the default branch holds the PR head" "$out" "merged #42 (1a2b3c4d5e6f): tree verified"
chk "land fast-forwarded the main checkout onto the landed tree" \
  "$([ "$(git -C "$LREPO" rev-parse HEAD)" = "$LTIP" ]; echo $?)"
chk_has "land reports the pull" "$out" "pulled ${LREPO_P}"
chk "land removed the worktree" "$([ ! -e "$LWT" ]; echo $?)"
chk "land dropped the worktree from the list" \
  "$(git -C "$LREPO" worktree list --porcelain | grep -qxF "worktree $LWT" && echo 1 || echo 0)"
chk "land deleted the local branch" \
  "$(git -C "$LREPO" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk_has "land reports the delete" "$out" "deleted feat/land"

echo "--- a dirty worktree refuses before any write"
build_land dirty
LWT_D="$(cd "$TMPD/ld-repo-dirty/wt" && pwd -P)"
echo dirt > "$LWT_D/dirt.txt"
: > "$GH_STUB_CALLS"
out="$("$WRAP" land "$LWT_D" 2>&1)"; rc=$?
chk "land refuses a dirty worktree with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the dirt" "$out" "is dirty, so the branch is not what a PR would carry"
chk "a dirty refusal called no gh" "$([ ! -s "$GH_STUB_CALLS" ]; echo $?)"
chk "a dirty refusal pushed nothing" \
  "$(git -C "$TMPD/ld-bare-dirty" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"
chk "a dirty refusal left the worktree in place" "$([ -e "$LWT_D" ]; echo $?)"

echo "--- HEAD on the default branch refuses"
build_land ondef
git -C "$TMPD/ld-repo-ondef" checkout -q -b side
git -C "$TMPD/ld-repo-ondef" worktree add -q "$TMPD/ld-repo-ondef/wt-def" main >/dev/null 2>&1
LWT_M="$(cd "$TMPD/ld-repo-ondef/wt-def" && pwd -P)"
: > "$GH_STUB_CALLS"
out="$("$WRAP" land "$LWT_M" 2>&1)"; rc=$?
chk "land refuses a worktree on the default branch with exit 1" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the refusal names the branch" "$out" "HEAD is main, the default or a protected branch name"
chk "a default-branch refusal called no gh" "$([ ! -s "$GH_STUB_CALLS" ]; echo $?)"
chk "a default-branch refusal left the worktree in place" "$([ -e "$LWT_M" ]; echo $?)"

echo "--- PULL BLOCKED: a dirty tracked file in the main checkout never stops the tidy"
build_land blocked --modify-base
LREPO_B="$TMPD/ld-repo-blocked"; LREPO_BP="$(cd "$LREPO_B" && pwd -P)"; LWT_B="$(cd "$LREPO_B/wt" && pwd -P)"
LTIP_B="$(git -C "$LWT_B" rev-parse HEAD)"
LHEAD_B="$(git -C "$LREPO_B" rev-parse HEAD)"
echo "a sibling session's line" >> "$LREPO_B/base.txt"
: > "$GH_STUB_CALLS"
out="$(GH_STUB_CREATE_NUM=43 GH_STUB_LAND_REPO="$LWT_B" GH_STUB_LAND_REMOTE="$TMPD/ld-bare-blocked" \
  GH_STUB_LAND_BRANCH=feat/land GH_STUB_LAND_DEF=main "$WRAP" land "$LWT_B" 2>&1)"; rc=$?
chk "a blocked pull exits 2" "$([ "$rc" -eq 2 ]; echo $?)"
chk_has "the blocked pull says PULL BLOCKED" "$out" "PULL BLOCKED: pull --ff-only refused in ${LREPO_BP}"
chk_has "the blocked pull says nothing was stashed or reset" "$out" "nothing was stashed or reset"
chk "the blocked pull left the main checkout where it was" \
  "$([ "$(git -C "$LREPO_B" rev-parse HEAD)" = "$LHEAD_B" ]; echo $?)"
chk "the blocked pull left the sibling's dirty file alone" \
  "$(grep -qx "a sibling session's line" "$LREPO_B/base.txt"; echo $?)"
chk "the merge still landed" \
  "$([ "$(git -C "$TMPD/ld-bare-blocked" rev-parse main)" = "$LTIP_B" ]; echo $?)"
chk "the worktree was still removed" "$([ ! -e "$LWT_B" ]; echo $?)"
chk_has "the removal is still reported" "$out" "removed worktree ${LWT_B}"
chk "the branch was still deleted" \
  "$(git -C "$LREPO_B" rev-parse --verify feat/land >/dev/null 2>&1 && echo 1 || echo 0)"

echo "--- the usage text and the command doc name the verb"
chk_has "wrap --help names land" "$("$WRAP" --help 2>&1)" "wrap.sh land  <worktree>"
chk_has "commands/wrap.md names land for a hand-made worktree" "$(cat "$KIT_DIR/commands/wrap.md")" \
  "bin/wrap land <worktree>"

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
echo "=== log/stage: the default-branch warning, written but not to be committed here ==="
# ===========================================================================
# A commit on the default branch cannot be pushed through a PR, so the verb writes the file
# and says the line belongs to the next feature PR. The write itself is never refused.
DBREPO="$LOGHOME/dbrepo"
git init -q "$DBREPO"
git -C "$DBREPO" symbolic-ref HEAD refs/heads/main
git -C "$DBREPO" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
mkdir -p "$DBREPO/_meta" && printf 'seed\n' > "$DBREPO/_meta/LOG.md"
git -C "$DBREPO" add _meta/LOG.md && git -C "$DBREPO" -c user.name=t -c user.email=t@t commit -q -m log
set_log_key "$DBREPO/_meta/LOG.md"

out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on main" 2>&1)"
chk_has "log on the default branch warns" "$out" "on the default branch (main)"
chk_has "log names the next feature PR as the carrier" "$out" "next feature PR"
chk "log on the default branch still wrote the line" \
  "$([ "$(head -1 "$DBREPO/_meta/LOG.md")" = "$(date +%F) · wrap: on main" ]; echo $?)"

git -C "$DBREPO" checkout -q -b feat/log-guard
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on a branch" 2>&1)"
chk_no "log on a feature branch does not warn" "$out" "default branch"
chk "log on a feature branch still wrote the line" \
  "$([ "$(head -1 "$DBREPO/_meta/LOG.md")" = "$(date +%F) · wrap: on a branch" ]; echo $?)"

# origin/HEAD, not the local branch name, decides which branch is the default one: a repo whose
# remote default is `master` gets no warning for a session sitting on a local `main`.
git init -q --bare "$LOGHOME/dbremote.git"
git -C "$DBREPO" remote add origin "$LOGHOME/dbremote.git"
git -C "$DBREPO" push -q origin "HEAD:refs/heads/master"
git -C "$DBREPO" fetch -q origin
git -C "$DBREPO" checkout -q main
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: local main, remote master" 2>&1)"
chk_no "log: a local main is not the default when origin says master" "$out" "default branch"
git -C "$DBREPO" checkout -q -B master
out="$(cd "$DBREPO" && HOME="$LOGHOME" KIT_CONFIG_ROOT="$KITROOT" "$WRAP" log "wrap: on remote master" 2>&1)"
chk_has "log: the remote's own default branch warns" "$out" "on the default branch (master)"

STAGEDB="$TMPD/stage-defaultbranch"
git init -q "$STAGEDB"
git -C "$STAGEDB" symbolic-ref HEAD refs/heads/main
git -C "$STAGEDB" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
out="$(cd "$STAGEDB" && "$WRAP" stage "Guarded Title" "the intent" "the home" 2>&1)"
chk_has "stage on the default branch warns" "$out" "on the default branch (main)"
chk "stage on the default branch still wrote the block" \
  "$(grep -q '## \[staged\] Guarded Title' "$STAGEDB/_meta/backlog-staging.md"; echo $?)"
git -C "$STAGEDB" checkout -q -b feat/stage-guard
out="$(cd "$STAGEDB" && "$WRAP" stage "Branch Title" "i" "h" 2>&1)"
chk_no "stage on a feature branch does not warn" "$out" "default branch"

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
for knob in merge_own_prs tidy_worktrees build_candidates pull_past_dirty distill; do
  chk_has "commands/wrap.md reads wrap.$knob" "$(cat "$KIT_DIR/commands/wrap.md")" "wrap.$knob"
  chk_has "kit.toml declares $knob" "$(cat "$KIT_DIR/kit.toml")" "$knob"
done
# distill is the switch for the whole distill half (the pre-0 scan, the seams, step 7). It ships
# OFF: "wrap up" lands the session, and the distill half runs on `/kit:wrap distill` or the knob.
# It authorizes writes to home repos, so the project fence holds like every other [wrap] knob.
DS_ON="$TMPD/distill-operator"; DS_PROJ="$TMPD/distill-project"
mkdir -p "$DS_ON" "$DS_PROJ"
printf '[wrap]\ndistill = true\n' > "$DS_ON/kit.toml"
printf '[wrap]\ndistill = true\n' > "$DS_PROJ/.kit.toml"
v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root wrap.distill true)"
chk "wrap.distill ships as false" "$([ "$v" = "false" ]; echo $?)"
v="$(KIT_CONFIG_OPERATOR="$DS_ON" kit_config_get_root wrap.distill false)"
chk "wrap.distill honours the operator kit.toml" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_PROJECT_ROOT="$DS_PROJ" kit_config_get_root wrap.distill false)"
chk "wrap.distill ignores a project .kit.toml" "$([ "$v" = "false" ]; echo $?)"
chk_has "commands/wrap.md takes the distill argument" "$(cat "$KIT_DIR/commands/wrap.md")" "/kit:wrap distill"
# pull_past_dirty is the one knob whose shipped default does NOT act: it authorizes a write to
# a dirty file in a checkout other sessions share, so it opts in, and the project fence holds.
v="$(KIT_CONFIG_ROOT="$KIT_DIR" kit_config_get_root wrap.pull_past_dirty true)"
chk "wrap.pull_past_dirty ships as false" "$([ "$v" = "false" ]; echo $?)"
v="$(KIT_CONFIG_OPERATOR="$PD_ON" kit_config_get_root wrap.pull_past_dirty false)"
chk "wrap.pull_past_dirty honours the operator kit.toml" "$([ "$v" = "true" ]; echo $?)"
v="$(KIT_PROJECT_ROOT="$PD_PROJ" kit_config_get_root wrap.pull_past_dirty false)"
chk "wrap.pull_past_dirty ignores a project .kit.toml" "$([ "$v" = "false" ]; echo $?)"

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

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line naming the home and insertion point passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (reported: needs a spec)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying the precedent miss passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: build_candidates knob is false|' | bash "$LINT" 2>&1)"; rc=$?
chk "a real SKIPPED reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The distill switch off is the shipped default, so its report shape is the common one: both
# lines SKIPPED with the switch as the reason, and the lint must take it as a real skip.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** SKIPPED: distill off|; s|^\*\*Seam:\*\* .*|**Seam:** SKIPPED: distill off|' | bash "$LINT" 2>&1)"; rc=$?
chk "Built and Seam both SKIPPED: distill off passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The lane suffix. commands/wrap.md step 7b routes every candidate through
# lib/classify/lane-classify.sh: a tiny-lane candidate is built here and carries the check
# that proved it, anything heavier is reported with a one-line why. Both shapes append to the
# same line, so the ENHANCE/NEW token must survive the suffix, and the suffix alone must never
# stand in for the token.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=tiny and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, reported: owes a review, too big for session close)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=normal and its reported why passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, reported: build_candidates off)|' | bash "$LINT" 2>&1)"; rc=$?
chk "the knob-false shape, reported with the knob as the why, passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** lib/wrap/report-lint.sh (lane=tiny, verified: bash tests/test-wrap.sh, abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane suffix with no ENHANCE or NEW still fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still asks for the ENHANCE or NEW token" "$out" "no ENHANCE <home> or NEW (precedent: ...) token"

# The verdict. Every candidate opens with BUILT, REPORTED, or NOTE; a line without one
# reads as built when it may only have been reported or noted.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=tiny, verified: bash tests/test-alert.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a candidate with no leading verdict fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the three verdicts" "$out" "BUILT, REPORTED, or NOTE"

# STAGED and FILED are retired: step 7b never writes a staging block or mints a board row.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** STAGED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged + goal drafted: .claude/goals/cron-fire.md)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a STAGED verdict fails, staging is retired" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the retired verdict" "$out" "uses a retired verdict"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** FILED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, filed: ops-toolkit ID-901, goal drafted: .claude/goals/cron-fire.md)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a FILED verdict fails, wrap never mints a board row" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the FILED finding names the retired verdict" "$out" "uses a retired verdict"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** NOTE remerge ENHANCE dwarves-kit bin/wrap merge: PROSE-ONLY: the verb already re-merges under the union driver, nothing was missing, memory note written|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NOTE verdict on a prose-only candidate passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The lane closure rule. `wrap.build_lanes` lets an operator list heavier lanes for step 7b to
# build inline, so `lane=normal`, `lane=bug` and `lane=backfill` are legal on a verified item
# and the lint can no longer treat `tiny` as the only buildable lane. What it does enforce is
# the pairing: a lane token says the candidate was sized and nothing about what became of it,
# so every item naming a lane owes `verified:` or `reported:`. The retired closures
# (`staged`, `filed:`, `capture failed:`) no longer close a lane.
out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: tests/live/wake-probe after the touch probe (lane=normal, verified: bash tests/test-alert.sh, #418)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE line carrying lane=normal and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=bug, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=bug and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=backfill, verified: bash tests/test-cron.sh, b2c3d4e)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW line carrying lane=backfill and its check passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, reported: owes a spec and a review)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a full lane reported with its why passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, filed: ops-toolkit ID-901)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a retired filed: closure no longer closes a lane" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the retired closure reads as no closure" "$out" "names a lane with no closure"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, staged: build_candidates off)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a retired staged closure no longer closes a lane" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=full, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a full lane closed as built fails, full is never built at session close" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the full-lane rule" "$out" "closes a full-lane candidate as built"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=tiny, reported: nope)|' | bash "$LINT" 2>&1)"; rc=$?
chk "BUILT closed as reported fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the verdict and closure mismatch" "$out" "pairs its verdict with the wrong closure"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, verified: bash tests/test-cron.sh, a1b2c3d)|' | bash "$LINT" 2>&1)"; rc=$?
chk "REPORTED closed as verified fails" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal, unreported: x)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an unanchored closure token (unreported:) does not close a lane" "$([ "$rc" -eq 1 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** REPORTED cron-fire NEW (precedent: nothing matched): tools/cron-fire (lane=normal)|' | bash "$LINT" 2>&1)"; rc=$?
chk "a lane with neither a check nor a reported why fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the missing closure" "$out" "names a lane with no closure"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT alpha ENHANCE tools/x: file.sh (lane=normal, verified: bash tests/test-x.sh, #12)\n- REPORTED beta NEW (precedent: nothing matched): tools/beta (lane=bug)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "one unclosed lane among good bullets fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "item 2"

chk_has "commands/wrap.md classifies each candidate's lane" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/classify/lane-classify.sh classify"
chk_has "commands/wrap.md names the worker model tiers" "$(cat "$KIT_DIR/commands/wrap.md")" "Sonnet is the default worker"
chk_has "commands/wrap.md reads the build_lanes knob" "$(cat "$KIT_DIR/commands/wrap.md")" "kit_config_get_root wrap.build_lanes"
chk_has "kit.toml ships build_lanes defaulting to tiny" "$(cat "$KIT_DIR/kit.toml")" 'build_lanes = "tiny"'
chk_no "commands/wrap.md no longer files a candidate with board capture" "$(cat "$KIT_DIR/commands/wrap.md")" "bin/board capture"
chk_no "commands/wrap.md no longer stages a candidate" "$(cat "$KIT_DIR/commands/wrap.md")" "bin/wrap stage \"<title>\""
chk_no "commands/wrap.md dropped the staged-exclusion form" "$(cat "$KIT_DIR/commands/wrap.md")" "build_lanes excludes"
chk_no "kit.toml dropped the staged-exclusion form" "$(cat "$KIT_DIR/kit.toml")" "build_lanes excludes"
# The LIST form: a bare `**Built:**` header followed by `- ` bullets, one candidate per
# line. Added after a real report crammed three candidates onto one unreadable line. Each
# bullet owes the same ENHANCE/NEW token as the inline form, checked per bullet, so one bare
# item among several good ones cannot hide the way it did when the whole line was one string.
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- REPORTED untracked-blocks-ff-pull NEW (precedent: nothing matched): dwarvesf/dwarves-kit lib/wrap, the pull path in wrap apply (reported: needs a spec)\n- BUILT mini-script-run-loop ENHANCE ops-toolkit tools/mac-mini-substrate/mini-run (no change needed, precedent hit is the helper itself)\n- BUILT sandbox-overlap-probe ENHANCE dwarvesf/foundation-ops fleet/knowledge-guard (already homed as OPS-16)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a three-bullet Built list passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT alpha ENHANCE tools/x: file.sh (abc1234)\n- lib/wrap/report-lint.sh @ def5678\n- REPORTED gamma NEW (precedent: nothing matched): tools/gamma (reported: needs a spec)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a list with one bare path-and-commit bullet fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the offending bullet by index" "$out" "bullet 2"
chk_has "the finding quotes the bare bullet" "$out" "lib/wrap/report-lint.sh @ def5678"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a bare Built header with no bullets and no inline content fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding says it is empty" "$out" "is empty"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:** NOTHING: no candidates\n- BUILT stray ENHANCE tools/x: file.sh (abc1234)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
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
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- BUILT pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "an all-prose Built list fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the prose rule" "$out" "a precedent hit on a note is not a build"
chk_has "the finding says the code home wins" "$out" "the code home wins"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- BUILT pull-context ENHANCE ops-toolkit research/2026-09-10-ff-pull.md (def5678)\n- PROSE-ONLY: the call is one human judgment per run, no mechanism fits it\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "the same all-prose Built passes with a real PROSE-ONLY reason" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)\n- PROSE-ONLY: none\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a too-short PROSE-ONLY reason cannot silence the rule" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding still names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- BUILT pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)\n- BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (def5678)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' | bash "$LINT" 2>&1)"; rc=$?
chk "a mixed Built passes, because something was built" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a single memory note fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the inline finding names the prose rule" "$out" "a precedent hit on a note is not a build"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-lesson ENHANCE ops-toolkit .claude/memory/ff-pull-trap.md (abc1234) PROSE-ONLY: the pull path already guards itself, only the trap was new|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline PROSE-ONLY token with a real reason passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | sed 's|^\*\*Built:\*\* .*|**Built:** BUILT pull-guard ENHANCE dwarvesf/dwarves-kit lib/wrap/wrap.sh (abc1234)|' | bash "$LINT" 2>&1)"; rc=$?
chk "an inline Built naming a code path still passes" "$([ "$rc" -eq 0 ]; echo $?)"

# The harness-shape check: a `NEW (precedent: nothing matched)` candidate that turns out to
# speak CDP already has a home (browser-harness-js learnings), so it warns instead of passing
# clean, but it never fails the lint (the precedent check itself was still honest).
HARNESS_FIX="$TMPD/harness-fixture"; mkdir -p "$HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$HARNESS_FIX/probe.js"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** REPORTED site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (reported: needs a spec)|" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW item whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home" "$out" "browser-harness-js skills/cdp/learnings"

out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** BUILT wake-probe ENHANCE tools/alert-triage: ${HARNESS_FIX} (a1b2c3d)|" | bash "$LINT" 2>&1)"; rc=$?
chk "an ENHANCE item is never checked for harness shape, even over the same CDP content" "$([ "$rc" -eq 0 ]; echo $?)"
chk_no "no harness warn on an ENHANCE line" "$out" "browser-harness-js skills/cdp/learnings"

# The harness-shape check on a LIST-form bullet: the same token match, on a `- ` line.
LIST_HARNESS_FIX="$TMPD/harness-fixture-list"; mkdir -p "$LIST_HARNESS_FIX"
printf "await session.Runtime.evaluate({ expression: '1+1' });\n" > "$LIST_HARNESS_FIX/probe.js"
out="$(printf '✅ **Needs you:** NOTHING\n\n**Built:**\n- REPORTED site-probe NEW (precedent: nothing matched): %s (reported: needs a spec)\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' "$LIST_HARNESS_FIX" | bash "$LINT" 2>&1)"; rc=$?
chk "a NEW bullet whose files call the CDP harness warns, not fails" "$([ "$rc" -eq 0 ]; echo $?)"
chk_has "the warn names the harness home for a bullet item" "$out" "browser-harness-js skills/cdp/learnings"

printf 'echo "plain shell content, no CDP calls here"\n' > "$HARNESS_FIX/probe.js"
out="$(_report '✅ **Needs you:** NOTHING' | sed "s|^\*\*Built:\*\* .*|**Built:** REPORTED site-probe NEW (precedent: nothing matched): ${HARNESS_FIX} (reported: needs a spec)|" | bash "$LINT" 2>&1)"; rc=$?
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

# The FYI rule. The block used to mix a skipped step, a state, an incident, and an ask under
# one header, so an operator told to "follow the FYI" read nine ambiguous lines. Each bullet
# now opens with SKIPPED, STATE, or INCIDENT, and an ask belongs in `Needs you` instead.
_fyi() { printf '✅ **Needs you:** NOTHING\n\n**FYI:**\n%s\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n\n**What happened**\n- body\n' "$1"; }

out="$(_fyi '- SKIPPED step 7b, its scan output went to the scratch file
- STATE wrap.pull_past_dirty is false, the ops-toolkit checkout stayed behind
- INCIDENT the first merge raced CI, the retry landed it' | bash "$LINT" 2>&1)"; rc=$?
chk "an FYI block whose bullets are all tagged passes" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_fyi '- the ops-toolkit checkout stayed behind' | bash "$LINT" 2>&1)"; rc=$?
chk "an untagged FYI bullet fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding names the three tags" "$out" "SKIPPED (a step that did not run), STATE"

out="$(_fyi '- STATE wrap.pull_past_dirty is false, turning the knob on now works cleanly' | bash "$LINT" 2>&1)"; rc=$?
chk "a tagged FYI bullet carrying an ask fails" "$([ "$rc" -eq 1 ]; echo $?)"
chk_has "the finding sends the ask to Needs you" "$out" "that is an ask; move it to Needs you as DECIDE or RUN"

out="$(_fyi '- NOTHING' | bash "$LINT" 2>&1)"; rc=$?
chk "the NOTHING sentinel needs no tag" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(_report '✅ **Needs you:** NOTHING' | bash "$LINT" 2>&1)"; rc=$?
chk "a report with no FYI block still passes, the block is optional" "$([ "$rc" -eq 0 ]; echo $?)"

out="$(printf '✅ **Needs you:** NOTHING\n\n**FYI:**\n\n**Built:** NOTHING: no candidates\n\n**Seam:** NOTHING: no seam configured\n' | bash "$LINT" 2>&1)"; rc=$?
chk "an FYI header with no bullets is not a finding" "$([ "$rc" -eq 0 ]; echo $?)"

chk_has "commands/wrap.md names the three FYI tags" "$(cat "$KIT_DIR/commands/wrap.md")" "OPENS WITH ITS TAG"
chk_has "commands/wrap.md says FYI carries no ask" "$(cat "$KIT_DIR/commands/wrap.md")" '**`FYI` carries no ask.**'

chk_has "commands/wrap.md wires the lint into step 9" "$(cat "$KIT_DIR/commands/wrap.md")" "lib/wrap/report-lint.sh"
chk_has "the FYI contract keeps follow-ups in the report, no row minted for a home" "$(cat "$KIT_DIR/commands/wrap.md")" "it never mints a board row or a staging block"
chk_no "FYI is not described as never a task" "$(cat "$KIT_DIR/commands/wrap.md")" "never a task"

echo
if [ "$FAIL" -gt 0 ]; then echo "test-wrap: $PASS passed, $FAIL FAILED of $TOTAL" >&2; exit 1; fi
echo "test-wrap: all $PASS passed"
