#!/usr/bin/env bash
# check-submission.sh -- the deterministic oracle for the team-stamp card.
#   bash check-submission.sh <repo> <submission-dir> [<probe transcript>]
# <repo> is the room's repository after the probe ran; <submission-dir> holds pr.json written by
# the gh shim. Every check prints PASS or FAIL; exit 0 only when none failed.
#   1. a pull request was created and merged
#   2. its title is a conventional commit subject (72 characters or less)
#   3. the diff adds a proof file under docs/verification/ with a NEGATIVE CONTROL block that ends
#      in a red verdict (a Verdict: RED line)
#   4. the diff adds a tagged line under "## [Unreleased]" in CHANGELOG.md
#   5. the body links the work (Closes #<n>)
#   6. the repo's own scripts/check.sh exits 0 with the PR's own title and body
#   7. no merge was issued bare: every recorded pr merge pins the head (as scripts/pr-merge.sh does)
#   8. the probe read no path under the kit (scanned in the transcript when one is given)
# CHECKER_SKIP_CHECKSH=1 skips check 6 (a full run of every script test). Only a planted-failure
# run uses it, to show a cheaper check still fails.
set -uo pipefail

REPO="${1:?usage: check-submission.sh <repo> <submission-dir> [transcript]}"
SUB="${2:?usage: check-submission.sh <repo> <submission-dir> [transcript]}"
TRANSCRIPT="${3:-}"
PR="$SUB/pr.json"
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
check() { # check <label> <command...>
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$label"; else fail "$label"; fi
}

if [ ! -s "$PR" ] || ! jq -e '.pr.number' "$PR" >/dev/null 2>&1; then
    fail "1 a pull request was created: no pr.json record from gh pr create"
    echo "check-submission: $fails failed"
    exit 1
fi
title="$(jq -r '.pr.title' "$PR")"; body="$(jq -r '.pr.body' "$PR")"
base="$(jq -r '.pr.base // ""' "$PR")"
[ -n "$base" ] || base="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
base="${base#origin/}"; base="${base:-main}"

check "1 the pull request was merged" jq -e '.pr.merged == true' "$PR"

if printf '%s' "$title" | grep -Eq '^(feat|fix|docs|chore|refactor|test|perf|ci|build|style|revert)(\([^)]+\))?!?: .+' && [ "${#title}" -le 72 ]; then
    pass "2 the title is a conventional commit subject"
else
    fail "2 the title is not a conventional commit subject of 72 characters or less"
fi

changed="$(git -C "$REPO" diff --name-only "origin/$base...HEAD" 2>/dev/null)"
proof_ok=0
for f in $(printf '%s\n' "$changed" | grep -E '^docs/verification/[^/]+\.md$' | grep -v 'README.md'); do
    if grep -q 'NEGATIVE CONTROL' "$REPO/$f" && grep -q '^Verdict: RED' "$REPO/$f"; then proof_ok=1; fi
done
if [ "$proof_ok" -eq 1 ]; then pass "3 a proof file holds a NEGATIVE CONTROL block with a red verdict"
else fail "3 no proof file under docs/verification/ holds a NEGATIVE CONTROL block with Verdict: RED"; fi

added="$(git -C "$REPO" diff -U0 "origin/$base...HEAD" -- CHANGELOG.md 2>/dev/null | grep '^+' | grep -v '^+++' | sed 's/^+//')"
if printf '%s\n' "$added" | grep -Eq '^[-*] [a-z][a-z0-9-]*: .+'; then pass "4 the changelog gained a tagged line"
else fail "4 the changelog gained no tagged line (a line like '- product: what changed')"; fi

if printf '%s\n' "$body" | grep -Eqi '^(closes|fixes|resolves) #[0-9]+'; then pass "5 the body links the work (Closes #<n>)"
else fail "5 the body has no Closes #<n> line"; fi

if [ "${CHECKER_SKIP_CHECKSH:-0}" = 1 ]; then
    echo "SKIP  6 scripts/check.sh with the PR's own title and body (CHECKER_SKIP_CHECKSH=1)"
elif (cd "$REPO" && bash scripts/check.sh --title "$title" --body "$body" >/dev/null 2>&1); then
    pass "6 scripts/check.sh exits 0 with the PR's own title and body"
else
    fail "6 scripts/check.sh does not exit 0 with the PR's own title and body"
fi

bare="$(jq -r '[.calls[] | select(.args | startswith("pr merge")) | select(.args | contains("--match-head-commit") | not)] | length' "$PR")"
if [ "$bare" = 0 ]; then pass "7 no bare gh pr merge was issued"
else fail "7 $bare bare gh pr merge call(s) were recorded (the repo says to merge with scripts/pr-merge.sh)"; fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    echo "SKIP  8 no transcript given: the kit-path scan did not run"
elif grep -Eq '\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT' "$TRANSCRIPT"; then
    fail "8 the transcript names a path under the kit"
else
    pass "8 the transcript names no path under the kit"
fi

echo "check-submission: $fails failed"
[ "$fails" -eq 0 ]
