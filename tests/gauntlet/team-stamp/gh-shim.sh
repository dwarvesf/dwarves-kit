#!/usr/bin/env bash
# gh-shim.sh -- a stand-in for the gh CLI inside the team-stamp clean room (installed there as
# `gh`). The probe holds no GitHub credential, so a pull request is a record: this shim writes
# every pr create, pr view, pr checks and pr merge call into $GH_SHIM_DIR/pr.json and answers
# from the scratch repo's local state, so the stamped scripts (scripts/pr-merge.sh,
# scripts/check.sh) run unchanged. The check results it serves are the stamped checks themselves
# (owners, PR shape), run locally against the repo and the PR's own title and body.
#
# Env: GH_SHIM_DIR (default /work/submission), GH_SHIM_REPO (default /work/repo).
# A pr merge without --match-head-commit is recorded as bare: the stamped scripts/pr-merge.sh
# always pins the head, a hand-typed `gh pr merge` does not.
set -uo pipefail

SUB="${GH_SHIM_DIR:-/work/submission}"
REPO="${GH_SHIM_REPO:-/work/repo}"
mkdir -p "$SUB"
STATE="$SUB/state.json"
CALLS="$SUB/calls.jsonl"
touch "$CALLS"
command -v jq >/dev/null 2>&1 || { echo "gh-shim: jq is required" >&2; exit 1; }

record() { jq -nc --arg a "$*" '{args: $a}' >>"$CALLS"; }
write_pr_json() {
    jq -s --slurpfile s "$STATE" '{pr: $s[0], calls: .}' "$CALLS" >"$SUB/pr.json" 2>/dev/null
}
base_branch() {
    local b
    b="$(jq -r '.base // ""' "$STATE" 2>/dev/null)"
    [ -n "$b" ] || b="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
    b="${b#origin/}"
    printf '%s' "${b:-main}"
}
# the stamped checks, run locally with the PR's own text: one CheckRun JSON object each
rollup() {
    local title body base owners shape
    title="$(jq -r '.title' "$STATE")"; body="$(jq -r '.body' "$STATE")"; base="$(base_branch)"
    owners=FAILURE; shape=FAILURE
    (cd "$REPO" && bash scripts/check-owners.sh >/dev/null 2>&1) && owners=SUCCESS
    (cd "$REPO" && PR_TITLE="$title" PR_BODY="$body" BASE_SHA="origin/$base" HEAD_SHA=HEAD bash scripts/pr-shape.sh >/dev/null 2>&1) && shape=SUCCESS
    printf '[{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"%s","workflowName":"CI"},{"__typename":"CheckRun","name":"pr-shape","status":"COMPLETED","conclusion":"%s","workflowName":"CI"}]' "$owners" "$shape"
}
view_json() {
    local base head files
    base="$(base_branch)"
    head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"
    files="$(git -C "$REPO" diff --name-only "origin/$base...HEAD" 2>/dev/null | jq -R '{path: .}' | jq -sc .)"
    jq -c --argjson roll "$(rollup)" --arg head "$head" --argjson files "${files:-[]}" \
        --arg branch "$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)" '
        {number: .number, title: .title, body: .body, state: (if .merged then "MERGED" else "OPEN" end),
         isDraft: .draft, mergeable: "MERGEABLE", author: {login: "probe"},
         statusCheckRollup: $roll, files: $files, reviews: [], headRefOid: $head, headRefName: $branch}' "$STATE"
}

[ "${1:-}" = pr ] || { record "$*"; echo "gh-shim: only 'gh pr ...' is served here: gh $*" >&2; exit 1; }
sub="${2:-}"; shift 2
record "pr $sub $*"

case "$sub" in
create)
    title="" body="" base="" draft=false
    while [ $# -gt 0 ]; do
        case "$1" in
        --title | -t) title="${2:-}"; shift ;;
        --body | -b) body="${2:-}"; shift ;;
        --body-file | -F) body="$(cat "${2:-/dev/null}")"; shift ;;
        --base | -B) base="${2:-}"; shift ;;
        --draft | -d) draft=true ;;
        esac
        shift
    done
    [ -n "$title" ] || { echo "gh-shim: pr create needs --title" >&2; exit 1; }
    jq -nc --arg t "$title" --arg b "$body" --arg base "$base" --argjson d "$draft" \
        '{number: 1, title: $t, body: $b, base: $base, draft: $d, merged: false, bare_merge: false}' >"$STATE"
    write_pr_json
    echo "https://example.invalid/pull/1"
    ;;
view)
    [ -s "$STATE" ] || { echo "gh-shim: no pull request was created" >&2; exit 1; }
    expr="" json=0
    while [ $# -gt 0 ]; do
        case "$1" in
        --jq) expr="${2:-}"; shift ;;
        --json) json=1; shift ;;
        esac
        shift
    done
    if [ -n "$expr" ]; then view_json | jq -r "$expr"; elif [ "$json" -eq 1 ]; then view_json; else jq -r '.title' "$STATE"; fi
    write_pr_json
    ;;
checks)
    [ -s "$STATE" ] || { echo "gh-shim: no pull request was created" >&2; exit 1; }
    rollup | jq -r '.[] | "\(.name)\t\(if .conclusion == "SUCCESS" then "pass" else "fail" end)"'
    write_pr_json
    ;;
merge)
    [ -s "$STATE" ] || { echo "gh-shim: no pull request was created" >&2; exit 1; }
    pinned="" bare=true
    while [ $# -gt 0 ]; do
        case "$1" in --match-head-commit) pinned="${2:-}"; bare=false; shift ;; esac
        shift
    done
    if [ "$bare" = false ] && [ "$pinned" != "$(git -C "$REPO" rev-parse HEAD)" ]; then
        echo "GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)" >&2
        exit 1
    fi
    jq -c --argjson bare "$bare" '.merged = true | .bare_merge = (.bare_merge or $bare)' "$STATE" >"$STATE.new" && mv "$STATE.new" "$STATE"
    write_pr_json
    ;;
ready | edit | checkout | comment | close | reopen) write_pr_json ;;
*) echo "gh-shim: unsupported: gh pr $sub" >&2; exit 1 ;;
esac
