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
# workflow named CI, on the head it judged, and treats the harness's own files as doors: .github/,
# scripts/, OWNERS.md, docs/TEAM-WORKFLOW.md and .kit.toml at the root; .claude/, .cursor/,
# .vscode/, .mcp.json, AGENTS.md, CLAUDE.md, CLAUDE.local.md and GEMINI.md at any depth. Paths are
# matched in lower case, so `.CLAUDE/x` is a door too. A path (current or previous name) with ANY byte
# outside printable ASCII is a door as well: a case-insensitive disk can fold a non-ASCII spelling
# (U+017F, U+212A, others) onto a guarded name, and no list of code points is complete. A repo's
# --door-paths ADD to that list. The first pull request that introduces the stamp
# touches every door: merge it by hand, after a second person has read it.
#
# Which runs count. The check rollup of a head lists runs of every pull request on that head, so a
# check counts only when its run id is a pull_request run of THIS pull request on the stamped
# workflow file (read from the actions runs API). The pull request's base must be the default
# branch, and a run counts only when it was created after the last base change of the pull request (a
# re-run keeps its creation time and the base it first ran against). The guard also refuses when the
# head commit belongs to any other pull request in any state. GitHub lists on a run every open pull request that shares its head, so a run counts only
# when this pull request is the only one listed: a second pull request on the same head, with a base
# whose checks pass anything, cannot lend its runs. The changed files come from the REST files list, paginated, with each previous name
# (a rename out of a door is a door change); more than 3000 files, or any failed read, refuses.
#
# An approval counts only when all of these hold: it is the reviewer's latest decision, it was made
# on the head commit this script judged (a push after the approval voids it), the reviewer's
# association with the repo is OWNER, MEMBER or COLLABORATOR, the reviewer is not the PR's author and
# not a bot account, it was submitted after the pull request's last base change (a retarget voids
# it), and, when a door approver is set, the login matches. A review field gh does not report means
# the approval does not count.
#
# This script refuses to run when its own text differs from origin/<default branch>:scripts/pr-merge.sh.
# That stops an honest out-of-date copy. It does NOT stop a hostile copy, which can simply omit the check.
# The defence against a hostile copy is that nobody runs a pull request's copy (no Fix line says to)
# and that scripts/ is a door.
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
# Byte-wise matching: a path is judged by its bytes, never by a locale.
export LC_ALL=C

# Doors match any casing; ownership (scripts/check-owners.sh) matches the exact path.
# Door paths (case globs, written in lower case: a path is lowered before it is matched; * crosses a
# slash; an extra pattern from --door-paths is lowered too). BASE_DOORS are the harness's own files and are always
# doors. DOORS holds the paths this repo added with --door-paths; it may be empty.
BASE_DOORS=(".github/*" "scripts/*" ".claude/*" "*/.claude/*" ".mcp.json" "*/.mcp.json" "owners.md" "agents.md" "*/agents.md" "claude.md" "*/claude.md" "claude.local.md" "*/claude.local.md" "gemini.md" "*/gemini.md" ".cursor/*" "*/.cursor/*" ".vscode/*" "*/.vscode/*" "docs/team-workflow.md" ".kit.toml")
DOORS=({{DOOR_ARRAY}})
# The login that must approve a door change. Empty means any person other than the author.
APPROVER="{{DOOR_APPROVER}}"
# The branch this repo merges into.
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"
# The workflow whose checks count.
CI_WORKFLOW="CI"
# The stamped workflow file; a run counts only when its path ends with this.
CI_FILE=".github/workflows/ci.yml"
MAX_FILES=3000

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
def runid: ([(.detailsUrl // "") | capture("/actions/runs/(?<id>[0-9]+)(/|$)")] | (.[0].id) // null);
def mine: (runid) as $r | ($r == null) or (($r | tonumber) as $n | any(runs[]; . == $n));
((.statusCheckRollup // []) | map(select(mine))) as $all
| ($all | newest) as $checks
| .author.login as $author
| (.headRefOid // "") as $head
| "draft=\(.isDraft)",
  "mergeable=\(.mergeable | tostring | ctl)",
  "base=\((.baseRefName // "") | ctl)",
  "failing=\([$checks[] | select(cls == "failing") | nm] | join(","))",
  "ambiguous=\([$all | group_by(nm)[] | select((map(producer) | unique | length) > 1) | .[0] | nm] | join(","))",
  "pending=\([$checks[] | select(cls == "pending") | nm] | join(","))",
  "author=\(.author.login | ctl)",
  "head=\((.headRefOid // "") | ctl)",
  "changes_passed=\([$checks[] | select(.__typename == "CheckRun" and .name == "changes" and .workflowName == wf and (runid != null) and .status == "COMPLETED" and .conclusion == "SUCCESS")] | length)",
  "shape_passed=\([$checks[] | select(.__typename == "CheckRun" and .name == "pr-shape" and .workflowName == wf and (runid != null) and .status == "COMPLETED" and .conclusion == "SUCCESS")] | length)",
  "approvals=\([(.reviews // []) | map(select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")) | group_by(.author.login)[] | sort_by(.submittedAt) | last | select(.state == "APPROVED" and (.author.login // "") != "" and .author.login != $author and ((.commit.oid // "") != "") and .commit.oid == ($head) and ((.authorAssociation // "") | IN("OWNER", "MEMBER", "COLLABORATOR")) and (.author.login | test("\\[bot\\]$|^app/") | not) and ((.submittedAt // "") > basechg)) | .author.login | ctl] | join(","))",
  empty
'

JQ="def wf: \"$CI_WORKFLOW\"; $JQ"

draft="" mergeable="" base="" failing="" pending="" ambiguous="" changes_passed=0 shape_passed=0 approvals="" author="" head=""
doors="" nfiles=0
readfail="" otherprs=""
tab=$'\t'

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# A path with a byte outside 0x20 to 0x7E is a door, whatever it looks like. A case-insensitive disk can
# fold a non-ASCII spelling (U+017F to s, U+212A to k, and others) onto a guarded path, and no list of
# code points is complete. This byte rule is the layer that does not depend on such a list.
# odd_path <path>: succeeds when the path holds a byte outside 0x20 to 0x7E (the locale is C, so a
# multibyte character counts as bytes).
odd_path() {
    case "$1" in
    *[![:print:]]*) return 0 ;;
    esac
    return 1
}

# match_doors <path>: succeeds when the path is a door: a byte outside printable ASCII, or the lowered
# path matches a lowered door pattern. oddseen is set when the byte rule fired.
oddseen=0
match_doors() {
    local lp pattern
    if odd_path "$1"; then
        oddseen=1
        return 0
    fi
    lp="$(lower "$1")"
    for pattern in "${BASE_DOORS[@]}" ${DOORS[@]+"${DOORS[@]}"}; do
        pattern="$(lower "$pattern")"
        # shellcheck disable=SC2254
        case "$lp" in
        $pattern) return 0 ;;
        esac
    done
    return 1
}

# Read the PR and fill the variables above. Every read must succeed and parse, or the load fails and
# the PR is refused: a read that fails is never treated as "nothing found".
load() {
    local out line path head1 head2 runs_out run_ids base_changes basechg files_out prefix prs_out
    readfail=""
    oddseen=0
    otherprs=""
    if ! head1="$(gh api "repos/{owner}/{repo}/pulls/$number" --jq '.head.sha' 2>/dev/null)" || ! is_safe "$head1"; then
        printf 'pr-merge: gh could not read PR #%s (is gh installed and logged in?)\nFix: gh auth status\n' "$number" >&2
        return 1
    fi
    # the last time the base branch of this pull request changed
    basechg=""
    if ! base_changes="$(gh api --paginate "repos/{owner}/{repo}/issues/$number/timeline?per_page=100" \
        --jq '.[] | select(.event == "base_ref_changed") | .created_at' 2>/dev/null)"; then
        readfail="${readfail:-the timeline of this pull request could not be read}"
    else
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in
            [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) [ "$line" \> "$basechg" ] && basechg="$line" ;;
            *) readfail="${readfail:-the timeline of this pull request could not be parsed}" ;;
            esac
        done <<EOF
$base_changes
EOF
    fi
    # the pull_request runs of THIS pull request on the stamped workflow file, for this head, created after
    # the last base change (a re-run keeps its creation time and its first base)
    if ! runs_out="$(gh api --paginate "repos/{owner}/{repo}/actions/runs?head_sha=$head1&event=pull_request&per_page=100" \
        --jq ".workflow_runs[] | select((.path // \"\") | endswith(\"/$CI_FILE\") or . == \"$CI_FILE\") | select(((.pull_requests // []) | length) == 1 and .pull_requests[0].number == $number) | select((.created_at // \"\") > \"$basechg\") | .id" 2>/dev/null)"; then
        readfail="the workflow runs of this pull request could not be read"
    fi
    run_ids=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        case "$line" in *[!0-9]*) readfail="the workflow runs of this pull request could not be parsed"; break ;; esac
        run_ids="${run_ids:+$run_ids,}$line"
    done <<EOF
$runs_out
EOF
    # every pull request this head commit belongs to, in any state: a second one makes the runs of this
    # head ambiguous, because a run lists only OPEN pull requests
    otherprs=""
    if ! prs_out="$(gh api --paginate "repos/{owner}/{repo}/commits/$head1/pulls?per_page=100" --jq '.[] | .number' 2>/dev/null)"; then
        readfail="${readfail:-the pull requests of the head commit could not be read}"
    else
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            case "$line" in
            *[!0-9]*) readfail="${readfail:-the pull requests of the head commit could not be parsed}" ;;
            "$number") ;;
            *) otherprs="${otherprs:+$otherprs,}$line" ;;
            esac
        done <<EOF
$prs_out
EOF
    fi
    # the changed files, with the previous name of a rename: one name per line, controls replaced by ?
    if ! files_out="$(gh api --paginate "repos/{owner}/{repo}/pulls/$number/files?per_page=100" \
        --jq '.[] | ("f " + ((.filename // "") | gsub("[\\x00-\\x1f\\x7f]"; "\u00bf"))), (if .previous_filename then "p " + (.previous_filename | gsub("[\\x00-\\x1f\\x7f]"; "\u00bf")) else empty end)' 2>/dev/null)"; then
        readfail="${readfail:-the changed files of this pull request could not be read}"
    fi
    # the head again, after the files read: a head that moved in between makes the file list another head's
    if ! head2="$(gh api "repos/{owner}/{repo}/pulls/$number" --jq '.head.sha' 2>/dev/null)" || [ "$head2" != "$head1" ]; then
        readfail="${readfail:-the head moved while the changed files were read}"
    fi
    prefix="def wf: \"$CI_WORKFLOW\"; def runs: [${run_ids}]; def basechg: \"$basechg\"; "
    if ! out="$(gh pr view "$number" --json statusCheckRollup,isDraft,mergeable,baseRefName,author,reviews,headRefOid --jq "$prefix$JQ" 2>/dev/null)"; then
        printf 'pr-merge: gh could not read PR #%s (is gh installed and logged in?)\nFix: gh auth status\n' "$number" >&2
        return 1
    fi
    draft="" mergeable="" base="" failing="" pending="" ambiguous="" changes_passed=0 shape_passed=0 approvals="" author="" head=""
    doors="" nfiles=0
    while IFS= read -r line; do
        case "$line" in
        draft=*) draft="${line#draft=}" ;;
        mergeable=*) mergeable="${line#mergeable=}" ;;
        base=*) base="${line#base=}" ;;
        failing=*) failing="${line#failing=}" ;;
        pending=*) pending="${line#pending=}" ;;
        ambiguous=*) ambiguous="${line#ambiguous=}" ;;
        changes_passed=*) changes_passed="${line#changes_passed=}" ;;
        shape_passed=*) shape_passed="${line#shape_passed=}" ;;
        approvals=*) approvals="${line#approvals=}" ;;
        author=*) author="${line#author=}" ;;
        head=*) head="${line#head=}" ;;
        esac
    done <<EOF
$out
EOF
    [ "$head" = "$head1" ] || readfail="${readfail:-the head moved while the pull request was read}"
    nfiles=0
    while IFS= read -r path; do
        case "$path" in
        "f "?*) nfiles=$((nfiles + 1)) ;;
        "p "?*) ;;
        *) continue ;;
        esac
        path="${path#[fp] }"
        if match_doors "$path"; then doors="${doors:+$doors, }$path"; fi
    done <<EOF
$files_out
EOF
    # GitHub lists at most 3000 files: a pull request that long cannot be judged
    if [ "$nfiles" -ge "$MAX_FILES" ]; then readfail="${readfail:-the pull request has too many files to judge}"; fi
    [ "$nfiles" -gt 0 ] || readfail="${readfail:-the changed files of this pull request came back empty}"
    return 0
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

    [ -z "$readfail" ] || refuse "$readfail, so the pull request cannot be judged" "gh auth status"
    [ "$base" = "$DEFAULT_BRANCH" ] || refuse "the base of this pull request is $(clean "$base"), not the default branch $DEFAULT_BRANCH" "gh pr edit $number --base $DEFAULT_BRANCH"
    [ -z "$otherprs" ] || refuse "the head commit also belongs to another pull request ($(clean "$otherprs")), so the runs of this head cannot be told from that pull request's" "close the other pull request or push a new commit to this branch, then run $wait_fix"
    [ "$draft" != "true" ] || refuse "the PR is a draft" "gh pr ready $number"
    [ -z "$failing" ] || refuse "failing check: $(clean "$failing")" "gh pr checks $number"
    [ -z "$pending" ] || refuse "pending check: $(clean "$pending")" "$wait_fix"
    [ -z "$ambiguous" ] || refuse "check reported by more than one workflow or app (a PR may add a workflow that emits the same name): $(clean "$ambiguous")" "gh pr checks $number"
    [ "$changes_passed" -ge 1 ] || refuse "the changes check has not passed from the workflow $CI_WORKFLOW on this head, so CI has not run" "$wait_fix"
    [ "$shape_passed" -ge 1 ] || refuse "the pr-shape check has not passed from the workflow $CI_WORKFLOW on this head" "$wait_fix"
    case "$mergeable" in
    MERGEABLE) ;;
    CONFLICTING)
        refuse "merge conflicts with the base branch" "on your own branch run: git fetch origin && git merge origin/$DEFAULT_BRANCH, resolve the conflicts, push, then run bash scripts/pr-merge.sh --wait $number from a $DEFAULT_BRANCH checkout"
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
        if [ "$oddseen" -eq 1 ]; then
            reviewer_fix="ask a second person to approve PR $number (a file name with a byte outside printable ASCII can collide with a guarded path on a case-insensitive disk), then run $wait_fix"
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
