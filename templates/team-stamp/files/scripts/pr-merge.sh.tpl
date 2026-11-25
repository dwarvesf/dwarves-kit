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
# without an approving review from a second person. The PR's author never counts
# as the second person. When a door approver is set, that person must be the one
# who approves (unless they wrote the PR; then any other person can).
#
# Only the newest run of each check name counts, so an old failed run that was
# fixed and rerun does not block. A check name reported by more than one producer
# is refused: a workflow a PR adds could emit a passing check with the same name.
# Zero checks is green only when the "changes" job passed: that job runs on every
# pull request, so a passing "changes" job proves CI ran.
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
# Needs gh. Exit 0 merged (or dry-run clean), 1 refused or timed out, 2 bad usage.
# Every refusal prints two lines on stderr: the rule, then a "Fix:" line.
set -euo pipefail

# Door paths (case globs; * crosses a slash). Empty means no path needs a second person.
DOORS=({{DOOR_ARRAY}})
# The login that must approve a door change. Empty means any person other than the author.
APPROVER="{{DOOR_APPROVER}}"
# The branch a PR in conflict merges from.
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"

usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
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
    -*) fail 2 "unknown option $1" "bash scripts/pr-merge.sh --help" ;;
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
# than one producer (workflow name plus kind).
# shellcheck disable=SC2016
JQ='
def cls:
  if .__typename == "StatusContext" then
    (if .state == "SUCCESS" then "ok"
     elif (.state == "PENDING" or .state == "EXPECTED") then "pending"
     else "failing" end)
  elif .status != "COMPLETED" then "pending"
  elif (.conclusion == "SUCCESS" or .conclusion == "NEUTRAL" or .conclusion == "SKIPPED") then "ok"
  else "failing" end;
def nm: (.name // .context);
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
| "draft=\(.isDraft)",
  "mergeable=\(.mergeable)",
  "failing=\([$checks[] | select(cls == "failing") | nm] | join(","))",
  "ambiguous=\([$all | group_by(nm)[] | select((map(producer) | unique | length) > 1) | .[0] | nm] | join(","))",
  "pending=\([$checks[] | select(cls == "pending") | nm] | join(","))",
  "author=\(.author.login)",
  "head=\(.headRefOid // "")",
  "changes_passed=\([$checks[] | select(.name == "changes" and .status == "COMPLETED" and .conclusion == "SUCCESS")] | length)",
  "approvals=\([(.reviews // []) | map(select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")) | group_by(.author.login)[] | sort_by(.submittedAt) | last | select(.state == "APPROVED" and .author.login != $author) | .author.login] | join(","))",
  ((.files // [])[] | "file=\(.path)")
'

draft="" mergeable="" failing="" pending="" ambiguous="" changes_passed=0 approvals="" author="" head=""
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
    draft="" mergeable="" failing="" pending="" ambiguous="" changes_passed=0 approvals="" author="" head=""
    doors="" nfiles=0
    while IFS= read -r line; do
        case "$line" in
        draft=*) draft="${line#draft=}" ;;
        mergeable=*) mergeable="${line#mergeable=}" ;;
        failing=*) failing="${line#failing=}" ;;
        pending=*) pending="${line#pending=}" ;;
        ambiguous=*) ambiguous="${line#ambiguous=}" ;;
        changes_passed=*) changes_passed="${line#changes_passed=}" ;;
        approvals=*) approvals="${line#approvals=}" ;;
        author=*) author="${line#author=}" ;;
        head=*) head="${line#head=}" ;;
        file=*)
            nfiles=$((nfiles + 1))
            path="${line#file=}"
            if [ "${#DOORS[@]}" -gt 0 ]; then
                for pattern in "${DOORS[@]}"; do
                    # shellcheck disable=SC2254
                    case "$path" in
                    $pattern)
                        doors="${doors:+$doors, }$path"
                        break
                        ;;
                    esac
                done
            fi
            ;;
        esac
    done <<EOF
$out
EOF
    # gh may cap the file list. With a door list set, a PR that long counts as touching a door.
    if [ "$nfiles" -ge 100 ] && [ "${#DOORS[@]}" -gt 0 ]; then
        doors="${doors:+$doors, }(100 or more files)"
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
            if [ "$changes_passed" -eq 0 ] && [ -z "$failing" ]; then
                pending="(checks not registered yet)"
            elif [ "$mergeable" = "UNKNOWN" ] && [ -z "$failing" ]; then
                pending="(mergeability UNKNOWN)"
            else
                break
            fi
        fi
        if [ $((SECONDS - start)) -ge "$limit" ]; then
            printf 'pr-merge: timed out after %ss waiting on #%s, still pending: %s (a run with no runner stays queued; scripts/check.sh is the local check)\nFix: gh run list --limit 10\n' "$limit" "$number" "$pending" >&2
            exit 1
        fi
        commas="${pending//[^,]/}"
        echo "pr-merge: waiting on $((${#commas} + 1)) pending check(s) of #$number ($((SECONDS - start))s of ${limit}s): $pending" >&2
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
    local author_lc approver_lc approvals_lc reviewer wait_fix
    refusals=""
    wait_fix="bash scripts/pr-merge.sh --wait $number"

    [ "$draft" != "true" ] || refuse "the PR is a draft" "gh pr ready $number"
    [ -z "$failing" ] || refuse "failing check: $failing" "gh pr checks $number"
    [ -z "$pending" ] || refuse "pending check: $pending" "$wait_fix"
    [ -z "$ambiguous" ] || refuse "check reported by more than one workflow or app (a PR may add a workflow that emits the same name): $ambiguous" "gh pr checks $number"
    [ "$changes_passed" -ge 1 ] || refuse "the changes job has not passed, so CI has not run" "$wait_fix"
    case "$mergeable" in
    MERGEABLE) ;;
    CONFLICTING) refuse "merge conflicts with the base branch" "gh pr checkout $number && git fetch origin && git merge origin/$DEFAULT_BRANCH && git push" ;;
    *) refuse "mergeability is $mergeable, try again in a minute" "$wait_fix" ;;
    esac

    if [ -n "$doors" ]; then
        author_lc="$(lower "$author")"
        approver_lc="$(lower "$APPROVER")"
        approvals_lc="$(lower "$approvals")"
        reviewer="<login of a person other than the author>"
        if [ -n "$APPROVER" ] && [ "$approver_lc" != "$author_lc" ]; then
            reviewer="$APPROVER"
        fi
        if [ -z "$approvals" ]; then
            refuse "touches a door path ($doors) and has no approving review from someone other than its author" "gh pr edit $number --add-reviewer $reviewer"
        elif [ -n "$APPROVER" ] && [ "$approver_lc" != "$author_lc" ]; then
            case ",$approvals_lc," in
            *",$approver_lc,"*) ;;
            *) refuse "touches a door path ($doors): needs an approving review from $APPROVER" "gh pr edit $number --add-reviewer $APPROVER" ;;
            esac
        fi
    fi

    [ -n "$head" ] || refuse "gh did not report the head commit, so the merge cannot be pinned" "gh pr view $number --json headRefOid"
    return 0
}

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
echo "pr-merge: #$number is clear, merging head $head"
if ! merge_out="$(gh pr merge "$number" --squash --delete-branch --match-head-commit "$head" 2>&1)"; then
    printf 'pr-merge: refused #%s: gh did not merge head %s: %s\nFix: %s\n' "$number" "$head" "$(printf '%s\n' "$merge_out" | sed -n 1p)" "bash scripts/pr-merge.sh --wait $number" >&2
    exit 1
fi
[ -z "$merge_out" ] || printf '%s\n' "$merge_out"
