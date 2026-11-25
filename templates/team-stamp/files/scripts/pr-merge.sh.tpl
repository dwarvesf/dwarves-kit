#!/usr/bin/env bash
# pr-merge.sh - the merge guard. Squash-merge a PR only when it is safe.
#
#   bash scripts/pr-merge.sh <number>             check, then merge and delete the branch
#   bash scripts/pr-merge.sh --wait <number>      wait for pending checks, then check and merge
#   bash scripts/pr-merge.sh --dry-run <number>   print the verdict, merge nothing
#   bash scripts/pr-merge.sh --wait --timeout <seconds> <number>   bound the wait (default 900)
#   bash scripts/pr-merge.sh --help
#
# This plan cannot make GitHub require checks before a merge, so this script does
# it for the people and agents who follow the rules. It refuses a draft, a
# failing or pending check, a merge conflict, and a PR that changes a door path
# without an approving review from a second person.
#
# What binds the workflow file. GitHub runs a pull request's own copy of the workflow, so a PR can
# edit it. This script therefore requires BOTH checks `changes` and `pr-shape`, each from the
# workflow named CI, on the head it judged, and treats the harness's own files as doors: the
# workflows, scripts/, .claude/, OWNERS.md, AGENTS.md, docs/TEAM-WORKFLOW.md and .kit.toml. A repo's
# --door-paths ADD to that list. The first pull request that introduces the stamp touches every
# door: merge it by hand, after a second person has read it.
#
# An approval counts only when all of these hold: it is the reviewer's latest decision, it was made
# on the head commit this script judged (a push after the approval voids it), the reviewer's
# association with the repo is OWNER, MEMBER or COLLABORATOR, the reviewer is not the PR's author and
# not a bot account, and, when a door approver is set, the login matches. A review field gh does not
# report means the approval does not count.
#
# This script refuses to run when its own text differs from origin/<default branch>:scripts/pr-merge.sh,
# so a pull request's edited copy is not the copy that judges it. Never run a pull request's copy.
#
# Only the newest run of each check name counts, so an old failed run that was
# fixed and rerun does not block. A check name reported by more than one producer
# is refused: a workflow a PR adds could emit a passing check with the same name.
# Zero other checks is green only when the "changes" and "pr-shape" jobs passed: they run on every
# pull request, so passing ones prove CI ran.
#
# --wait polls the PR every 15 seconds until no check is pending, then judges as
# usual. --timeout <seconds> bounds the wait: on timeout it exits 1 and names the
# checks still pending. A draft is refused at once, with no waiting.
# PR_MERGE_POLL_SECS sets the poll interval. Under --wait, mergeability UNKNOWN
# (GitHub has not computed it yet, as right after a push) counts as pending too.
# Without --wait it is refused.
#
# The merge is pinned to the head the script judged (--match-head-commit), so a
# push after the check makes GitHub refuse the merge.
#
# Needs gh and git. Exit 0 merged (or dry-run clean), 1 refused or timed out, 2 bad usage.
# Every refusal prints two lines on stderr: the rule, then a "Fix:" line.
set -euo pipefail

# Door paths (case globs; * crosses a slash). BASE_DOORS are the harness's own files and are always
# doors. DOORS holds the paths this repo added with --door-paths; it may be empty.
BASE_DOORS=(".github/workflows/*" "scripts/*" ".claude/*" "OWNERS.md" "AGENTS.md" "docs/TEAM-WORKFLOW.md" ".kit.toml")
DOORS=({{DOOR_ARRAY}})
# The login that must approve a door change. Empty means any person other than the author.
APPROVER="{{DOOR_APPROVER}}"
# The branch this repo merges into.
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"
# The workflow whose checks count.
CI_WORKFLOW="CI"

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# Text from gh (check names, file paths, logins, error lines) is chosen by whoever wrote the PR.
# clean <text>: every character outside A-Za-z0-9._/@- , comma and space becomes ?, a newline
# included, so that text cannot forge a second line or carry an escape sequence.
clean() { printf '%s' "${1:0:80}" | LC_ALL=C tr -c 'A-Za-z0-9._/@ ,-' '?'; }
# is_safe <text>: succeeds only for a non-empty value of A-Za-z0-9._/@- that does not start with -.
# Only such a value is ever put into a "Fix:" command; the PR number is checked to be digits.
is_safe() {
    case "$1" in
    '' | -* | *[!A-Za-z0-9._/@-]*) return 1 ;;
    esac
    return 0
}

# fail <exit code> <rule> <fix>: the two-line refusal for a usage error.
fail() {
    printf 'pr-merge: %s\nFix: %s\n' "$2" "$3" >&2
    exit "$1"
}

dry=0
waiting=0
limit=900
limit_set=0
number=""
while [ $# -gt 0 ]; do
    case "$1" in
    --help | -h)
        usage
        exit 0
        ;;
    --dry-run) dry=1 ;;
    --wait) waiting=1 ;;
    --timeout)
        case "${2:-}" in
        '' | *[!0-9]*) fail 2 "--timeout needs a number of seconds" "bash scripts/pr-merge.sh --wait --timeout 900 <number>" ;;
        esac
        limit="$2"
        limit_set=1
        shift
        ;;
    -*) fail 2 "unknown option $(clean "$1")" "bash scripts/pr-merge.sh --help" ;;
    *)
        [ -z "$number" ] || fail 2 "one PR number only" "bash scripts/pr-merge.sh --wait <number>"
        number="$1"
        ;;
    esac
    shift
done
case "$number" in
'' | *[!0-9]*) fail 2 "give a PR number" "bash scripts/pr-merge.sh --wait <number>" ;;
esac
if [ "$limit_set" -eq 1 ] && [ "$waiting" -eq 0 ]; then
    fail 2 "--timeout needs --wait" "bash scripts/pr-merge.sh --wait --timeout $limit $number"
fi

# One gh call, judged from its JSON (never from a piped `gh pr checks`).
# The rollup lists every run on the head commit, across workflow runs, so each
# check name is judged by its newest entry only. Newest = latest startedAt, then
# completedAt, then the worse class. A queued or in-progress entry with no real
# start time counts as the newest. A CheckRun is pending until COMPLETED, ok on
# SUCCESS, NEUTRAL or SKIPPED, failing otherwise. A status context is ok on SUCCESS,
# pending on PENDING or EXPECTED, failing otherwise. An approval counts when it is
# the reviewer's latest decision (comments do not change it) and the reviewer is
# not the author. `ambiguous=` lists the check names whose entries come from more
# than one producer (workflow name plus kind). Every string that comes back has its
# control characters (a newline, an escape) replaced by ?, so one value is one line.
# shellcheck disable=SC2016
JQ='
def ctl: if type == "string" then gsub("[\\x00-\\x1f\\x7f]"; "?") else . end;
def cls:
  if .__typename == "StatusContext" then
    (if .state == "SUCCESS" then "ok"
     elif (.state == "PENDING" or .state == "EXPECTED") then "pending"
     else "failing" end)
  elif .status != "COMPLETED" then "pending"
  elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "ok"
  else "failing" end;
def nm: ((.name // .context) | ctl);
def rank: if cls == "ok" then 0 elif cls == "pending" then 1 else 2 end;
def started: (.startedAt // .createdAt // "");
def stamp:
  if cls == "pending" and (started == "" or (started | startswith("0001"))) then "9999"
  else started end;
def newest: group_by(nm) | map(sort_by([stamp, (.completedAt // ""), rank]) | last);
def producer: ((.workflowName // "") + "|" + (.__typename // ""));
(.statusCheckRollup // []) as $all
| ($all | newest) as $checks
| .author.login as $author
| (.headRefOid // "") as $head
| "draft=\(.isDraft)",
  "mergeable=\(.mergeable | tostring | ctl)",
  "failing=\([$checks[] | select(cls == "failing") | nm] | join(","))",
  "ambiguous=\([$all | group_by(nm)[] | select((map(producer) | unique | length) > 1) | .[0] | nm] | join(","))",
  "pending=\([$checks[] | select(cls == "pending") | nm] | join(","))",
  "author=\(.author.login | ctl)",
  "head=\((.headRefOid // "") | ctl)",
  "changes_passed=\([$checks[] | select(.__typename == "CheckRun" and .name == "changes" and .workflowName == wf and .status == "COMPLETED" and .conclusion == "SUCCESS")] | length)",
  "shape_passed=\([$checks[] | select(.__typename == "CheckRun" and .name == "pr-shape" and .workflowName == wf and .status == "COMPLETED" and .conclusion == "SUCCESS")] | length)",
  "approvals=\([(.reviews // []) | map(select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")) | group_by(.author.login)[] | sort_by(.submittedAt) | last | select(.state == "APPROVED" and (.author.login // "") != "" and .author.login != $author and ((.commit.oid // "") != "") and .commit.oid == ($head) and ((.authorAssociation // "") | IN("OWNER", "MEMBER", "COLLABORATOR")) and (.author.login | test("\\[bot\\]$|^app/") | not)) | .author.login | ctl] | join(","))",
  ((.files // [])[] | "file=\(.path | ctl)")
'

JQ="def wf: \"$CI_WORKFLOW\"; $JQ"

draft="" mergeable="" failing="" pending="" ambiguous="" changes_passed=0 shape_passed=0 approvals="" author="" head=""
doors="" nfiles=0
tab=$'\t'

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# Read the PR once and fill the variables above.
load() {
    local out line path pattern
    if ! out="$(gh pr view "$number" --json statusCheckRollup,isDraft,mergeable,files,author,reviews,headRefOid --jq "$JQ")"; then
        printf 'pr-merge: gh could not read PR #%s (is gh installed and logged in?)\nFix: gh auth status\n' "$number" >&2
        return 1
    fi
    draft="" mergeable="" failing="" pending="" ambiguous="" changes_passed=0 shape_passed=0 approvals="" author="" head=""
    doors="" nfiles=0
    while IFS= read -r line; do
        case "$line" in
        draft=*) draft="${line#draft=}" ;;
        mergeable=*) mergeable="${line#mergeable=}" ;;
        failing=*) failing="${line#failing=}" ;;
        pending=*) pending="${line#pending=}" ;;
        ambiguous=*) ambiguous="${line#ambiguous=}" ;;
        changes_passed=*) changes_passed="${line#changes_passed=}" ;;
        shape_passed=*) shape_passed="${line#shape_passed=}" ;;
        approvals=*) approvals="${line#approvals=}" ;;
        author=*) author="${line#author=}" ;;
        head=*) head="${line#head=}" ;;
        file=*)
            nfiles=$((nfiles + 1))
            path="${line#file=}"
            for pattern in "${BASE_DOORS[@]}" ${DOORS[@]+"${DOORS[@]}"}; do
                # shellcheck disable=SC2254
                case "$path" in
                $pattern)
                    doors="${doors:+$doors, }$path"
                    break
                    ;;
                esac
            done
            ;;
        esac
    done <<EOF
$out
EOF
    # gh may cap the file list, so a PR that long counts as touching a door.
    if [ "$nfiles" -ge 100 ]; then
        doors="${doors:+$doors, }100 or more files"
    fi
}

# Wait on the PR's own rollup, never a filtered run list: those can lag.
# A draft skips the wait and is refused by judge.
wait_for_checks() {
    local interval start commas
    interval="${PR_MERGE_POLL_SECS:-15}"
    start=$SECONDS
    # Right after a push the rollup is empty: no check has registered yet. Every PR
    # runs the changes job, so no passed changes job and no failure also means wait.
    # GitHub also reports mergeable UNKNOWN until it computes it: wait that out too.
    while [ "$draft" != "true" ]; do
        if [ -z "$pending" ]; then
            if { [ "$changes_passed" -eq 0 ] || [ "$shape_passed" -eq 0 ]; } && [ -z "$failing" ]; then
                pending="checks not registered yet"
            elif [ "$mergeable" = "UNKNOWN" ] && [ -z "$failing" ]; then
                pending="mergeability UNKNOWN"
            else
                break
            fi
        fi
        if [ $((SECONDS - start)) -ge "$limit" ]; then
            printf 'pr-merge: timed out after %ss waiting on #%s, still pending: %s (a run with no runner stays queued; scripts/check.sh is the local check)\nFix: gh run list --limit 10\n' "$limit" "$number" "$(clean "$pending")" >&2
            exit 1
        fi
        commas="${pending//[^,]/}"
        echo "pr-merge: waiting on $((${#commas} + 1)) pending check(s) of #$number ($((SECONDS - start))s of ${limit}s): $(clean "$pending")" >&2
        sleep "$interval"
        load || exit 1
    done
}

# One refusal per line: the rule, a tab, the fix.
refusals=""
refuse() {
    refusals="${refusals}${1}${tab}${2}
"
}

# The one judgment, for the PR that load just read. It fills refusals and merges nothing.
judge() {
    local author_lc approver_lc approvals_lc wait_fix reviewer_fix
    refusals=""
    wait_fix="bash scripts/pr-merge.sh --wait $number"

    [ "$draft" != "true" ] || refuse "the PR is a draft" "gh pr ready $number"
    [ -z "$failing" ] || refuse "failing check: $(clean "$failing")" "gh pr checks $number"
    [ -z "$pending" ] || refuse "pending check: $(clean "$pending")" "$wait_fix"
    [ -z "$ambiguous" ] || refuse "check reported by more than one workflow or app (a PR may add a workflow that emits the same name): $(clean "$ambiguous")" "gh pr checks $number"
    [ "$changes_passed" -ge 1 ] || refuse "the changes check has not passed from the workflow $CI_WORKFLOW on this head, so CI has not run" "$wait_fix"
    [ "$shape_passed" -ge 1 ] || refuse "the pr-shape check has not passed from the workflow $CI_WORKFLOW on this head" "$wait_fix"
    case "$mergeable" in
    MERGEABLE) ;;
    CONFLICTING)
        refuse "merge conflicts with the base branch" "gh pr update-branch $number"
        ;;
    *) refuse "mergeability is $(clean "$mergeable"), try again in a minute" "$wait_fix" ;;
    esac

    if [ -n "$doors" ]; then
        author_lc="$(lower "$author")"
        approver_lc="$(lower "$APPROVER")"
        approvals_lc="$(lower "$approvals")"
        reviewer_fix="ask a person other than the author to approve PR $number, then run $wait_fix"
        if [ -n "$APPROVER" ] && [ "$approver_lc" != "$author_lc" ] && is_safe "$APPROVER"; then
            reviewer_fix="gh pr edit $number --add-reviewer $APPROVER"
        fi
        if [ -z "$approvals" ]; then
            refuse "touches a door path ($(clean "$doors")) and has no approving review on this head from a second person (owner, member or collaborator, not a bot)" "$reviewer_fix"
        elif [ -n "$APPROVER" ] && [ "$approver_lc" != "$author_lc" ]; then
            case ",$approvals_lc," in
            *",$approver_lc,"*) ;;
            *) refuse "touches a door path ($(clean "$doors")): needs an approving review from $(clean "$APPROVER")" "$reviewer_fix" ;;
            esac
        fi
    fi

    if ! is_safe "$head"; then
        refuse "gh did not report a usable head commit, so the merge cannot be pinned" "gh pr view $number --json headRefOid"
    fi
    return 0
}

# self_check: this copy must be the default branch's copy. A pull request's own edited copy of this
# script is never the one that judges it.
self_check() {
    local self dir ref
    self="${BASH_SOURCE[0]}"
    dir="$(cd "$(dirname "$self")" && pwd)"
    is_safe "$DEFAULT_BRANCH" || fail 1 "the default branch name in this script is not a plain name" "bash scripts/pr-merge.sh --help"
    ref="origin/$DEFAULT_BRANCH"
    if ! git -C "$dir" fetch -q origin "$DEFAULT_BRANCH" 2>/dev/null; then
        echo "pr-merge: note: could not fetch origin $DEFAULT_BRANCH; comparing with the copy fetched last" >&2
    fi
    if ! git -C "$dir" cat-file -e "$ref:scripts/pr-merge.sh" 2>/dev/null; then
        fail 1 "$ref holds no scripts/pr-merge.sh, so this copy cannot be checked: this is the pull request that introduces the stamp" "merge the first stamp pull request by hand, after a second person has read it"
    fi
    git -C "$dir" show "$ref:scripts/pr-merge.sh" 2>/dev/null | cmp -s - "$self" ||
        fail 1 "this copy of scripts/pr-merge.sh differs from $ref, so it may be a pull request's own copy" "git checkout $DEFAULT_BRANCH && git pull, then run it again"
}
self_check

load || exit 1
if [ "$waiting" -eq 1 ]; then
    wait_for_checks
fi
judge

if [ -n "$refusals" ]; then
    while IFS="$tab" read -r rule fix; do
        [ -n "$rule" ] || continue
        printf 'pr-merge: refused #%s: %s\nFix: %s\n' "$number" "$rule" "$fix" >&2
    done <<EOF
$refusals
EOF
    exit 1
fi

if [ "$dry" -eq 1 ]; then
    echo "pr-merge: #$number would merge (dry run, nothing merged)"
    exit 0
fi
echo "pr-merge: #$number is clear, merging head $(clean "$head")"
if ! merge_out="$(gh pr merge "$number" --squash --delete-branch --match-head-commit "$head" 2>&1)"; then
    printf 'pr-merge: refused #%s: gh did not merge head %s: %s\nFix: %s\n' "$number" "$(clean "$head")" "$(clean "$(printf '%s\n' "$merge_out" | sed -n 1p)")" "bash scripts/pr-merge.sh --wait $number" >&2
    exit 1
fi
[ -z "$merge_out" ] || printf 'pr-merge: gh said: %s\n' "$(clean "$(printf '%s\n' "$merge_out" | sed -n 1p)")"
