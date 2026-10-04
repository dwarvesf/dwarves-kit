#!/usr/bin/env bash
# wrap.sh -- the landing step after ship. One pass over every repo a session
# touched, with twelve verbs:
#
#   wrap.sh scan  [--under <root>]... <repo> [<repo>...]    report only, exit 0
#   wrap.sh apply [--apply] [--worktrees] [--archive-unmerged] [--pull-only|--no-pull] [--own <path>]... [--under <root>]... <repo> [...]  dry-run by default
#   wrap.sh apply --pull-only [--apply] <repo> [...]        fetch + pull stage alone, no worktree/branch/stray write
#   wrap.sh apply --no-pull [--apply] [--own <path>]... <repo> [...]  tidy without the pull or the stray-commits move (a step 0 stop)
#   wrap.sh merge [--apply] [--no-pull] [--pr N] [--with-ci] [--verify C] <repo>   merges ONE own green PR (--pr: a named draft)
#   wrap.sh land  <worktree> [--title T] [--body-file F] [--with-ci] [--verify C]   one hand-made worktree, landed
#   wrap.sh start <repo> <branch> [--carry [<path>...]]     one hand-made worktree, started
#   wrap.sh log   "<slug>: <one sentence>" [--date YYYY-MM-DD]
#   wrap.sh default-branch <repo>                           prints the detected name
#   wrap.sh knowledge-root <repo>                           the fenced knowledge dir
#   wrap.sh follow-mode [lanes|all]                         step 10's mode and lanes, report only
#   wrap.sh deploy-wait <owner>/<name> <sha> [--check S]... [--timeout N]  step 4's push-deploy wait
#   wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]  stage a candidate
#   wrap.sh rebase <worktree>                               onto origin/<default>, safe conflicts only
#   wrap.sh --help
#
#   --under <root> (scan and apply, repeatable) appends every immediate child of <root> that
#   holds a .git file or directory, in sorted order, to the repo list. Other children are
#   skipped; a root with no repos prints one line. A bare --under (no directory follows it)
#   expands to every root in the wrap.roots knob instead (tilde-expanded, listed order, each
#   through the same immediate-child scan); an empty knob exits 64 naming it.
#
#   apply --archive-unmerged (opt-in, never under --own) pushes every local branch that is
#   not current/default/worktree-held and carries at least one commit patch origin/<default>
#   lacks (git cherry origin/<default> <branch> shows a `+`) to origin archive/<slug>-<date>,
#   then deletes the local branch once that push lands. No force; an existing archive ref
#   refuses the push. A branch with no unique patch is left for the merged-branch sweep above.
#
#   internal, a test seam: apply --tips-file <path> replaces the run's own tip snapshot
#   internal, a test seam: WRAP_ORIGIN_DELETE_CHUNK sets the names per origin delete push
#
#   start's --carry (repeatable path, or bare for everything) moves the main checkout's
#   uncommitted changes, tracked and untracked, into the worktree `start` just created, via a
#   named `git stash push -u`, applied by identity, never by index. Nothing dirty in scope is
#   not a refusal; an index.lock held by another writer is, and leaves the worktree in place.
#
# Verify a change in the shape commands/wrap.md runs it: step 5 passes `--own` on a shared
# repo, so a test or real-repo run of the bare form alone misses that path. The first origin
# sweep shipped skipping `--own` and every shared repo kept its merged heads.
#
# The write set is closed: branch delete under three proofs, `apply`'s origin delete of
# merged branches, each leased to the tip it read (knob wrap.delete_merged_remote_branches),
# worktree remove under
# --worktrees, pull --ff-only on the default branch and its pull-past-dirty stash, the
# activity-log prepend, the knowledge-root project directory, the staging-file append, one
# gh pr merge, one bounded re-merge cycle for a conflicting own PR (a `merge --no-ff
# --no-commit` of origin/<default>, the `chore(merge)` merge commit it lands, one follow-up
# dedupe commit when the merge duplicates a kanban row, one fast-forward push of the
# branch, and on the way out the restore of whatever the merge changed or one
# `reset --keep` of this run's own unpushed commits; a scratch detached worktree is added
# and removed when no checkout holds the branch), one `gh pr ready` when `merge --pr N` targets a draft,
# `merge`'s squash-equivalent fallback for a conflicting own PR whose head already holds
# the base (one commit-tree, one <branch>-squash push with a single scratch-ref delete and
# repush, one replacement `gh pr create`), `land`'s own named push, PR create, squash
# merge, worktree remove and branch delete, `apply`'s stray-line carry (per dirty
# union-marked file, one scratch detached worktree at origin/<default>, one commit, one push
# of a new wrap/stray-* branch, knob wrap.carry_stray_lines), `apply`'s stray-commit carry
# (the main checkout on the default branch and ahead of origin: one local and pushed
# wrap/stray-commits-* branch at HEAD, then one `reset --keep origin/<default>` when only
# merge=union files are dirty and origin holds HEAD, same knob), and under knob
# wrap.autoland_carry (default false) one `gh pr create --head` per carry branch with no open
# PR plus one `merge --apply --pr` of it, with every write that verb owns,
# `apply --archive-unmerged`'s one push per qualifying branch to a new origin
# archive/<slug>-<date> ref, never forced, followed by one local `branch -D` only once that
# push lands,
# `start`'s one worktree add under `.claude/worktrees` on a new local branch, and `start
# --carry`'s one named `git stash push -u` in the main checkout, one `stash apply` in the
# new worktree, and, on a clean apply, one `stash drop` of that same named entry.
# `rebase` rewrites its worktree's own local branch (one `git rebase origin/<default>`,
# `--continue` per resolved stop, `--abort` on any refusal) and, once no rebase is stopped,
# at most one regenerate commit there; it never pushes.
# Every other action is a report line. The
# verbs never switch a branch and never force a push or a pull. The one force is
# `worktree remove -f -f`: it overrides a LOCK, never a dirty, detached, checked-out or
# unproven worktree, and the removal counts only once a postcondition finds the path gone.
#
# Ported from the operator's repo-wrapup scripts. The default branch is DETECTED, never
# assumed to be main.
# `-e` is deliberately absent. The `run()` helper captures the exit code of every write
# itself, reports the failure once and sets FAILURES; under `-e` the shell would exit at
# the first failed write and the remaining repos would never report.
set -uo pipefail

# A git call must never block on a credential prompt inside an unattended wrap.
export GIT_TERMINAL_PROMPT=0

# A caller such as a git hook exports its own repo's GIT_DIR, GIT_COMMON_DIR or index.
# Inherited, they point every `git -C <repo>` below at that other repo, so wrap drops the
# repo-location variables once here: git's own list of the ones it clears before entering
# another repo, plus GIT_NAMESPACE, or a fixed copy of that list when git cannot print it.
# Config injection (GIT_CONFIG*) stays: callers such as mini-run pass credential and
# insteadOf settings that way on purpose, and without them every fetch fails.
_loc_vars="$(git rev-parse --local-env-vars 2>/dev/null)"
[ -n "$_loc_vars" ] || _loc_vars="GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_COMMON_DIR
GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_GRAFT_FILE
GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE"
for _v in $_loc_vars GIT_NAMESPACE; do
  case "$_v" in GIT_CONFIG*) ;; *) unset "$_v" ;; esac
done
unset _v _loc_vars

# An index.lock at least this old belongs to a foreign writer, not to ordinary git traffic.
LOCK_STALE_SECS=5
# A routine activity line stays inside this many characters. Over it, `log` warns and writes.
LOG_LINE_BUDGET=300

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"
# The one staging-block writer: `stage` shells out to it rather
# than growing a second copy of the dedupe/render/append grammar in bash.
STAGING_FORMAT_PY="$LIB_ROOT/reflect/staging-format.py"
BACKLOG_SH="$LIB_ROOT/board/backlog.sh"
# `land`'s ship-gate record shells out to this rather than reimplementing the
# rid/ledger rules -- see cmd_land's use below.
GATE_LEDGER_SH="$LIB_ROOT/gate/gate-ledger.sh"
# `land` reads the branch's proof of done through the gate's own verbs (proof-files,
# captured-output, images), so the lookup the ship-gate judges is the one the PR shows.
PROOF_LEDGER_SH="$LIB_ROOT/gate/proof-ledger.sh"
# shellcheck source=lib/config/kit-config.sh
source "$LIB_ROOT/config/kit-config.sh" || { echo "FATAL: lib/config/kit-config.sh missing or unreadable" >&2; exit 1; }
# shellcheck source=lib/gate/default-branch-warn.sh
source "$LIB_ROOT/gate/default-branch-warn.sh" || { echo "FATAL: lib/gate/default-branch-warn.sh missing or unreadable" >&2; exit 1; }
for _m in common scan apply pull carry ci merge land start log deploy rebase; do source "$SELF_DIR/wrap-$_m.sh" || { echo "FATAL: lib/wrap/wrap-$_m.sh missing or unreadable" >&2; exit 1; }; done; unset _m

_usage() { sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --------------------------------------------------------------------------- entry

main() {
  local verb="${1:-}"
  [ $# -gt 0 ] && shift
  case "$verb" in
    scan)           cmd_scan "$@" ;;
    apply)          cmd_apply "$@" ;;
    merge)          cmd_merge "$@" ;;
    land)           cmd_land "$@" ;;
    start)          cmd_start "$@" ;;
    log)            cmd_log "$@" ;;
    default-branch) cmd_default_branch "$@" ;;
    knowledge-root) cmd_knowledge_root "$@" ;;
    follow-mode)    cmd_follow_mode "$@" ;;
    deploy-wait)    cmd_deploy_wait "$@" ;;
    stage)          cmd_stage "$@" ;;
    rebase)         cmd_rebase "$@" ;;
    -h|--help|help|"") _usage; return 0 ;;
    *) echo "wrap: unknown verb '$verb' (try: wrap --help)" >&2; return 64 ;;
  esac
}

main "$@"
