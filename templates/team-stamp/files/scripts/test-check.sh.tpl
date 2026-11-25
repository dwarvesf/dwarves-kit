#!/usr/bin/env bash
# test-check.sh - run check.sh in temp git repos. No network and no token: a fake gh and a PATH with
# no gh at all stand in for it. The owners check and the PR shape check are stubs that log what they
# were given, so a case can say exactly which inputs reached them; when the real pr-shape.sh and
# check-owners.sh sit beside this file, a last group runs check.sh against them. The default branch,
# tags and product paths are the stamped values. Leaves its temp dir behind; the path is printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check.sh"
PRSHAPE="$HERE/pr-shape.sh"
OWNERS_SH="$HERE/check-owners.sh"
CIYML="$HERE/../.github/workflows/ci.yml"
BRANCH='{{DEFAULT_BRANCH}}'
TAGS='{{TAGS}}'
PRODUCT_PATHS='{{PRODUCT_PATHS}}'
PRODUCT_ERE='{{PRODUCT_ERE}}'
unset CI PR_TITLE PR_BODY PR_BODY_FILE BASE_SHA HEAD_SHA || true
T="$(mktemp -d "${TMPDIR:-/tmp}/check-test.XXXXXX")"
echo "test dir: $T"

# P1: the first product tag; PP1: the first product path
P1=""
oldifs="$IFS"
IFS=','
for t in $TAGS; do
    [ "$t" = dev ] && continue
    [ -n "$P1" ] || P1="$t"
done
PP1="${PRODUCT_PATHS%%,*}"
IFS="$oldifs"
[ -n "$P1" ] || { echo "test needs one product tag besides dev in: $TAGS"; exit 1; }
[ -n "$PP1" ] || { echo "test needs a product path in: $PRODUCT_PATHS"; exit 1; }

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

mkbin() { # mkbin <dir> <tool>...: a PATH directory holding only these tools
    local d="$1" t p
    shift
    mkdir -p "$d"
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null || true)"
        case "$p" in /*) ln -sf "$p" "$d/$t" ;; esac
    done
}
TOOLS="bash git awk sed grep mktemp dirname basename mkdir cat printf tr head tail sort cut wc ls cp mv rm date uname env sh cmp diff find xargs readlink chmod touch tee"
mkbin "$T/bin-nogh" $TOOLS
# A fake gh: pr view answers from FAKE_TITLE and FAKE_BODY, or fails when FAKE_NOPR=1. It logs each call.
mkdir -p "$T/bin-gh"
cat >"$T/bin-gh/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"${STUB_DIR:?}/gh.calls"
[ "${FAKE_NOPR-}" = "1" ] && exit 1
case "$*" in
*"--json title"*) printf '%s\n' "${FAKE_TITLE-}" ;;
*"--json body"*) printf '%s\n' "${FAKE_BODY-}" ;;
*) exit 1 ;;
esac
EOF
chmod +x "$T/bin-gh/gh"
mkbin "$T/bin-gh" $TOOLS

R=""
n=0
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.autocrlf=false -c core.hooksPath=/dev/null "$@"; }
put() { # put <path> <content>
    mkdir -p "$R/$(dirname "$1")"
    printf '%s\n' "$2" >"$R/$1"
}
commit_all() { # commit_all <subject>
    g add -A
    g commit -q -m "$1"
}
write_stubs() {
    cat >"$R/scripts/pr-shape.sh" <<'EOF'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
printf '%s' "${PR_TITLE-unset}" >"$d/title"
printf '%s' "${PR_BODY-unset}" >"$d/body"
printf '%s' "${PR_BODY_FILE-unset}" >"$d/body_file"
printf '%s' "${BASE_SHA-unset}" >"$d/base"
printf '%s' "${HEAD_SHA-unset}" >"$d/head"
echo called >>"$d/prshape.calls"
echo "checks: 0 failed, 1 passed"
if [ "${STUB_PRSHAPE_RC:-0}" -ne 0 ]; then
    printf 'pr-shape: stub refusal\nFix: true\n' >&2
fi
exit "${STUB_PRSHAPE_RC:-0}"
EOF
    cat >"$R/scripts/check-owners.sh" <<'EOF'
#!/usr/bin/env bash
echo called >>"${STUB_DIR:?}/owners.calls"
if [ "${STUB_OWNERS_RC:-0}" -ne 0 ]; then
    printf 'check-owners: stub refusal\nFix: true\n' >&2
fi
exit "${STUB_OWNERS_RC:-0}"
EOF
}
# new_repo <stub|real>: a base commit with check.sh and the two scripts it calls, origin/<branch> at
# that commit, then a feature branch
new_repo() {
    n=$((n + 1))
    R="$T/repo$n"
    mkdir -p "$R/scripts"
    git -C "$R" init -q --template=
    git -C "$R" symbolic-ref HEAD "refs/heads/$BRANCH"
    cp "$CHECK" "$R/scripts/check.sh"
    put README.md "readme"
    if [ "$1" = real ]; then
        cp "$PRSHAPE" "$R/scripts/pr-shape.sh"
        cp "$OWNERS_SH" "$R/scripts/check-owners.sh"
        put OWNERS.md "# Owners

| Path | What it does | Owner | Sponsor |
|---|---|---|---|
| \`scripts/check.sh\` | local check | @t | |
| \`scripts/pr-shape.sh\` | PR shape | @t | |
| \`scripts/check-owners.sh\` | owners | @t | |"
        put CHANGELOG.md "# Changelog

## [Unreleased]

- $P1: an existing tagged line"
    else
        write_stubs
    fi
    commit_all base
    g update-ref "refs/remotes/origin/$BRANCH" "$(g rev-parse HEAD)"
    g checkout -q -b feat/x
}
# run_check <name> <PATH dir> [VAR=value ...] [-- args]: stdout in $T/<name>.out, stderr in $T/<name>.err,
# exit in $rc, the stubs' logs in $T/stub-<name>/
run_check() {
    local name="$1" bindir="$2"
    shift 2
    local vars=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        vars+=("$1")
        shift
    done
    [ $# -eq 0 ] || shift
    mkdir -p "$T/stub-$name"
    rc=0
    (cd "$R" && env STUB_DIR="$T/stub-$name" ${vars[@]+"${vars[@]}"} PATH="$bindir" bash scripts/check.sh "$@") \
        >"$T/$name.out" 2>"$T/$name.err" || rc=$?
}
has() { grep -Fq -- "$2" "$T/$1.out" "$T/$1.err"; }
lacks() { ! grep -Fq -- "$2" "$T/$1.out" "$T/$1.err"; }
rc_is() { [ "$rc" -eq "$1" ]; }
file_is() { # file_is <name> <stub file> <expected>: the stub saw exactly this value
    printf '%s' "$3" >"$T/expected"
    cmp -s "$T/expected" "$T/stub-$1/$2"
}
called() { [ -f "$T/stub-$1/$2.calls" ]; }
not_called() { [ ! -f "$T/stub-$1/$2.calls" ]; }
# pairs_ok <name>: stderr is whole pairs, a rule line "<tool>: " then a line "Fix: "
pairs_ok() {
    awk 'NR % 2 == 1 && $0 !~ /^[A-Za-z-]+: / { bad = 1 } NR % 2 == 0 && $0 !~ /^Fix: / { bad = 1 } END { exit (bad || NR == 0 || NR % 2 == 1) }' "$T/$1.err"
}
# run_fixes <name>: run every Fix: line through bash -c in the fixture
run_fixes() {
    local l
    while IFS= read -r l; do
        [ -n "$l" ] || continue
        (cd "$R" && bash -c "${l#Fix: }" </dev/null) >/dev/null 2>&1 || true
    done <<EOF
$(grep '^Fix: ' "$T/$1.err" || true)
EOF
}
no_payload() { ! grep -Eq '\$\(touch|^Fix: rm -rf' "$T/$1.out" "$T/$1.err"; }
no_pwned() { [ -z "$(find "$R" "$T" -name 'PWNED*' 2>/dev/null)" ]; }
sq="'"

# 1. a docs-only branch, nothing passed, no gh at all: the title is the first commit subject
new_repo stub
put docs/a.md "plain doc"
commit_all "docs: add a page"
BASE0="$(g rev-parse "origin/$BRANCH")"
HEAD0="$(g rev-parse HEAD)"
run_check c1 "$T/bin-nogh"
expect "docs-only, gh absent: exit 0" rc_is 0
expect "docs-only: the owners check ran" called c1 owners
expect "docs-only: pr-shape ran" called c1 prshape
expect "docs-only: the title is the first commit subject" file_is c1 title "docs: add a page"
expect "docs-only: the body is empty" file_is c1 body ""
expect "docs-only: BASE_SHA is the merge base with origin/$BRANCH" file_is c1 base "$BASE0"
expect "docs-only: HEAD_SHA is HEAD" file_is c1 head "$HEAD0"
expect "docs-only: PR_BODY_FILE is cleared for pr-shape" file_is c1 body_file ""
expect "docs-only: says where the title came from" has c1 "PR title comes from the first commit subject on this branch"
expect "docs-only: ends with 0 failed" has c1 "check: 0 failed"
expect "docs-only: nothing on stderr" test ! -s "$T/c1.err"
expect "docs-only: no path filter note" lacks c1 "a product path or the workflow changed"

# 2. arguments beat the environment
run_check c2 "$T/bin-nogh" "PR_TITLE=fix: from env" "PR_BODY=env body" -- --title "feat(x): from args" --body "Closes #12"
expect "arguments: exit 0" rc_is 0
expect "arguments: the title reached pr-shape" file_is c2 title "feat(x): from args"
expect "arguments: the body reached pr-shape" file_is c2 body "Closes #12"
expect "arguments: says so" has c2 "PR title comes from the --title argument; the body comes from the --body argument"
# 3. the environment alone
run_check c3 "$T/bin-nogh" "PR_TITLE=fix: from env" "PR_BODY=Closes #4"
expect "environment: the title reached pr-shape" file_is c3 title "fix: from env"
expect "environment: the body reached pr-shape" file_is c3 body "Closes #4"
expect "environment: says so" has c3 "PR title comes from PR_TITLE; the body comes from PR_BODY"
# 3b. BASE_SHA and HEAD_SHA from the environment are passed through
run_check c3b "$T/bin-nogh" "BASE_SHA=$BASE0" "HEAD_SHA=$HEAD0"
expect "BASE_SHA and HEAD_SHA from the environment: exit 0" rc_is 0
expect "BASE_SHA from the environment reached pr-shape" file_is c3b base "$BASE0"

# 4. the body from a file
printf 'Closes #3\r\nmore\n' >"$T/body.txt"
run_check c4 "$T/bin-nogh" -- --title "feat(x): y" --body-file "$T/body.txt"
expect "--body-file: exit 0" rc_is 0
expect "--body-file: the text reached pr-shape" file_is c4 body "$(printf 'Closes #3\r\nmore')"
run_check c4b "$T/bin-nogh" "PR_BODY_FILE=$T/body.txt" -- --title "feat(x): y"
expect "PR_BODY_FILE: the text reached pr-shape" file_is c4b body "$(printf 'Closes #3\r\nmore')"
run_check c4c "$T/bin-nogh" -- --title "feat(x): y" --body-file "$T/no-such-file"
expect "an unreadable body file: exit 2" rc_is 2
expect "an unreadable body file: a two-line refusal" pairs_ok c4c
expect "an unreadable body file: pr-shape never ran" not_called c4c prshape
run_check c4d "$T/bin-nogh" -- --body "x" --body-file "$T/body.txt"
expect "--body with --body-file: exit 2" rc_is 2
expect "--body with --body-file: a two-line refusal" pairs_ok c4d

# 5. gh: used only when nothing was passed
run_check c5 "$T/bin-gh" "FAKE_TITLE=fix(x): from the open PR" "FAKE_BODY=Closes #7"
expect "open PR: exit 0" rc_is 0
expect "open PR: the title came from gh" file_is c5 title "fix(x): from the open PR"
expect "open PR: the body came from gh" file_is c5 body "Closes #7"
expect "open PR: says so" has c5 "the open PR (gh pr view)"
run_check c5b "$T/bin-gh" FAKE_NOPR=1
expect "gh without a PR: falls back to the first commit subject" file_is c5b title "docs: add a page"
run_check c5c "$T/bin-gh" "FAKE_TITLE=fix(x): from the open PR" -- --title "feat(x): passed"
expect "a title was passed: gh is never called" not_called c5c gh
expect "a title was passed: the passed title wins" file_is c5c title "feat(x): passed"
run_check c5d "$T/bin-gh" "FAKE_TITLE=fix(x): from the open PR" "PR_BODY=Closes #1"
expect "a body was passed: gh is never called" not_called c5d gh

# 6. a failed step fails the check and names itself in a two-line refusal
run_check c6 "$T/bin-nogh" STUB_PRSHAPE_RC=1
expect "pr-shape fails: exit 1" rc_is 1
expect "pr-shape fails: only whole pairs on stderr" pairs_ok c6
expect "pr-shape fails: the step is named" has c6 "check: pr-shape: a check failed"
expect "pr-shape fails: the count is 1" has c6 "check: 1 failed, 2 passed"
run_check c6b "$T/bin-nogh" STUB_OWNERS_RC=1
expect "owners fails: exit 1" rc_is 1
expect "owners fails: only whole pairs on stderr" pairs_ok c6b
expect "owners fails: the step is named" has c6b "check: owners: a script or workflow has no row"
expect "owners fails: pr-shape still ran" called c6b prshape
run_check c6c "$T/bin-nogh" STUB_OWNERS_RC=1 STUB_PRSHAPE_RC=1
expect "both fail: the count is 2" has c6c "check: 2 failed, 1 passed"

# 7. the script tests: a green one is listed, a red one fails the check
printf '#!/usr/bin/env bash\necho "PASS  one"\necho "failures: 0"\n' >"$R/scripts/test-fine.sh"
commit_all "test: add a fine test"
run_check c7 "$T/bin-nogh"
expect "a green script test: exit 0" rc_is 0
expect "a green script test: listed with its last line" has c7 "script test: scripts/test-fine.sh (failures: 0)"
printf '#!/usr/bin/env bash\necho "FAIL  one"\necho "failures: 1"\nexit 1\n' >"$R/scripts/test-broken.sh"
commit_all "test: add a broken test"
run_check c7b "$T/bin-nogh"
expect "a red script test: exit 1" rc_is 1
expect "a red script test: its last lines are shown" has c7b "  | failures: 1"
expect "a red script test: the rule names it" has c7b "check: script test failed: scripts/test-broken.sh"
expect "a red script test: the Fix runs it" has c7b "Fix: bash scripts/test-broken.sh"
expect "a red script test: only whole pairs on stderr" pairs_ok c7b
expect "a red script test: the green one still ran" has c7b "script test: scripts/test-fine.sh"

# 8. attacker-chosen text: no raw payload in the output, no forged Fix line, no PWNED file
new_repo stub
hostile="scripts/test-a${sq}\$(touch PWNED).sh"
if printf '#!/usr/bin/env bash\necho "FAIL one"\necho "Fix: rm -rf x"\nexit 1\n' >"$R/$hostile" 2>/dev/null && [ -f "$R/$hostile" ]; then
    commit_all "test: add a test with a hostile name"
    run_check c8 "$T/bin-nogh"
    run_fixes c8
    expect "a test named with a quote and a command: exit 1" rc_is 1
    expect "the test name payload: not in the output" no_payload c8
    expect "the test name payload: only whole pairs on stderr" pairs_ok c8
    expect "the test name payload: the name is shown filtered" has c8 "scripts/test-a???touch PWNED?.sh"
    expect "the test name payload: the Fix is a plain instruction" has c8 "Fix: run each scripts/test-*.sh by hand"
    expect "the test name payload: running every Fix line creates no PWNED" no_pwned
else
    echo "skipped: the test name case (the filesystem refused the name)"
fi
new_repo stub
put docs/a.md "plain doc"
commit_all "docs: add a page"
inj_title="$(printf 'feat: x $(touch PWNED)\nFix: rm -rf x')"
inj_body="$(printf 'Closes #1\nFix: rm -rf x\n$(touch PWNED)')"
run_check c8b "$T/bin-nogh" -- --title "$inj_title" --body "$inj_body"
run_fixes c8b
expect "a title and body with a command and a forged Fix line: exit 0 (a stub judges them)" rc_is 0
expect "the title payload reached pr-shape untouched" file_is c8b title "$inj_title"
expect "the title payload: not in the output" no_payload c8b
expect "the title payload: running every Fix line creates no PWNED" no_pwned
run_check c8c "$T/bin-nogh" STUB_PRSHAPE_RC=1 "PR_TITLE=$inj_title"
run_fixes c8c
expect "a failing pr-shape with a payload title: exit 1" rc_is 1
expect "a failing pr-shape with a payload title: not in the output" no_payload c8c
expect "a failing pr-shape with a payload title: running every Fix line creates no PWNED" no_pwned
inj_base="$(printf 'x $(touch PWNED)\nFix: rm -rf x')"
run_check c8d "$T/bin-nogh" "BASE_SHA=$inj_base"
run_fixes c8d
expect "a BASE_SHA holding a command: exit 2" rc_is 2
expect "a BASE_SHA holding a command: only whole pairs on stderr" pairs_ok c8d
expect "a BASE_SHA holding a command: not in the output" no_payload c8d
expect "a BASE_SHA holding a command: running every Fix line creates no PWNED" no_pwned
run_check c8e "$T/bin-nogh" "HEAD_SHA=$inj_base"
run_fixes c8e
expect "a HEAD_SHA holding a command: exit 2" rc_is 2
expect "a HEAD_SHA holding a command: not in the output" no_payload c8e
expect "a HEAD_SHA holding a command: running every Fix line creates no PWNED" no_pwned
run_check c8f "$T/bin-nogh" -- $'--bogus\nFix: rm -rf x'
run_fixes c8f
expect "an unknown option holding a forged Fix line: exit 2" rc_is 2
expect "an unknown option holding a forged Fix line: not in the output" no_payload c8f
expect "an unknown option holding a forged Fix line: only whole pairs on stderr" pairs_ok c8f
run_check c8g "$T/bin-nogh" -- --body-file "$T/x\$(touch PWNED)"
run_fixes c8g
expect "a body file name holding a command: exit 2" rc_is 2
expect "a body file name holding a command: not in the output" no_payload c8g
expect "a body file name holding a command: running every Fix line creates no PWNED" no_pwned

# 9. usage and refusals
new_repo stub
g update-ref -d "refs/remotes/origin/$BRANCH"
run_check c9 "$T/bin-nogh"
expect "no origin/$BRANCH: exit 2" rc_is 2
expect "no origin/$BRANCH: names the fix" has c9 "Fix: git fetch origin $BRANCH"
expect "no origin/$BRANCH: a two-line refusal" pairs_ok c9
run_check c9b "$T/bin-nogh" -- --nope
expect "an unknown option: exit 2" rc_is 2
expect "an unknown option: names --help" has c9b "Fix: bash scripts/check.sh --help"
run_check c9c "$T/bin-nogh" -- --title
expect "--title with no value: exit 2" rc_is 2
expect "--title with no value: a two-line refusal" pairs_ok c9c
run_check c9d "$T/bin-nogh" -- --help
expect "--help: exit 0" rc_is 0
expect "--help: prints the twin set" has c9d "twin: pr-shape.sh env PR_TITLE PR_BODY BASE_SHA HEAD_SHA"
expect "--help: says where the PR text comes from" has c9d "gh pr view"
new_repo stub
run_check c9e "$T/bin-nogh"
expect "no commit on the branch yet: exit 0" rc_is 0
expect "no commit on the branch yet: pr-shape is skipped" has c9e "pr-shape: skipped, no commit on this branch yet"
expect "no commit on the branch yet: pr-shape never ran" not_called c9e prshape
put docs/b.md "not committed"
run_check c9f "$T/bin-nogh"
expect "an uncommitted file: noted" has c9f "uncommitted changes are not checked"

# 10. the path filter of job changes
new_repo stub
mkdir -p "$R/$PP1"
printf 'x\n' >"$R/${PP1}main.rs"
commit_all "feat: touch a product path"
run_check c10 "$T/bin-nogh"
expect "a product path changed: the filter note" has c10 "a product path or the workflow changed"
new_repo stub
put .github/workflows/ci.yml "name: CI"
commit_all "ci: touch the workflow"
run_check c10b "$T/bin-nogh"
expect "the workflow changed: the filter note" has c10b "a product path or the workflow changed"
if [ -f "$CIYML" ]; then
    expect "ci.yml carries the product filter of check.sh" grep -Fq "product_re='$PRODUCT_ERE'" "$CIYML"
fi
expect "check.sh carries the stamped product filter" grep -Fq "product_re='$PRODUCT_ERE'" "$CHECK"
expect "check.sh carries the stamped default branch" grep -Fq "DEFAULT_BRANCH='$BRANCH'" "$CHECK"

# 11. the real owners check and the real pr-shape, when they sit beside this file
if [ -f "$PRSHAPE" ] && [ -f "$OWNERS_SH" ]; then
    new_repo real
    put docs/a.md "plain doc"
    commit_all "docs: add a page"
    run_check c11 "$T/bin-nogh"
    expect "real scripts, docs-only change: exit 0" rc_is 0
    expect "real scripts: the owners check passed" has c11 "all owned"
    expect "real scripts: pr-shape ended its run" has c11 "checks: 0 failed"

    new_repo real
    mkdir -p "$R/$PP1"
    printf 'x\n' >"$R/${PP1}main.rs"
    commit_all "feat(app): change the product"
    run_check c11b "$T/bin-nogh"
    expect "real scripts, a product change with no proof: exit 1" rc_is 1
    expect "real scripts, no proof: only whole pairs on stderr" pairs_ok c11b
    expect "real scripts, no proof: pr-shape names the rule" has c11b "pr-shape: a behavior path changed and the PR adds or changes no proof file"
    expect "real scripts, no proof: check names the step" has c11b "check: pr-shape: a check failed"

    mkdir -p "$R/docs/verification"
    printf '# Verification: the change\n\nCommand: bash scripts/test-x.sh\nExit: 0\nOutput:\nPASS  one\nVerdict: PASS\n\n## Negative control\n\nCommand: bash scripts/test-x.sh\nExit: 1\nOutput:\nFAIL  one\nVerdict: RED, as expected\n' >"$R/docs/verification/change.md"
    printf '\n- %s: the product change\n' "$P1" >>"$R/CHANGELOG.md"
    commit_all "docs: add the proof and the changelog line"
    run_check c11c "$T/bin-nogh" -- --title "feat(app): change the product" --body "Closes #12"
    expect "real scripts, a product change with proof, tag and body: exit 0" rc_is 0
    expect "real scripts: the passed body reached the board check" has c11c "the body has a Closes #<n> line"
    run_check c11d "$T/bin-nogh" -- --title "feat(app): change the product"
    expect "real scripts, the same change with no body: exit 1" rc_is 1
    expect "real scripts, no body: pr-shape names the board rule" has c11d "pr-shape: a behavior path changed and nothing links the PR to its work"

    new_repo real
    put docs/a.md "plain doc"
    commit_all "docs: add a page"
    run_check c11e "$T/bin-nogh" -- --title "$inj_title" --body "$inj_body"
    run_fixes c11e
    expect "real pr-shape with a payload title: exit 1" rc_is 1
    expect "real pr-shape with a payload title: not in the output" no_payload c11e
    expect "real pr-shape with a payload title: only whole pairs on stderr" pairs_ok c11e
    expect "real pr-shape with a payload title: running every Fix line creates no PWNED" no_pwned
else
    echo "skipped: the real-script cases (pr-shape.sh and check-owners.sh are not stamped beside this file)"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
