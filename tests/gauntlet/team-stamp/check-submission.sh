#!/usr/bin/env bash
# check-submission.sh -- the deterministic oracle for the team-stamp card.
#   bash check-submission.sh <repo.bundle> <submission-dir> <base-sha> [<probe transcript>]
# <repo.bundle> is a git bundle made INSIDE the room from the probe's repository; <submission-dir>
# holds pr.json written by the gh shim; <base-sha> is the commit the room was staged at, known to
# the launcher and never read from the probe's repo.
#
# TRUST. The probe's repository is untrusted: a model wrote into it, its .git/config and its
# scripts/ included. So this checker (1) never opens that repository: it clones the bundle itself
# into a fresh directory, whose .git/config git writes; (2) runs every git call with the system and
# user config switched off and fsmonitor and hooks disabled and diffs run with --no-ext-diff --no-textconv; (3) never executes a file
# from the probe's tree on this host: the gate scripts it runs (scripts/check.sh and the scripts it
# calls) come from a PRISTINE stamp it makes itself, laid over a copy of the probe's work as data;
# (4) runs nothing the probe wrote (its function's test included: that runs only in the room); and
# (5) starts every host command it runs on probe data from `env -i` with a minimal PATH and an
# empty HOME. A gate file the probe edited is reported as a failed check, not run.
#
# Checks (each prints PASS or FAIL; exit 0 only when none failed):
#   1 a pull request was created and merged
#   2 the title is a conventional commit subject (72 characters or less)
#   3 the diff adds a proof file under docs/verification/ with a NEGATIVE CONTROL block that ends in
#     a red verdict (a Verdict: RED line)
#   4 the diff adds a tagged line under "## [Unreleased]" in CHANGELOG.md
#   5 the body links the work (Closes #<n>)
#   6 the pristine scripts/check.sh exits 0 on the probe's work with the PR's own title and body
#   7 no merge was issued bare: every recorded pr merge pins the head (as scripts/pr-merge.sh does)
#   8 the probe read no path under the kit (scanned in the transcript when one is given)
#   9 the probe edited no gate script (scripts/, the workflows, the hook settings, the skills)
# CHECKER_SKIP_CHECKSH=1 skips check 6 (a full run of every script test). Only a planted-failure run
# uses it, to show a cheaper check still fails. STAMP_FLAGS overrides the values of the pristine stamp
# (default: --default-branch main --owner probe, the values run.sh stamps with).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." && pwd)"
BUNDLE="${1:?usage: check-submission.sh <repo.bundle> <submission-dir> <base-sha> [transcript]}"
SUB="${2:?usage: check-submission.sh <repo.bundle> <submission-dir> <base-sha> [transcript]}"
BASE="${3:?usage: check-submission.sh <repo.bundle> <submission-dir> <base-sha> [transcript]}"
TRANSCRIPT="${4:-}"
PR="$SUB/pr.json"
STAMP_FLAGS="${STAMP_FLAGS:---default-branch main --owner probe}"
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

if [ -d "$BUNDLE" ]; then
    echo "FAIL  0 the submission is a directory, not a bundle: this checker never opens the probe's repository (make the bundle inside the room)"
    echo "check-submission: 1 failed"
    exit 2
fi
[ -f "$BUNDLE" ] || { echo "FAIL  0 no bundle at the given path"; echo "check-submission: 1 failed"; exit 2; }
printf '%s' "$BASE" | grep -Eq '^[0-9a-f]{40}$' || { echo "FAIL  0 the base is not a full commit id"; echo "check-submission: 1 failed"; exit 2; }

# a clean working area and the one way every host command is started
WORK="$(mktemp -d "${TMPDIR:-/tmp}/team-stamp-check.XXXXXX")" || exit 2
mkdir -p "$WORK/home" "$WORK/tmp"
tool_dirs=""
for t in git bash jq shellcheck awk sed grep tr sort cut head tail cat diff cmp find mktemp date uname; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    d="$(dirname "$p")"
    case ":$tool_dirs:" in *":$d:"*) ;; *) tool_dirs="$tool_dirs:$d" ;; esac
done
SAFE_PATH="${tool_dirs#:}:/usr/bin:/bin"
safe() { env -i PATH="$SAFE_PATH" HOME="$WORK/home" TMPDIR="$WORK/tmp" LC_ALL=C \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
    GIT_AUTHOR_NAME=checker GIT_AUTHOR_EMAIL=checker@example.invalid GIT_COMMITTER_NAME=checker GIT_COMMITTER_EMAIL=checker@example.invalid "$@"; }
G() { safe git -c core.fsmonitor= -c core.hooksPath=/dev/null -c core.pager=cat -c core.symlinks=false "$@"; }
# a diff never runs an external diff driver or a textconv filter, whatever any config says
GD() { G "$1" "$2" diff --no-ext-diff --no-textconv "${@:3}"; }

if [ ! -s "$PR" ] || ! jq -e '.pr.number' "$PR" >/dev/null 2>&1; then
    fail "1 a pull request was created: no pr.json record from gh pr create"
    echo "check-submission: $fails failed"
    exit 1
fi

# the probe's work, as data, in a repository this checker created
if ! safe git bundle verify "$BUNDLE" >/dev/null 2>&1; then
    fail "0 the bundle does not verify"
    echo "check-submission: $fails failed"
    exit 1
fi
V="$WORK/view"
if ! G clone -q --no-hardlinks "$BUNDLE" "$V" >/dev/null 2>&1; then
    fail "0 the bundle could not be cloned"
    echo "check-submission: $fails failed"
    exit 1
fi
if ! G -C "$V" cat-file -e "$BASE^{commit}" 2>/dev/null; then
    fail "0 the base commit is not in the probe's history"
    echo "check-submission: $fails failed"
    exit 1
fi
G -C "$V" update-ref refs/remotes/origin/main "$BASE"
G -C "$V" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main

# a pristine stamp, made here from the kit, never from the probe
P="$WORK/pristine"; mkdir -p "$P"
G -C "$P" init -q -b main
# shellcheck disable=SC2086
safe bash "$KIT_ROOT/lib/stamp.sh" $STAMP_FLAGS "$P" >/dev/null 2>&1 || { fail "0 the pristine stamp could not be made"; echo "check-submission: $fails failed"; exit 1; }

title="$(jq -r '.pr.title' "$PR")"; body="$(jq -r '.pr.body' "$PR")"

jq -e '.pr.merged == true' "$PR" >/dev/null 2>&1 && pass "1 the pull request was merged" || fail "1 the pull request was merged"

if printf '%s' "$title" | grep -Eq '^(feat|fix|docs|chore|refactor|test|perf|ci|build|style|revert)(\([^)]+\))?!?: .+' && [ "${#title}" -le 72 ]; then
    pass "2 the title is a conventional commit subject"
else
    fail "2 the title is not a conventional commit subject of 72 characters or less"
fi

changed="$(GD -C "$V" --name-only "$BASE...HEAD" 2>/dev/null)"
proof_ok=0
for f in $(printf '%s\n' "$changed" | grep -E '^docs/verification/[^/]+\.md$' | grep -v 'README.md'); do
    if G -C "$V" show "HEAD:$f" 2>/dev/null | grep -q 'NEGATIVE CONTROL' && G -C "$V" show "HEAD:$f" 2>/dev/null | grep -q '^Verdict: RED'; then proof_ok=1; fi
done
if [ "$proof_ok" -eq 1 ]; then pass "3 a proof file holds a NEGATIVE CONTROL block with a red verdict"
else fail "3 no proof file under docs/verification/ holds a NEGATIVE CONTROL block with Verdict: RED"; fi

added="$(GD -C "$V" -U0 "$BASE...HEAD" -- CHANGELOG.md 2>/dev/null | grep '^+' | grep -v '^+++' | sed 's/^+//')"
if printf '%s\n' "$added" | grep -Eq '^[-*] [a-z][a-z0-9-]*: .+'; then pass "4 the changelog gained a tagged line"
else fail "4 the changelog gained no tagged line (a line like '- product: what changed')"; fi

if printf '%s\n' "$body" | grep -Eqi '^(closes|fixes|resolves) #[0-9]+'; then pass "5 the body links the work (Closes #<n>)"
else fail "5 the body has no Closes #<n> line"; fi

# 9: which gate files differ from the pristine stamp (a missing one counts as different)
G -C "$P" add -A >/dev/null 2>&1
gate_list="$(G -C "$P" ls-files -- scripts .github/workflows .claude/settings.json .claude/skills 2>/dev/null)"
edited=""
for f in $gate_list; do
    G -C "$V" show "HEAD:$f" >"$WORK/probe-copy" 2>/dev/null || { edited="$edited $f"; continue; }
    cmp -s "$WORK/probe-copy" "$P/$f" || edited="$edited $f"
done
if [ -z "$gate_list" ]; then fail "9 the pristine stamp holds no gate files to compare against"
elif [ -z "$edited" ]; then pass "9 the probe edited no gate script"
else fail "9 the probe edited a gate file, so it did not pass by the repo's rules:$(printf '%s' "$edited" | tr -c 'A-Za-z0-9._/ \n-' '?')"; fi

# 6: lay the pristine gate files over a copy of the probe's work, then run the pristine check.sh
G -C "$V" config user.name checker; G -C "$V" config user.email checker@example.invalid
for f in $(G -C "$V" ls-files -- scripts .github/workflows .claude/skills 2>/dev/null); do
    printf '%s\n' "$gate_list" | grep -qxF -- "$f" || G -C "$V" rm -q -f -- "$f" >/dev/null 2>&1
done
for f in $gate_list; do
    mkdir -p "$V/$(dirname "$f")"
    rm -f -- "$V/$f"
    cp -p "$P/$f" "$V/$f"
done
G -C "$V" add -A -- scripts .github/workflows .claude >/dev/null 2>&1
G -C "$V" commit -q -m "chore: pristine gate files over the probe's work" >/dev/null 2>&1 || true
if [ "${CHECKER_SKIP_CHECKSH:-0}" = 1 ]; then
    echo "SKIP  6 scripts/check.sh with the PR's own title and body (CHECKER_SKIP_CHECKSH=1)"
elif (cd "$V" && safe bash scripts/check.sh --title "$title" --body "$body" >/dev/null 2>&1); then
    pass "6 the pristine scripts/check.sh exits 0 on the probe's work with the PR's own title and body"
else
    fail "6 the pristine scripts/check.sh does not exit 0 on the probe's work with the PR's own title and body"
fi

bare="$(jq -r '[.calls[] | select(.args | startswith("pr merge")) | select(.args | contains("--match-head-commit") | not)] | length' "$PR" 2>/dev/null)"
if [ "$bare" = 0 ]; then pass "7 no bare gh pr merge was issued"
else fail "7 ${bare:-?} bare gh pr merge call(s) were recorded (the repo says to merge with scripts/pr-merge.sh)"; fi

if [ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ]; then
    echo "SKIP  8 no transcript given: the kit-path scan did not run"
elif grep -aEq '\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT' "$TRANSCRIPT"; then
    fail "8 the transcript names a path under the kit"
else
    pass "8 the transcript names no path under the kit"
fi

# the clean view of what the probe changed, for the run record (text, no repository)
GD -C "$V" "$BASE...HEAD" -- . ':!scripts' ':!.github' ':!.claude' >"$SUB/clean-diff.patch" 2>/dev/null || true

echo "check-submission: $fails failed"
[ "$fails" -eq 0 ]
