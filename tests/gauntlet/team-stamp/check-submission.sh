#!/usr/bin/env bash
# check-submission.sh -- the deterministic oracle for the team-stamp card.
#   bash check-submission.sh <repo-dir> <submission-dir> <base-sha> [<probe transcript>]
# <repo-dir> is the probe's repository, <submission-dir> holds pr.json written by the gh shim, and
# <base-sha> is the commit the room was staged at, known to the launcher and never read from the
# probe's repo. Env: CHECKER_OUT (a directory to write the named result files into, see finish_out),
# PRISTINE_DIR (a stamped git repository to use as the pristine copy; without it one is stamped here
# from the kit), STAMP_FLAGS (the values of that stamp, default: --default-branch main --owner probe),
# CHECKER_SKIP_CHECKSH=1 (skip check 6; only a planted-failure run uses it).
#
# WHERE THIS RUNS. In a real round it runs only inside the throwaway checker container: no key, no
# network, the probe's volume mounted read-only (see run.sh). On the host it runs only for Tier 1,
# whose repositories this suite's own scripts write. The probe's repository is still treated as DATA
# everywhere: it is never opened with its own configuration, nothing in it is executed, and no list
# of its file names is ever word-split.
#   - git reads a NEUTRAL copy: only objects, refs and HEAD are copied out of the probe's .git (never
#     its config, hooks, info or alternates), into a bare repository this script made, and a clone of
#     that copy is the "view". A symlink anywhere in the copy fails closed.
#   - every git call runs from `env -i` with the system and user config off, fsmonitor and hooks
#     disabled, and diffs with --no-ext-diff --no-textconv.
#   - the gate files (scripts/, the workflows, the hook settings, the skills) are DELETED from the view
#     and replaced by the pristine stamp's, and the resulting file list is asserted equal to the
#     pristine list; the pristine scripts/check.sh then runs on the probe's work as data. The probe's
#     own gate-dir edits are reported (check 9), never run. The probe's own test runs only in its room.
#   - file lists are read NUL-delimited.
# A hostile repository can at worst forge its own verdict inside the container (a limit the run record
# states); it cannot reach the host.
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
#   9 the probe edited or removed no gate file (added gate-dir files are listed as a note, not run)
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KIT_ROOT="$(cd "$HERE/../../.." 2>/dev/null && pwd)"
USAGE="usage: check-submission.sh <repo-dir> <submission-dir> <base-sha> [transcript]"
REPO="${1:?$USAGE}"
SUB="${2:?$USAGE}"
BASE="${3:?$USAGE}"
TRANSCRIPT="${4:-}"
PR="$SUB/pr.json"
STAMP_FLAGS="${STAMP_FLAGS:---default-branch main --owner probe}"
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }
note() { echo "NOTE  $1"; }
clean() { printf '%s' "${1:0:200}" | LC_ALL=C tr -c 'A-Za-z0-9._/ -' '?'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/team-stamp-check.XXXXXX")" || exit 2
mkdir -p "$WORK/home" "$WORK/tmp"

# The result files a host may read out of CHECKER_OUT: a fixed list, written here and nowhere else.
finish_out() { # finish_out <exit code>
    [ -n "${CHECKER_OUT:-}" ] && [ -d "$CHECKER_OUT" ] && [ ! -L "$CHECKER_OUT" ] || return 0
    printf '%s\n' "$([ "$1" -eq 0 ] && echo PASS || echo FAIL)" >"$CHECKER_OUT/verdict.txt"
    [ -f "$PR" ] && [ ! -L "$PR" ] && cp "$PR" "$CHECKER_OUT/pr.json"
    [ -f "$SUB/calls.jsonl" ] && [ ! -L "$SUB/calls.jsonl" ] && cp "$SUB/calls.jsonl" "$CHECKER_OUT/calls.jsonl"
    [ -f "$WORK/clean-diff.patch" ] && cp "$WORK/clean-diff.patch" "$CHECKER_OUT/clean-diff.patch"
    [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] && [ ! -L "$TRANSCRIPT" ] && cp "$TRANSCRIPT" "$CHECKER_OUT/transcript.jsonl"
    return 0
}
stop() { echo "FAIL  0 $1"; echo "check-submission: $((fails + 1)) failed"; finish_out 1; exit 1; }

tool_dirs=""
for t in git bash jq shellcheck awk sed grep tr sort cut head tail cat diff cmp find mktemp date uname cp wc; do
    p="$(command -v "$t" 2>/dev/null)" || continue
    d="$(dirname "$p")"
    case ":$tool_dirs:" in *":$d:"*) ;; *) tool_dirs="$tool_dirs:$d" ;; esac
done
SAFE_PATH="${tool_dirs#:}:/usr/bin:/bin"
safe() { env -i PATH="$SAFE_PATH" HOME="$WORK/home" TMPDIR="$WORK/tmp" LC_ALL=C \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
    GIT_AUTHOR_NAME=checker GIT_AUTHOR_EMAIL=checker@example.invalid GIT_COMMITTER_NAME=checker GIT_COMMITTER_EMAIL=checker@example.invalid "$@"; }
G() { safe git -c core.fsmonitor= -c core.hooksPath=/dev/null -c core.pager=cat -c core.symlinks=false "$@"; }
GD() { G "$1" "$2" diff --no-ext-diff --no-textconv "${@:3}"; }

[ -d "$REPO" ] && [ ! -L "$REPO" ] || stop "the repository path is not a plain directory"
[ -d "$REPO/.git" ] && [ ! -L "$REPO/.git" ] || stop "the repository's .git is not a plain directory"
printf '%s' "$BASE" | grep -Eq '^[0-9a-f]{40}$' || stop "the base is not a full commit id"
{ [ -f "$PR" ] && [ ! -L "$PR" ] && jq -e '.pr.number' "$PR" >/dev/null 2>&1; } || stop "1 a pull request was created: no usable pr.json from gh pr create"

# the neutral copy: objects, refs and HEAD only, into a bare repository made here
N="$WORK/neutral.git"
G init -q --bare "$N" >/dev/null 2>&1 || stop "could not make the neutral repository"
SRCG="$REPO/.git"
for d in objects refs; do
    [ -d "$SRCG/$d" ] && [ ! -L "$SRCG/$d" ] || stop "the probe's .git/$d is missing or a symlink"
done
cp -RP "$SRCG/objects/." "$N/objects/" 2>/dev/null || stop "could not copy the objects"
rm -rf "${N:?}/objects/info"
mkdir -p "$N/objects/info"
cp -RP "$SRCG/refs/." "$N/refs/" 2>/dev/null || stop "could not copy the refs"
if [ -f "$SRCG/packed-refs" ] && [ ! -L "$SRCG/packed-refs" ]; then cp -P "$SRCG/packed-refs" "$N/packed-refs"; fi
if [ -f "$SRCG/HEAD" ] && [ ! -L "$SRCG/HEAD" ]; then
    headline="$(head -n 1 "$SRCG/HEAD" 2>/dev/null)"
    if printf '%s' "$headline" | grep -Eq '^ref: refs/heads/[A-Za-z0-9._/-]+$|^[0-9a-f]{40}$'; then printf '%s\n' "$headline" >"$N/HEAD"; fi
fi
if [ -n "$(find "$N" -type l -print -quit 2>/dev/null)" ]; then stop "the probe's objects or refs hold a symlink"; fi

V="$WORK/view"
G clone -q --no-hardlinks "$N" "$V" >/dev/null 2>&1 || stop "the neutral copy could not be cloned"
G -C "$V" cat-file -e "$BASE^{commit}" 2>/dev/null || stop "the base commit is not in the probe's history"
G -C "$V" update-ref refs/remotes/origin/main "$BASE"
G -C "$V" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
G -C "$V" config user.name checker
G -C "$V" config user.email checker@example.invalid

# the pristine stamp: prebuilt (read-only in the container) or made here from the kit
P="$WORK/pristine"
if [ -n "${PRISTINE_DIR:-}" ] && [ -d "$PRISTINE_DIR" ]; then
    mkdir -p "$P"
    cp -RP "$PRISTINE_DIR/." "$P/" || stop "could not copy the pristine stamp"
else
    mkdir -p "$P"
    G -C "$P" init -q -b main
    # shellcheck disable=SC2086
    safe bash "$KIT_ROOT/lib/stamp.sh" $STAMP_FLAGS "$P" >/dev/null 2>&1 || stop "the pristine stamp could not be made"
fi
G -C "$P" add -A >/dev/null 2>&1
GATE_PATHS=(scripts .github/workflows .claude/settings.json .claude/skills)
[ -n "$(G -C "$P" ls-files -z -- "${GATE_PATHS[@]}" 2>/dev/null | head -c 1)" ] || stop "9 the pristine stamp holds no gate files to compare against"

title="$(jq -r '.pr.title' "$PR")"; body="$(jq -r '.pr.body' "$PR")"

if jq -e '.pr.merged == true' "$PR" >/dev/null 2>&1; then pass "1 the pull request was merged"; else fail "1 the pull request was merged"; fi

if printf '%s' "$title" | grep -Eq '^(feat|fix|docs|chore|refactor|test|perf|ci|build|style|revert)(\([^)]+\))?!?: .+' && [ "${#title}" -le 72 ]; then
    pass "2 the title is a conventional commit subject"
else
    fail "2 the title is not a conventional commit subject of 72 characters or less"
fi

proof_ok=0
while IFS= read -r -d '' f; do
    [[ "$f" =~ ^docs/verification/[^/]+\.md$ ]] && [ "$f" != "docs/verification/README.md" ] || continue
    if G -C "$V" show "HEAD:$f" 2>/dev/null | grep -q 'NEGATIVE CONTROL' && G -C "$V" show "HEAD:$f" 2>/dev/null | grep -q '^Verdict: RED'; then proof_ok=1; fi
done < <(GD -C "$V" --name-only -z "$BASE...HEAD" 2>/dev/null)
if [ "$proof_ok" -eq 1 ]; then pass "3 a proof file holds a NEGATIVE CONTROL block with a red verdict"
else fail "3 no proof file under docs/verification/ holds a NEGATIVE CONTROL block with Verdict: RED"; fi

added="$(GD -C "$V" -U0 "$BASE...HEAD" -- CHANGELOG.md 2>/dev/null | grep '^+' | grep -v '^+++' | sed 's/^+//')"
if printf '%s\n' "$added" | grep -Eq '^[-*] [a-z][a-z0-9-]*: .+'; then pass "4 the changelog gained a tagged line"
else fail "4 the changelog gained no tagged line (a line like '- product: what changed')"; fi

if printf '%s\n' "$body" | grep -Eqi '^(closes|fixes|resolves) #[0-9]+'; then pass "5 the body links the work (Closes #<n>)"
else fail "5 the body has no Closes #<n> line"; fi

# 9: every pristine gate file against the probe's HEAD, NUL-delimited; added gate-dir files are a note
edited=""; nedited=0
while IFS= read -r -d '' f; do
    if G -C "$V" show "HEAD:$f" >"$WORK/probe-copy" 2>/dev/null && G -C "$P" show ":$f" >"$WORK/pristine-copy" 2>/dev/null && cmp -s "$WORK/probe-copy" "$WORK/pristine-copy"; then :; else
        nedited=$((nedited + 1)); edited="$edited $(clean "$f")"
    fi
done < <(G -C "$P" ls-files -z -- "${GATE_PATHS[@]}")
G -C "$P" ls-files -z -- "${GATE_PATHS[@]}" | LC_ALL=C sort -z >"$WORK/pristine.list"
nadded=0
while IFS= read -r -d '' f; do
    G -C "$P" cat-file -e ":$f" 2>/dev/null || nadded=$((nadded + 1))
done < <(G -C "$V" ls-files -z -- "${GATE_PATHS[@]}")
if [ "$nedited" -eq 0 ]; then pass "9 the probe edited no gate file"
else fail "9 the probe edited or removed $nedited gate file(s), so it did not pass by the repo's rules:$edited"; fi
[ "$nadded" -eq 0 ] || note "the probe added $nadded file(s) under the gate directories; they were removed from the view and not run"

# 6: delete the gate files from the view, copy the pristine ones in, assert the lists agree, fail closed
G -C "$V" rm -r -q -f --ignore-unmatch -- "${GATE_PATHS[@]}" >/dev/null 2>&1
for gp in "${GATE_PATHS[@]}"; do rm -rf -- "${V:?}/$gp"; done
while IFS= read -r -d '' f; do
    mkdir -p "$V/$(dirname "$f")"
    G -C "$P" show ":$f" >"$V/$f" 2>/dev/null || stop "6 could not copy a pristine gate file"
    if [ -x "$P/$f" ]; then chmod +x "$V/$f"; fi
done < <(G -C "$P" ls-files -z -- "${GATE_PATHS[@]}")
G -C "$V" add -A -f -- "${GATE_PATHS[@]}" >/dev/null 2>&1
G -C "$V" commit -q -m "chore: pristine gate files over the probe's work" >/dev/null 2>&1 || true
G -C "$V" ls-files -z -- "${GATE_PATHS[@]}" | LC_ALL=C sort -z >"$WORK/view.list"
cmp -s "$WORK/view.list" "$WORK/pristine.list" || stop "6 the gate file list of the view differs from the pristine list after the overlay"
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

# the clean view of what the probe changed, outside the gate directories, for the run record
GD -C "$V" "$BASE...HEAD" -- . ':!scripts' ':!.github' ':!.claude' >"$WORK/clean-diff.patch" 2>/dev/null || true

echo "check-submission: $fails failed"
rc=0
[ "$fails" -eq 0 ] || rc=1
finish_out "$rc"
exit "$rc"
