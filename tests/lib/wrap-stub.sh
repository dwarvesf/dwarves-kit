#!/usr/bin/env bash
# wrap-stub.sh -- shared harness for the tests/test-wrap-*.sh suites: set flags, $WRAP,
# chk/chk_has/chk_no, TMPD and its cleanup trap, the config/ledger pins, the gh stub on
# PATH, gitc/build_remote/make_clone/set_stub, the three bare remotes, and the fixture
# builders more than one suite uses. Sourced, never executed: a suite sets KIT_DIR,
# then sources this file.
# modules under test (the test-affected cache key greps this line):
# lib/wrap/wrap.sh lib/wrap/wrap-common.sh lib/wrap/wrap-scan.sh lib/wrap/wrap-apply.sh lib/wrap/wrap-pull.sh lib/wrap/wrap-carry.sh lib/wrap/wrap-ci.sh lib/wrap/wrap-merge.sh lib/wrap/wrap-land.sh lib/wrap/wrap-start.sh lib/wrap/wrap-log.sh lib/wrap/wrap-deploy.sh lib/wrap/wrap-rebase.sh lib/wrap/report-lint.sh lib/wrap/wrap-adopt.sh

set -uo pipefail
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

# Pin the gate-ledger root at a scratch dir: `land`'s ship-gate record is the first
# thing in this file that calls gate-ledger.sh, so every `$WRAP` call below now shells out to
# it. Without this, that call would resolve the real machine's ~/.local/state/dwarves-kit/logs
# corpus instead of a throwaway one.
KIT_LEDGER_DIR="$TMPD/ledger"; export KIT_LEDGER_DIR
GATE_LEDGER="$KIT_DIR/lib/gate/gate-ledger.sh"

# Pin git's init template at an empty dir: the operator's init.templateDir may point nowhere (one
# warning per init and clone) and must never seed a fixture repo.
GIT_TEMPLATE_DIR="$TMPD/no-git-template"; export GIT_TEMPLATE_DIR; mkdir -p "$GIT_TEMPLATE_DIR"

# --------------------------------------------------------------------------- gh stub
mkdir -p "$TMPD/stub"
cat > "$TMPD/stub/gh" <<'STUB'
#!/usr/bin/env bash
# gh stub: answers exactly what wrap.sh asks and records every call.
printf '%s\n' "$*" >> "${GH_STUB_CALLS:-/dev/null}"
# A second, additive log: each argument bracketed on its own, so a case that must prove an
# arg's exact boundaries (a title with internal spaces landed as ONE argv entry, not several)
# can check it without touching the space-joined $GH_STUB_CALLS format every existing
# assertion in this file already depends on.
if [ -n "${GH_STUB_CALLS_QUOTED:-}" ]; then
  { printf '<%s>' "$@"; printf '\n'; } >> "$GH_STUB_CALLS_QUOTED"
fi
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
        head=""; author=""; state=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --head) head="${2:-}"; shift 2 ;;
            --author) author="${2:-}"; shift 2 ;;
            --state) state="${2:-}"; shift 2 ;;
            *) shift ;;
          esac
        done
        if [ -n "$head" ] && [ "$state" = "open" ]; then
          key="GH_STUB_OPEN_HEAD_$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')"
          eval "val=\"\${$key:-}\""
          [ -n "$val" ] || val="[]"
          printf '%s\n' "$val"
          exit "${GH_STUB_LIST_RC:-0}"
        elif [ -n "$head" ]; then
          # GH_STUB_MERGED_HEAD_RC models a failed merged-head read: gh prints nothing
          # and exits non-zero.
          [ "${GH_STUB_MERGED_HEAD_RC:-0}" = "0" ] || exit "$GH_STUB_MERGED_HEAD_RC"
          key="GH_STUB_MERGED_$(printf '%s' "$head" | tr -c 'A-Za-z0-9' '_')"
          eval "val=\"\${$key:-}\""
          [ -n "$val" ] || val="[]"
          printf '%s\n' "$val"
        else
          # --author sends real gh to the GraphQL search index, which lags a PR opened
          # seconds ago; the plain list reads the repository itself and never lags.
          if [ "$state" = "merged" ]; then
            # `apply`'s origin sweep reads every merged PR of the repo in one list.
            # GH_STUB_MERGED_ALL_RC models a failed read: gh prints nothing and exits non-zero.
            [ "${GH_STUB_MERGED_ALL_RC:-0}" = "0" ] || exit "$GH_STUB_MERGED_ALL_RC"
            printf '%s\n' "${GH_STUB_MERGED_ALL:-[]}"; exit 0
          fi
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
        fields=""; repo=""
        while [ $# -gt 0 ]; do
          case "$1" in --json) fields="${2:-}"; shift 2 ;; --repo) repo="${2:-}"; shift 2 ;; *) shift ;; esac
        done
        case "$fields" in
          state,mergeCommit)
            # The merge commit GitHub names is whatever landed on the default branch, so the
            # stub answers the --repo remote's HEAD (every fixture remote is a local path).
            merge_oid="$(git -C "$repo" rev-parse -q --verify HEAD 2>/dev/null)"
            default_state="{\"state\":\"MERGED\",\"mergeCommit\":{\"oid\":\"${merge_oid:-1a2b3c4d5e6f}\"}}"
            printf '%s\n' "${GH_STUB_VIEW_STATE:-$default_state}" ;;
          *)
            key="GH_STUB_PR_$n"; eval "val=\"\${$key:-}\""
            # Read k serves GH_STUB_PR_<n>_<j> for the highest j <= k that is set (j >= 2),
            # else GH_STUB_PR_<n>, so a case can model a PR whose mergeability changes as
            # GitHub catches up with the re-merge push.
            cnt_f="${GH_STUB_CALLS:-/dev/null}.view-$n"
            cnt=$(( $(cat "$cnt_f" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$cnt_f" 2>/dev/null
            # GH_STUB_FAIL_VIEW_<n>_<k>: the k-th view of PR <n> fails the way a gh read
            # failure does -- nothing printed, non-zero exit.
            eval "vf=\"\${GH_STUB_FAIL_VIEW_${n}_${cnt}:-0}\""
            [ "$vf" = "1" ] && exit 1
            j="$cnt"
            while [ "$j" -gt 1 ]; do
              key2="GH_STUB_PR_${n}_${j}"; eval "val2=\"\${$key2:-}\""
              if [ -n "${val2:-}" ]; then val="$val2"; break; fi
              j=$(( j - 1 ))
            done
            [ -n "$val" ] || val="{}"
            # A %REMERGE_TIP% marker resolves against the real branch tip, because a
            # re-merge test cannot know the recovered commit's SHA before wrap creates it.
            # %SQUASH_TIP% resolves the <branch>-squash tip the same way, for the
            # squash-fallback cases whose replacement-PR head exists only once wrap
            # commit-trees it mid-run.
            if [ -n "${GH_STUB_LAND_REPO:-}" ]; then
              real_oid="$(git -C "$GH_STUB_LAND_REPO" rev-parse "${GH_STUB_LAND_BRANCH:-feat/union}" 2>/dev/null)"
              val="${val//%REMERGE_TIP%/$real_oid}"
              sq_oid="$(git -C "$GH_STUB_LAND_REPO" rev-parse "${GH_STUB_SQUASH_BRANCH:-feat/union-squash}" 2>/dev/null)"
              val="${val//%SQUASH_TIP%/$sq_oid}"
              # %REMOTE_HEAD% is the remote's own branch tip: what GitHub reports as the
              # PR head once a foreign push has landed on the branch behind our merge.
              rh_oid="$(git -C "${GH_STUB_LAND_REMOTE:-.}" rev-parse "${GH_STUB_LAND_BRANCH:-feat/union}" 2>/dev/null)"
              val="${val//%REMOTE_HEAD%/$rh_oid}"
            fi
            # %CARRY_TIP% is the newest wrap/stray-* branch (by name, so by stamp) on the
            # carry-autoland fixture's bare origin: that branch exists only once apply pushes it.
            if [ -n "${GH_STUB_CARRY_REMOTE:-}" ]; then
              c_oid="$(git -C "$GH_STUB_CARRY_REMOTE" for-each-ref --sort=-refname --count=1 \
                --format='%(objectname)' 'refs/heads/wrap/stray-*' 2>/dev/null)"
              val="${val//%CARRY_TIP%/$c_oid}"
            fi
            printf '%s\n' "$val" ;;
        esac
        exit 0 ;;
      create)
        # `land` reads the number off the printed URL, so the stub answers with one.
        printf '%s\n' "https://github.com/o/r/pull/${GH_STUB_CREATE_NUM:-42}"
        exit "${GH_STUB_CREATE_RC:-0}" ;;
      ready)
        # `merge --pr N` marks a targeted draft ready. Nothing to print; real gh is silent too.
        exit "${GH_STUB_READY_RC:-0}" ;;
      edit)
        # `land`'s ci-label sync adds (or removes and re-adds) the `ci` label. The call is
        # recorded like every other; a case that needs the next `pr view` to show the new
        # label steps its GH_STUB_PR_<n>_<j> fixtures, the same way a moved head is modeled.
        exit "${GH_STUB_EDIT_RC:-0}" ;;
      merge)
        # GH_STUB_MERGE_FAILS=N fails the first N merge calls with
        # GH_STUB_MERGE_ERR (default a 502 body) and GH_STUB_MERGE_FAIL_RC
        # (default 1): a transient GitHub outage that clears mid-retry. A
        # failure after the budget, or with FAILS unset, exits
        # GH_STUB_MERGE_RC (default 0) as before; GH_STUB_MERGE_ERR prints on
        # every failing call either way, so a case can model a refusal text.
        cnt_f="${GH_STUB_CALLS:-/dev/null}.merge"
        cnt=$(( $(cat "$cnt_f" 2>/dev/null || echo 0) + 1 )); echo "$cnt" > "$cnt_f" 2>/dev/null
        if [ "$cnt" -le "${GH_STUB_MERGE_FAILS:-0}" ]; then
          printf '%s\n' "${GH_STUB_MERGE_ERR:-HTTP 502 Bad Gateway}" >&2
          exit "${GH_STUB_MERGE_FAIL_RC:-1}"
        fi
        rc="${GH_STUB_MERGE_RC:-0}"
        if [ "$rc" -ne 0 ] && [ -n "${GH_STUB_MERGE_ERR:-}" ]; then
          printf '%s\n' "$GH_STUB_MERGE_ERR" >&2
        fi
        # GH_STUB_LAND_OID=1 lands the --match-head-commit oid itself on the --repo remote's
        # default branch, for a head no local branch names (a carry branch apply just pushed).
        if [ "${GH_STUB_LAND_OID:-0}" = "1" ] && [ "$rc" -eq 0 ]; then
          m_repo=""; m_oid=""
          while [ $# -gt 0 ]; do
            case "$1" in --repo) m_repo="${2:-}"; shift 2 ;; --match-head-commit) m_oid="${2:-}"; shift 2 ;; *) shift ;; esac
          done
          git -C "$m_repo" update-ref "refs/heads/${GH_STUB_LAND_DEF:-main}" "$m_oid" 2>/dev/null
        fi
        # Stands in for GitHub's own squash landing on the default branch, so the
        # tree-verify step downstream has a real tree to compare against.
        if [ -n "${GH_STUB_LAND_REPO:-}" ]; then
          git -C "$GH_STUB_LAND_REPO" push -q "${GH_STUB_LAND_REMOTE:-origin}" \
            "${GH_STUB_LAND_BRANCH:-feat/union}:refs/heads/${GH_STUB_LAND_DEF:-main}" 2>/dev/null
        fi
        # GitHub's delete-branch-on-merge: the merged PR's head ref is gone from the remote.
        if [ "${GH_STUB_MERGE_DELETES_BRANCH:-0}" = "1" ] && [ -n "${GH_STUB_LAND_REMOTE:-}" ]; then
          git -C "$GH_STUB_LAND_REMOTE" update-ref -d "refs/heads/${GH_STUB_LAND_BRANCH:-feat/union}" 2>/dev/null
        fi
        exit "$rc" ;;
    esac
    exit 1 ;;
  label)
    verb="${1:-}"; [ $# -gt 0 ] && shift
    case "$verb" in
      list)
        # GH_STUB_LABELS is the repo's whole fuzzy --search answer: the exact-match on
        # `ci` is the code under test, so a fixture can hold "ci-cd" without a "ci".
        [ "${GH_STUB_LABEL_RC:-0}" = "0" ] || exit "$GH_STUB_LABEL_RC"
        printf '%s\n' "${GH_STUB_LABELS:-[]}"
        exit 0 ;;
    esac
    exit 1 ;;
esac
exit 1
STUB
chmod +x "$TMPD/stub/gh"
PATH="$TMPD/stub:$PATH"; export PATH
GH_STUB_CALLS="$TMPD/gh-calls.log"; export GH_STUB_CALLS; : > "$GH_STUB_CALLS"
# One mergeability read per settle for every case that does not test the settle wait
# itself; those cases set their own bound and put a no-op `sleep` first on PATH.
KIT_WRAP_SETTLE_SECS=0; export KIT_WRAP_SETTLE_SECS
mkdir -p "$TMPD/nosleep"; printf '#!/bin/sh\nexit 0\n' > "$TMPD/nosleep/sleep"; chmod +x "$TMPD/nosleep/sleep"

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


# --- shared fixtures (moved verbatim from the monolith; two or more suites use them) ---
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

LAB_STRAY=$'# Lab log\n\n---\n\n2026-09-05 · stray: the second line\n2026-09-04 · stray: the first line\n2026-09-01 · base: the first line\n'

AL_ON="$TMPD/autoland-on"; AL_PROJ="$TMPD/autoland-project"; mkdir -p "$AL_ON" "$AL_PROJ"
printf '[wrap]\nautoland_carry = true\n' > "$AL_ON/kit.toml"
printf '[wrap]\nautoland_carry = true\n' > "$AL_PROJ/.kit.toml"

AL_PR='{"number":42,"title":"carry","headRefName":"wrap/stray","headRefOid":"%CARRY_TIP%","baseRefName":"main","mergeable":"MERGEABLE","mergeStateStatus":"CLEAN","reviewDecision":"","statusCheckRollup":[],"isDraft":false}'
AL_OPEN='[{"number":42,"title":"carry","headRefName":"wrap/stray"}]'
al_run() { # al_run <bare> <clone> [--apply] -- apply with the knob on and the carry stub wired
  local bare="$1" clone="$2"; shift 2
  : > "$GH_STUB_CALLS"; rm -f "$GH_STUB_CALLS".*
  KIT_CONFIG_OPERATOR="$AL_ON" KIT_WRAP_CARRY_CHECKS_SECS="${AL_WAIT:-0}" GH_STUB_CARRY_REMOTE="$bare" GH_STUB_LAND_OID=1 \
    GH_STUB_OPEN_PRS="$AL_OPEN" GH_STUB_PR_42="${AL_PR_OVERRIDE:-$AL_PR}" "$WRAP" apply "$@" "$clone" 2>&1
}
al_orphan() { # al_orphan <name> -- an origin carry branch holding one of the two stray lines, no PR
  local p="$TMPD/upush-al-$1"
  git clone -q "$TMPD/ubare-$1" "$p"; gitc "$p"
  printf '%s' $'# Lab log\n\n---\n\n2026-09-04 · stray: the first line\n2026-09-01 · base: the first line\n' > "$p/_meta/LAB_LOG.md"
  git -C "$p" commit -qam "chore(LAB_LOG): carry 1 stray lines from a shared checkout"
  git -C "$p" push -q origin "HEAD:refs/heads/wrap/stray-meta-lab-log-md-20260101-0000"
}

PD_ON="$TMPD/pd-knob-on"; mkdir -p "$PD_ON"
printf '[wrap]\npull_past_dirty = true\n' > "$PD_ON/kit.toml"
PD_PROJ="$TMPD/pd-knob-project"; mkdir -p "$PD_PROJ"
printf '[wrap]\npull_past_dirty = true\n' > "$PD_PROJ/.kit.toml"

# Each land fixture SHAPE (builder + args + the LGEN/LBRANCH/LBASE_ATTR knobs) is built once under a
# private name, then every case gets its own `cp -R` of the bare remote and the clone. The copy keeps
# two absolute paths pointing at the template, so both are repaired: the clone's origin url and the
# linked worktree's gitdir links. Cases never touch the template, so none sees another's mutations.
land_cached() { # land_cached <raw builder> <name> [builder args...]
  local fn="$1" name="$2"; shift 2
  local tag="_c$(printf '%s\0' "$fn" "$@" "${LGEN:-}" "${LBRANCH:-}" "${LBASE_ATTR:-}" | cksum | cut -d' ' -f1)"
  [ -d "$TMPD/ld-repo-$tag" ] || "$fn" "$tag" "$@" || return 1
  [ ! -e "$TMPD/ld-repo-$name" ] || return 1   # a reused name would nest the copy, never overlay it
  cp -R "$TMPD/ld-bare-$tag" "$TMPD/ld-bare-$name" && cp -R "$TMPD/ld-repo-$tag" "$TMPD/ld-repo-$name" || return 1
  git -C "$TMPD/ld-repo-$name" remote set-url origin "$TMPD/ld-bare-$name"
  git -C "$TMPD/ld-repo-$name" worktree repair "$TMPD/ld-repo-$name/wt" >/dev/null 2>&1
}

_build_land() { # _build_land <name> [--modify-base|--union-log] [branch] [commit-subject...]
  local name="$1" mode="${2:-}" branch="${3:-feat/land}" work="$TMPD/ld-work-$1" repo="$TMPD/ld-repo-$1"
  local nshift=$#; [ "$nshift" -gt 3 ] && nshift=3
  shift "$nshift"
  mkdir -p "$work"; git -C "$work" init -q; gitc "$work"
  git -C "$work" symbolic-ref HEAD refs/heads/main
  echo base > "$work/base.txt"
  if [ "$mode" = "--union-log" ]; then
    mkdir -p "$work/_meta"
    printf '_meta/LAB_LOG.md merge=union\n' > "$work/.gitattributes"
    printf 'base entry\n' > "$work/_meta/LAB_LOG.md"
  fi
  git -C "$work" add -A; git -C "$work" commit -qm base
  git clone -q --bare "$work" "$TMPD/ld-bare-$name"
  git clone -q "$TMPD/ld-bare-$name" "$repo"; gitc "$repo"
  git -C "$repo" remote set-head origin main >/dev/null 2>&1
  git -C "$repo" worktree add -q -b "$branch" "$repo/wt" main >/dev/null 2>&1
  if [ "$mode" = "--modify-base" ]; then
    echo "branch edit" > "$repo/wt/base.txt"
    git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "feat: the landed change"
  elif [ "$mode" = "--union-log" ]; then
    echo "pr change" > "$repo/wt/pr-file.txt"
    printf 'remote entry\nbase entry\n' > "$repo/wt/_meta/LAB_LOG.md"
    git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "feat: the landed change"
  elif [ $# -gt 0 ]; then
    # SPEC-326 title-selection fixtures: one trivial commit per subject given, in order,
    # so a case can seed the exact multi-commit shape its title-pick expectation needs.
    local i=0 subj
    for subj in "$@"; do
      i=$((i + 1))
      echo "line $i" >> "$repo/wt/multi.txt"
      git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "$subj"
    done
  else
    echo "pr change" > "$repo/wt/pr-file.txt"
    git -C "$repo/wt" add -A; git -C "$repo/wt" commit -qm "feat: the landed change"
  fi
}
build_land() { land_cached _build_land "$@"; }   # build_land <name> [--modify-base|--union-log] [branch] [commit-subject...]
