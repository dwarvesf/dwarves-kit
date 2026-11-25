#!/usr/bin/env bash
# check.sh - the one local command before a push. It runs the checks CI runs (.github/workflows/ci.yml,
# jobs changes and pr-shape) with the same inputs, so a red CI run is a red local run first.
# Needs git and bash. No token, no network.
#
#   bash scripts/check.sh                                       owners, PR shape, the script tests
#   bash scripts/check.sh --title 'feat(x): y' --body 'Closes #12'
#   bash scripts/check.sh --title 'feat(x): y' --body-file body.txt
#   bash scripts/check.sh --help
#
# Twin set: the gate commands. ci.yml carries the same list at its top and runs each of them with
# the same inputs. Keep the two lists, and the commands below, in step with ci.yml.
#   twin: check-owners.sh
#   twin: pr-shape.sh env PR_TITLE PR_BODY BASE_SHA HEAD_SHA
# The generated script tests below are not in CI (a job that runs a pull request's own code does not
# belong on the gate runner); check.sh runs them on your machine.
#
# PR title and body. The first source that applies wins:
#   1. arguments: --title, --body or --body-file
#   2. environment: PR_TITLE, PR_BODY or PR_BODY_FILE (the names pr-shape.sh reads)
#   3. gh pr view, only when gh is on PATH and steps 1 and 2 gave no title and no body. It reads the
#      open PR of this branch with your own gh login; this script sets no token and the no-gh path
#      needs none.
#   4. otherwise the title is the first commit subject on the branch and the body is empty, so a rule
#      that reads the body (Closes #n, no-proof:, no-changelog:) fails here as it would in CI with an
#      empty body. Pass --body to give it.
# BASE_SHA and HEAD_SHA default to the merge base with origin/{{DEFAULT_BRANCH}} and to HEAD; set them
# to check another range. PR shape reads commits, so commit first.
#
# Output: "ok    <check>" lines, the checks' own lines, and "check: N failed, M passed" last. Every
# failed step prints exactly two lines on stderr, "check: <the rule>" then "Fix: <a command>".
# Exit 0 when no step failed, 1 when one or more failed, 2 for bad usage or no base revision.
#
# Safety: a PR title, a body, a file name and a test's output are attacker-chosen text. A value reaches
# an output line only through clean() (every character outside letters, digits and ._/@- and space
# becomes ?) or, for a test's own output behind "  | ", through show(), and reaches a Fix line only
# when safe_arg() accepts it. bash 3.2 safe.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

DEFAULT_BRANCH='{{DEFAULT_BRANCH}}'
self='^\.github/workflows/ci\.yml$'
product_re='{{PRODUCT_ERE}}'

clean() { printf '%s' "${1:0:80}" | LC_ALL=C tr -c 'A-Za-z0-9._/@ -' '?'; }
# show: the same filter for a test's own output, which keeps : , = ( ) # + % and brackets so a summary line reads
# normally; a $, a quote and a backtick still become ?, and a line is always printed behind "  | ".
show() { printf '%s' "${1:0:200}" | LC_ALL=C tr -c 'A-Za-z0-9._/@ :,=#()+%[]-' '?'; }
safe_re='^[A-Za-z0-9._/@-]+$'
safe_arg() { case "$1" in -* | "") return 1 ;; esac; [[ "$1" =~ $safe_re ]]; }
strip() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }

fails=0
passed=0
ok() {
    passed=$((passed + 1))
    printf 'ok    %s\n' "$1"
}
note() { printf 'note  %s\n' "$1"; }
detail() { printf '  | %s\n' "$(show "$1")"; }
# refuse <rule> <fix>: a failed step; the two-line refusal on stderr.
refuse() {
    fails=$((fails + 1))
    printf 'check: %s\nFix: %s\n' "$(strip "$1")" "$(strip "$2")" >&2
}
# die <rule> <fix>: bad usage or no base revision; the two-line refusal, then exit 2.
die() {
    printf 'check: %s\nFix: %s\n' "$(strip "$1")" "$(strip "$2")" >&2
    exit 2
}
usage() {
    awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
}

# ---- arguments
title="" body="" have_title=0 have_body=0 body_file="" title_src="" body_src=""
while [ $# -gt 0 ]; do
    case "$1" in
    -h | --help)
        usage
        exit 0
        ;;
    --title)
        [ $# -ge 2 ] || die "--title needs a value" "bash scripts/check.sh --title 'feat(x): y'"
        title="$2"
        have_title=1
        title_src="the --title argument"
        shift
        ;;
    --body)
        [ $# -ge 2 ] || die "--body needs a value" "bash scripts/check.sh --body 'Closes #12'"
        [ -z "$body_file" ] || die "give --body or --body-file, not both" "bash scripts/check.sh --body-file <file>"
        body="$2"
        have_body=1
        body_src="the --body argument"
        shift
        ;;
    --body-file)
        [ $# -ge 2 ] || die "--body-file needs a file name" "bash scripts/check.sh --body-file <file>"
        [ "$have_body" -eq 0 ] || die "give --body or --body-file, not both" "bash scripts/check.sh --body-file <file>"
        body_file="$2"
        shift
        ;;
    *) die "unknown option $(clean "$1")" "bash scripts/check.sh --help" ;;
    esac
    shift
done
read_body_file() { # read_body_file <path> <source label>
    [ -f "$1" ] && [ -r "$1" ] || die "the body file $(clean "$1") is not a readable file" "bash scripts/check.sh --body-file <a readable file>"
    body="$(cat "$1")"
    have_body=1
    body_src="$2"
}
if [ -n "$body_file" ]; then read_body_file "$body_file" "the --body-file argument"; fi

# ---- environment
if [ "$have_title" -eq 0 ] && [ -n "${PR_TITLE-}" ]; then
    title="$PR_TITLE"
    have_title=1
    title_src="PR_TITLE"
fi
if [ "$have_body" -eq 0 ]; then
    if [ -n "${PR_BODY_FILE-}" ]; then
        read_body_file "$PR_BODY_FILE" "PR_BODY_FILE"
    elif [ "${PR_BODY+set}" = set ]; then
        body="$PR_BODY"
        have_body=1
        body_src="PR_BODY"
    fi
fi

# ---- the range
git rev-parse --git-dir >/dev/null 2>&1 || die "this is not a git repository" "git init"
resolve() { # resolve <rev>: the commit id, or fail
    case "$1" in -* | "") return 1 ;; esac
    git rev-parse --verify -q "$1^{commit}" 2>/dev/null
}
if [ -n "${BASE_SHA-}" ]; then
    base="$(resolve "$BASE_SHA")" || die "BASE_SHA $(clean "$BASE_SHA") does not resolve in this clone" "git fetch origin $DEFAULT_BRANCH # then unset BASE_SHA or set it to a commit"
else
    base="$(git merge-base "origin/$DEFAULT_BRANCH" HEAD 2>/dev/null)" || die "no merge base with origin/$DEFAULT_BRANCH" "git fetch origin $DEFAULT_BRANCH"
fi
head_ref="${HEAD_SHA:-HEAD}"
head="$(resolve "$head_ref")" || die "HEAD_SHA $(clean "$head_ref") does not resolve in this clone" "git status --short # then unset HEAD_SHA or set it to a commit"
files="$(git -c core.quotepath=off diff --name-only "$base...$head" 2>/dev/null)"

if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    note "uncommitted changes are not checked: PR shape reads commits, so commit first"
fi
if [ -z "$files" ]; then
    note "no committed change against origin/$DEFAULT_BRANCH yet"
fi

# ---- the PR text, when the arguments and the environment gave none
if [ "$have_title" -eq 0 ] && [ "$have_body" -eq 0 ] && command -v gh >/dev/null 2>&1; then
    if t="$(gh pr view --json title --jq .title 2>/dev/null </dev/null)" && [ -n "$t" ]; then
        title="$t"
        have_title=1
        title_src="the open PR (gh pr view)"
        body="$(gh pr view --json body --jq .body 2>/dev/null </dev/null || true)"
        have_body=1
        body_src="the open PR (gh pr view)"
    fi
fi
if [ "$have_title" -eq 0 ]; then
    title="$(git log --reverse --format=%s "$base..$head" 2>/dev/null | head -n 1)"
    title_src="the first commit subject on this branch"
fi
if [ "$have_body" -eq 0 ]; then
    body=""
    body_src="empty (nothing was given)"
fi
note "PR title comes from $title_src; the body comes from $body_src"

# ---- 1. every script and workflow has an owner (job changes)
if [ ! -f scripts/check-owners.sh ]; then
    refuse "scripts/check-owners.sh is missing, so owners are not checked" "git checkout origin/$DEFAULT_BRANCH -- scripts/check-owners.sh"
elif bash scripts/check-owners.sh; then
    ok "owners: check-owners.sh passed"
else
    refuse "owners: a script or workflow has no row in OWNERS.md, or a row is broken (the lines above name it)" "bash scripts/check-owners.sh # fix each line above, then run it again"
fi

# ---- 2. PR shape, with the inputs CI gives it (job pr-shape)
if [ ! -f scripts/pr-shape.sh ]; then
    refuse "scripts/pr-shape.sh is missing, so the PR shape is not checked" "git checkout origin/$DEFAULT_BRANCH -- scripts/pr-shape.sh"
elif [ -z "$files" ]; then
    ok "pr-shape: skipped, no commit on this branch yet"
elif PR_TITLE="$title" PR_BODY="$body" PR_BODY_FILE='' BASE_SHA="$base" HEAD_SHA="$head" bash scripts/pr-shape.sh; then
    ok "pr-shape: no check failed"
else
    refuse "pr-shape: a check failed (the lines above name each rule)" "bash scripts/check.sh --title '<the PR title>' --body '<the PR body>' # after you fix each rule above"
fi

# ---- 3. the script tests (job pr-shape)
ran=0
for t in scripts/test-*.sh; do
    [ -f "$t" ] || continue
    ran=$((ran + 1))
    if out="$(bash "$t" 2>&1)"; then
        ok "script test: $(clean "$t") ($(show "$(printf '%s\n' "$out" | tail -n 1)"))"
    else
        while IFS= read -r l; do
            detail "$l"
        done <<EOF
$(printf '%s\n' "$out" | tail -n 15)
EOF
        if safe_arg "$t"; then
            refuse "script test failed: $t" "bash $t # read the FAIL lines, fix the script or its test, run it again"
        else
            refuse "a script test failed: $(clean "$t")" "run each scripts/test-*.sh by hand and fix the one that fails"
        fi
    fi
done
if [ "$ran" -eq 0 ]; then ok "script tests: none in scripts/"; fi

# ---- the path filter of job changes
if grep -Eq "$self|$product_re" <<<"$files"; then
    note "a product path or the workflow changed: CI runs the repo's own build and test jobs for it; run those commands before you push"
fi

printf 'check: %s failed, %s passed\n' "$fails" "$passed"
[ "$fails" -eq 0 ]
