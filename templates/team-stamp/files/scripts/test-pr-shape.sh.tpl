#!/usr/bin/env bash
# shellcheck disable=SC2034
# test-pr-shape.sh - run pr-shape.sh against a temp git repo built per case. No network. The tags,
# product paths, board file and default branch are the stamped values, so the cases hold for any
# list that has dev and one product tag. The shellcheck cases run when shellcheck is installed;
# the cases with no shellcheck on PATH always run. The negctl case runs when scripts/negctl.sh sits
# beside this file. Leaves its temp dir behind; the path is printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/pr-shape.sh"
NEGCTL="$HERE/negctl.sh"
BRANCH='{{DEFAULT_BRANCH}}'
BOARD='{{BOARD_FILE}}'
TAGS='{{TAGS}}'
PRODUCT_PATHS='{{PRODUCT_PATHS}}'
T="$(mktemp -d "${TMPDIR:-/tmp}/pr-shape-test.XXXXXX")"
echo "test dir: $T"
HAVE_SC=0
command -v shellcheck >/dev/null 2>&1 && HAVE_SC=1

# P1: the first product tag; PP: the product path prefixes
P1=""
PP=()
oldifs="$IFS"
IFS=','
for t in $TAGS; do
    [ "$t" = dev ] && continue
    [ -n "$P1" ] || P1="$t"
done
for p in $PRODUCT_PATHS; do PP+=("$p"); done
IFS="$oldifs"
[ -n "$P1" ] || { echo "test needs one product tag besides dev in: $TAGS"; exit 1; }
[ "${#PP[@]}" -gt 0 ] || { echo "test needs a product path in: $PRODUCT_PATHS"; exit 1; }

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

R=""
n=0
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.autocrlf=false -c core.hooksPath=/dev/null "$@"; }
put() { # put <path> <content>
    mkdir -p "$R/$(dirname "$1")"
    printf '%s\n' "$2" >"$R/$1"
}
AGENTS_BASE="# Agent rules

## Proof

## Merge"
WF_BASE="- [Agent rules](../AGENTS.md#agent-rules)
- [Proof](../AGENTS.md#proof)
- [Merge](../AGENTS.md#merge)"
CL_BASE="# Changelog

## [Unreleased]

- $P1: an existing tagged line
- a legacy line with no tag

## [0.2.0]

- Old line with no tag."
# new_repo: a base commit with the rule files, a changelog, a proof, a script and a doc
new_repo() {
    n=$((n + 1))
    R="$T/repo$n"
    mkdir -p "$R"
    git -C "$R" init -q --template=
    git -C "$R" symbolic-ref HEAD "refs/heads/$BRANCH"
    put README.md "readme"
    put AGENTS.md "$AGENTS_BASE"
    put docs/TEAM-WORKFLOW.md "$WF_BASE"
    put CHANGELOG.md "$CL_BASE"
    put docs/verification/old.md "old proof"
    put docs/guides/notes.md "notes"
    if [ -n "$BOARD" ]; then put "$BOARD" "| ID-001 | first | note | queued |"; fi
    mkdir -p "$R/scripts"
    printf '#!/usr/bin/env bash\necho old\n' >"$R/scripts/old.sh"
    g add -A
    g commit -q -m base
    BASE="$(g rev-parse HEAD)"
}
finish() { # finish: commit the working changes as the PR head
    g add -A
    g commit -q -m change
    HEAD_="$(g rev-parse HEAD)"
}
# pairs_ok <name>: stderr is whole pairs, a rule line "pr-shape: " then a line "Fix: "
pairs_ok() {
    awk 'NR % 2 == 1 && $0 !~ /^pr-shape: / { bad = 1 } NR % 2 == 0 && $0 !~ /^Fix: / { bad = 1 } END { exit (bad || NR == 0 || NR % 2 == 1) }' "$T/$1.err"
}
npairs() { echo $(($(wc -l <"$T/$1.err") / 2)); }
# run <name> <title> <body>: stdout in $T/<name>.out, stderr in $T/<name>.err, exit in $rc
run() {
    local name="$1" title="$2" body="$3"
    rc=0
    (cd "$R" && env -u CI -u PR_BODY_FILE PR_TITLE="$title" PR_BODY="$body" BASE_SHA="$BASE" HEAD_SHA="$HEAD_" bash "$SCRIPT") \
        >"$T/$name.out" 2>"$T/$name.err" || rc=$?
    if [ "$rc" -eq 1 ] && ! pairs_ok "$name"; then bad "refusal shape of $name: stderr is not rule/Fix pairs"; fi
}
has() { grep -Fq -- "$2" "$T/$1.out" "$T/$1.err"; }
lacks() { ! grep -Fq -- "$2" "$T/$1.out" "$T/$1.err"; }
failed() { grep -Fq -- "pr-shape: $2" "$T/$1.err"; }
rc_is() { [ "$rc" -eq "$1" ]; }
rc_pairs() { [ "$rc" -eq "$1" ] && pairs_ok "$2"; }
one_pair() { [ "$(npairs "$1")" -eq 1 ] && failed "$1" "$2"; }
n_pairs() { [ "$(npairs "$1")" -eq "$2" ]; }

GOOD_TITLE="feat(scripts): add the thing"
CLOSES="Closes #12"
FULL_PROOF="# Verification: the thing

Command: bash scripts/test-thing.sh
Exit: 0
Output:
PASS  one
Verdict: PASS

## Negative control

Command: bash scripts/test-thing.sh
Exit: 1
Output:
FAIL  one
Verdict: RED, as expected"
# behav_files <proof content or ->: a script change, then the proof
behav_files() {
    new_repo
    printf '#!/usr/bin/env bash\necho new\n' >"$R/scripts/new.sh"
    if [ "$1" != "-" ]; then put docs/verification/new.md "$1"; fi
}
behav_repo() {
    behav_files "$1"
    finish
}

# 1. a good behavioral PR
behav_repo "$FULL_PROOF"
run good "$GOOD_TITLE" "$CLOSES"
expect "good behavioral PR: exit 0" rc_is 0
expect "good behavioral PR: nothing on stderr" test ! -s "$T/good.err"
expect "good behavioral PR: final line" has good "checks: 0 failed"

# 2. titles
new_repo
put docs/guides/new.md "doc"
finish
run t1 "Update stuff" ""
expect "bad title (no type): exit 1" rc_is 1
expect "bad title: one pair naming the rule" one_pair t1 "title is not one line"
expect "bad title: the Fix line has the capital F" grep -q '^Fix: ' "$T/t1.err"
run t2 "feat(Scripts): add the thing" ""
expect "upper-case scope: exit 1" rc_is 1
run t3 "feat(scripts): this subject is much too long for the seventy two character limit" ""
expect "title over 72 characters: exit 1" rc_is 1
run t4 "docs(x): fine" ""
expect "title with a scope: exit 0" rc_is 0
run t5 "docs: fine" ""
expect "title without a scope: exit 0" rc_is 0
run t6 "$(printf 'docs: first line\nsecond line')" ""
expect "a two-line title: exit 1" rc_is 1

# 3. proof
behav_repo "-"
run pnone "$GOOD_TITLE" "$CLOSES"
expect "behavior change, no proof file: exit 1" rc_is 1
expect "no proof file: one pair naming the rule" one_pair pnone "a behavior path changed and the PR adds or changes no proof file"
expect "no proof file: the Fix names negctl and the escape line" grep -q '^Fix: bash scripts/negctl.sh .*no-proof: <reason' "$T/pnone.err"

NOEXIT_PROOF="${FULL_PROOF//Exit: 1/Code: 1}"
NOOUT_PROOF="${FULL_PROOF//Output:/Result:}"
NORED_PROOF="${FULL_PROOF//Verdict: RED, as expected/Verdict: PASS}"
NONC_PROOF="${FULL_PROOF//egative control/egative run}"
EXIT0_PROOF="${FULL_PROOF//Exit: 1/Exit: 0}"
BLANKOUT_PROOF="Command: x
Exit: 0
Output:

PASS  one
Verdict: PASS

## Negative control

Command: x
Exit: 1
Output:

Verdict: RED, as expected"
ENDOUT_PROOF="## Negative control
Command: x
Exit: 1
Verdict: RED, as expected
Output:"
for pc in "NOEXIT:no Exit line:Exit:" "NOOUT:no Output label:Output:" "BLANKOUT:Output then a blank line:Output:" "ENDOUT:Output as the last line:Output:" \
    "NORED:no RED verdict:Verdict: RED" "NONC:no negative control words:NEGATIVE CONTROL" "EXIT0:a control with Exit 0:Exit:"; do
    var="${pc%%:*}_PROOF"
    rest="${pc#*:}"
    label="${rest%%:*}"
    want="${rest#*:}"
    behav_repo "${!var}"
    run pbad "$GOOD_TITLE" "$CLOSES"
    expect "proof with $label: exit 1" rc_is 1
    expect "proof with $label: one pair" n_pairs pbad 1
    expect "proof with $label: names what is missing" has pbad "$want"
done

behav_repo "Command: x
Exit: 0
Output:
text
## Negative control
Command: x
Output:
  indented output
  Exit: 2
  Verdict: RED, as expected"
run pcase "$GOOD_TITLE" "$CLOSES"
expect "indented lines, any-case heading: exit 0" rc_is 0
behav_repo "Command: x
Exit: 1
Output:
text
the Verdict: RED came later
negative control"
run pmid "$GOOD_TITLE" "$CLOSES"
expect "Verdict: RED in the middle of a line: exit 1" rc_is 1
behav_repo "$(printf '%s\n' "$FULL_PROOF" | awk '{ printf "%s\r\n", $0 }')"
run pcrlf "$GOOD_TITLE" "$CLOSES"
expect "proof file with CRLF line ends: exit 0" rc_is 0

behav_files "-"
put docs/verification/README.md "$FULL_PROOF"
finish
run pread "$GOOD_TITLE" "$CLOSES"
expect "a full README as the only proof: exit 1" rc_is 1
behav_files "-"
put docs/verification/new/README.md "$FULL_PROOF"
printf 'PNG\n' >"$R/docs/verification/new/shot.png"
finish
run pimg "$GOOD_TITLE" "$CLOSES"
expect "a nested README and an image only: exit 1" rc_is 1
behav_files "-"
g rm -q docs/verification/old.md
finish
run pdel "$GOOD_TITLE" "$CLOSES"
expect "a deleted proof file only: exit 1" rc_is 1
behav_files "-"
put docs/verification/old.md "$FULL_PROOF"
finish
run pedit "$GOOD_TITLE" "$CLOSES"
expect "an old proof file changed to a full one: exit 0" rc_is 0
behav_files "-"
put docs/verification/old.md "$NOEXIT_PROOF"
put docs/verification/new.md "$NORED_PROOF"
finish
run ptwo "$GOOD_TITLE" "$CLOSES"
expect "two incomplete proof files: exit 1, one pair" rc_pairs 1 ptwo
expect "two incomplete proof files: both are named" has ptwo "docs/verification/new.md lacks"
behav_files "-"
put docs/verification/old.md "$NOEXIT_PROOF"
put docs/verification/new.md "$FULL_PROOF"
finish
run pone "$GOOD_TITLE" "$CLOSES"
expect "one complete proof file among two: exit 0" rc_is 0

behav_repo "-"
run npok "$GOOD_TITLE" "Summary
no-proof: comment rewording, no behavior effect
$CLOSES"
expect "no-proof line with a reason: exit 0" rc_is 0
expect "no-proof line: prints the reason, filtered" has npok "no-proof: comment rewording"
run npshort "$GOOD_TITLE" "no-proof: n/a
$CLOSES"
expect "no-proof with a short reason: exit 1" rc_is 1
run npmid "$GOOD_TITLE" "see no-proof: a reason that is long enough
$CLOSES"
expect "no-proof not at the line start: exit 1" rc_is 1
run npph "$GOOD_TITLE" "no-proof: <reason, 10+ characters>
$CLOSES"
expect "no-proof left as the placeholder: exit 1" rc_is 1
run npcrlf "$GOOD_TITLE" "$(printf 'Summary\r\nno-proof: comment rewording, no behavior effect\r\nCloses #12\r\n')"
expect "no-proof and Closes with CRLF line ends: exit 0" rc_is 0
run npnb "$GOOD_TITLE" "no-proof: comment rewording, no behavior effect"
expect "no-proof alone does not excuse the board link: exit 1" rc_is 1
expect "no-proof alone: the board check fails" failed npnb "a behavior path changed and nothing links"
behav_repo "$NOEXIT_PROOF"
run npover "$GOOD_TITLE" "no-proof: comment rewording, no behavior effect
$CLOSES"
expect "no-proof skips the content check: exit 0" rc_is 0

# a behavior path is any changed file that is not documentation
for bp in package-lock.json Makefile snapshots/home.png fixtures/a.json web/index.html data/a.bin docs/secrets/notes.md docs/archive.zip .github/workflows/x.yml .claude/settings.json .kit.toml; do
    new_repo
    mkdir -p "$R/$(dirname "$bp")"
    printf 'changed\n' >"$R/$bp"
    finish
    run bp "chore: touch a path" "$CLOSES"
    expect "behavior path $bp without proof: the proof check fails" failed bp "a behavior path changed and the PR adds or changes no proof file"
done
for dp in README.md docs/guides/OWNERS.md docs/guides/note.txt docs/assets/shot.png docs/product/a.svg docs/product/data.csv .github/pull_request_template.md .claude/memory/a.md docs/verification/x/shot.png; do
    new_repo
    mkdir -p "$R/$(dirname "$dp")"
    printf 'changed\n' >"$R/$dp"
    finish
    run dp "docs: touch a doc" ""
    expect "documentation path $dp: no proof demanded" has dp "ok    proof: no behavior path changed"
done

# 4. board link
behav_repo "$FULL_PROOF"
run noboard "$GOOD_TITLE" ""
expect "no board link: exit 1" rc_is 1
expect "no board link: the Fix names the ways in" grep -q "^Fix: .*Closes #<n>.*no-board-row: <reason" "$T/noboard.err"
run nbr "$GOOD_TITLE" "Summary
no-board-row: tooling fix with no backlog item"
expect "no-board-row line with a reason: exit 0" rc_is 0
run nbrshort "$GOOD_TITLE" "no-board-row: n/a"
expect "no-board-row with a short reason: exit 1" rc_is 1
run nbrmid "$GOOD_TITLE" "see no-board-row: a reason that is long enough"
expect "no-board-row not at the line start: exit 1" rc_is 1
for cl in "Summary
Closes #12" "Closes #12" "fixes #7" "RESOLVES #9"; do
    run closes "$GOOD_TITLE" "$cl"
    expect "close line [$(printf '%s' "$cl" | tail -n 1)]: exit 0" rc_is 0
done
run closescrlf "$GOOD_TITLE" "$(printf 'Summary\r\nCloses #12\r\n')"
expect "Closes #12 with CRLF line ends: exit 0" rc_is 0
run mention "$GOOD_TITLE" "This follows up on #12 and relates to #13."
expect "a body that only mentions #12: exit 1" rc_is 1
expect "a body that only mentions #12: the board check fails" failed mention "a behavior path changed and nothing links"
for cl in "Closes #" "this PR closes #12 when merged" "Closes #twelve"; do
    run closesbad "$GOOD_TITLE" "$cl"
    expect "not a close [$cl]: exit 1" rc_is 1
done
if [ -n "$BOARD" ]; then
    behav_files "$FULL_PROOF"
    put "$BOARD" "| ID-001 | first | note | executing |"
    finish
    run boardchg "$GOOD_TITLE" ""
    expect "the board file changed: exit 0" rc_is 0
    expect "the board rule names the board file" has noboard "$BOARD unchanged"
else
    expect "no board file set: the rule does not name one" lacks noboard "unchanged, no no-board-row"
fi

# 5. changelog
cl_put() { # cl_put <extra lines placed under [Unreleased]>
    local extra="$1"
    put CHANGELOG.md "${CL_BASE/- a legacy line with no tag/- a legacy line with no tag
${extra}}"
}
product_change() { # product_change <path>: a product change that passes the proof check
    mkdir -p "$R/$(dirname "$1")"
    printf 'changed\n' >"$R/$1"
    put docs/verification/new.md "$FULL_PROOF"
}
PFILE="${PP[0]}main.rs"
CL_TITLE="fix(app): change the thing"

new_repo
printf '#!/usr/bin/env bash\necho new\n' >"$R/scripts/new.sh"
put docs/verification/new.md "$FULL_PROOF"
finish
run cltool "chore(scripts): add a script" "$CLOSES"
expect "tooling-only PR, no changelog: exit 0" rc_is 0
expect "tooling-only PR: says no product path" has cltool "ok    changelog: no product path changed"

new_repo
product_change "$PFILE"
finish
run clnone "$CL_TITLE" "$CLOSES"
expect "product path without a changelog line: exit 1" rc_is 1
expect "product path without a changelog line: one pair" n_pairs clnone 1
expect "product path: the rule names the tags" has clnone "$P1:"
expect "product path: the Fix names the escape line" grep -q "^Fix: .*no-changelog: <reason" "$T/clnone.err"
run clesc "$CL_TITLE" "$CLOSES
no-changelog: internal refactor, no change a user sees"
expect "no-changelog line with a reason: exit 0" rc_is 0
run clshort "$CL_TITLE" "$CLOSES
no-changelog: n/a"
expect "no-changelog with a short reason: exit 1" rc_is 1
run clmid "$CL_TITLE" "$CLOSES
see no-changelog: a reason that is long enough"
expect "no-changelog not at the line start: exit 1" rc_is 1
run clcrlf "$CL_TITLE" "$(printf 'Closes #12\r\nno-changelog: internal refactor, no change a user sees\r\n')"
expect "no-changelog with CRLF line ends: exit 0" rc_is 0

for pp in "${PP[@]}"; do
    new_repo
    product_change "${pp}x/file.rs"
    finish
    run clpath "$CL_TITLE" "$CLOSES"
    expect "product path $pp without a changelog line: exit 1" rc_is 1
done
new_repo
mkdir -p "$R/${PP[0]}"
printf 'old\n' >"$R/${PP[0]}old.rs"
g add -A
g commit -q -m "add a product file"
BASE="$(g rev-parse HEAD)"
g rm -q "${PP[0]}old.rs"
put docs/verification/new.md "$FULL_PROOF"
finish
run cldel "$CL_TITLE" "$CLOSES"
expect "a deleted product file without a changelog line: exit 1" rc_is 1
new_repo
mkdir -p "$R/${PP[0]}"
printf 'old\n' >"$R/${PP[0]}old.rs"
g add -A
g commit -q -m "add a product file"
BASE="$(g rev-parse HEAD)"
g mv "${PP[0]}old.rs" scripts/moved.rs
put docs/verification/new.md "$FULL_PROOF"
finish
run clren "$CL_TITLE" "$CLOSES"
expect "a product file renamed out of the product path: exit 1" rc_is 1

new_repo
product_change "$PFILE"
cl_put "- $P1: a new tagged line"
finish
run cltag "$CL_TITLE" "$CLOSES"
expect "product path with a tagged line: exit 0" rc_is 0
expect "product path with a tagged line: says so" has cltag "ok    changelog: the PR adds a tagged line"
new_repo
product_change "$PFILE"
put CHANGELOG.md "${CL_BASE}
- $P1: a tagged line under a released version"
finish
run clrelonly "$CL_TITLE" "$CLOSES"
expect "a tagged line only under a released version: exit 1" rc_is 1

for tg in $(printf '%s' "$TAGS" | tr ',' ' '); do
    new_repo
    put docs/guides/new.md "doc"
    cl_put "- ${tg}: a line"
    finish
    run cltg "docs: add a note" ""
    expect "tag $tg: exit 0" rc_is 0
done
new_repo
product_change "$PFILE"
cl_put "- notatag: a misspelled tag"
finish
run clwrong "$CL_TITLE" "$CLOSES"
expect "added line with a wrong tag: exit 1" rc_is 1
expect "added line with a wrong tag: names the line" has clwrong "line 7"
new_repo
put docs/guides/new.md "doc"
cl_put "- a new line with no tag"
finish
run clnotag "docs: add a note" ""
expect "added untagged line, no product path: exit 1" rc_is 1
new_repo
put docs/guides/new.md "doc"
cl_put "- $P1:no space after the colon"
finish
run clspace "docs: add a note" ""
expect "added line with no space after the colon: exit 1" rc_is 1
run clescbad "docs: add a note" "no-changelog: internal refactor, no change a user sees"
expect "no-changelog does not excuse an untagged line: exit 1" rc_is 1
new_repo
put docs/guides/new.md "doc"
cl_put "- dev: a tagged line"
finish
run clold "docs: add a note" ""
expect "an old untagged line stays untouched: exit 0" rc_is 0
new_repo
put docs/guides/new.md "doc"
put CHANGELOG.md "${CL_BASE}
- an untagged line under a released version"
finish
run clrel "docs: add a note" ""
expect "an untagged line added under a released version: exit 0" rc_is 0
new_repo
put docs/guides/new.md "doc"
cl_put "### Fixed

- $P1: a tagged line
  an indented continuation line"
finish
run clcont "docs: add a note" ""
expect "added heading, blank and continuation lines: exit 0" rc_is 0

# 6. shellcheck
if [ "$HAVE_SC" -eq 1 ]; then
    new_repo
    printf '#!/usr/bin/env bash\nunused_var=1\n' >"$R/scripts/warn.sh"
    put docs/verification/new.md "$FULL_PROOF"
    finish
    run scwarn "$GOOD_TITLE" "$CLOSES"
    expect "shell file with a warning: exit 1" rc_is 1
    expect "shell file with a warning: one pair naming the file" one_pair scwarn "shellcheck finds warnings in 1 changed shell file(s): scripts/warn.sh"
    expect "shell file with a warning: the Fix is a command" grep -q '^Fix: shellcheck -S warning scripts/warn.sh' "$T/scwarn.err"
    new_repo
    printf '#!/usr/bin/env bash\nunused_var=1\n' >"$R/scripts/old.sh"
    finish
    run scold "chore: touch an old script" "no-board-row: tests only, no new behavior
no-proof: tests only, no new behavior"
    expect "a changed old script with a warning: exit 1" rc_is 1
    expect "a changed old script with a warning: only shellcheck fails" one_pair scold "shellcheck finds warnings"
    new_repo
    printf '#!/bin/bash\nunused_var=1\n' >"$R/runme"
    finish
    run scshebang "docs: pretend" ""
    expect "a file with a bash shebang and no .sh name is linted" failed scshebang "shellcheck finds warnings"
    new_repo
    printf 'unused_var=1\n' >"$R/scripts/noshebang.sh"
    finish
    run scnoshe "docs: pretend" ""
    expect "a .sh file with no shebang is linted as bash" failed scnoshe "shellcheck finds warnings"
    new_repo
    printf '#!/usr/bin/env bash\necho "$1"\n' >"$R/scripts/clean.sh"
    put docs/verification/new.md "$FULL_PROOF"
    finish
    run scok "$GOOD_TITLE" "$CLOSES"
    expect "clean shell file: exit 0" rc_is 0
    expect "clean shell file: counted" has scok "shellcheck: 1 shell file(s) clean"
else
    echo "skipped: shellcheck cases (shellcheck is not installed here)"
fi

mkbin() { # mkbin <dir> <tool>...
    local d="$1" t p
    shift
    mkdir -p "$d"
    for t in "$@"; do
        p="$(command -v "$t" 2>/dev/null || true)"
        case "$p" in /*) ln -sf "$p" "$d/$t" ;; esac
    done
}
mkbin "$T/bin-nosc" bash sh env git awk sed grep mktemp dirname basename mkdir cat printf tr head cut rm paste sort wc ls tail
new_repo
printf '#!/usr/bin/env bash\necho new\n' >"$R/scripts/new.sh"
put docs/verification/new.md "$FULL_PROOF"
finish
rc=0
(cd "$R" && PATH="$T/bin-nosc" CI="" PR_TITLE="$GOOD_TITLE" PR_BODY="$CLOSES" BASE_SHA="$BASE" HEAD_SHA="$HEAD_" "$T/bin-nosc/bash" "$SCRIPT") >"$T/nosc.out" 2>"$T/nosc.err" || rc=$?
expect "no shellcheck, local: exit 0" rc_is 0
expect "no shellcheck, local: prints the skip notice" has nosc "skipped, shellcheck is not installed"
rc=0
(cd "$R" && PATH="$T/bin-nosc" CI=true PR_TITLE="$GOOD_TITLE" PR_BODY="$CLOSES" BASE_SHA="$BASE" HEAD_SHA="$HEAD_" "$T/bin-nosc/bash" "$SCRIPT") >"$T/nosc-ci.out" 2>"$T/nosc-ci.err" || rc=$?
expect "no shellcheck, CI=true: exit 1 with one pair" rc_pairs 1 nosc-ci
expect "no shellcheck, CI=true: names the cause" failed nosc-ci "shellcheck is not installed on this runner"
new_repo
put docs/guides/new.md "doc"
finish
rc=0
(cd "$R" && PATH="$T/bin-nosc" CI=true PR_TITLE="docs: add a doc" PR_BODY="" BASE_SHA="$BASE" HEAD_SHA="$HEAD_" "$T/bin-nosc/bash" "$SCRIPT") >"$T/nosc-docs.out" 2>"$T/nosc-docs.err" || rc=$?
expect "no shellcheck, CI=true, no shell file changed: exit 0" rc_is 0

# 7. rule parity
new_repo
put AGENTS.md "${AGENTS_BASE}

## Never"
finish
run pa "docs: change the rules" ""
expect "AGENTS.md alone: exit 1" rc_is 1
expect "AGENTS.md alone: one pair naming the file" one_pair pa "AGENTS.md changed and docs/TEAM-WORKFLOW.md did not"
expect "AGENTS.md alone: the Fix names the escape line" grep -q "^Fix: .*no-rule-mirror: <reason" "$T/pa.err"
new_repo
put docs/TEAM-WORKFLOW.md "${WF_BASE}
Another line."
finish
run pw "docs: change the rules" ""
expect "TEAM-WORKFLOW.md alone: exit 1" rc_is 1
expect "TEAM-WORKFLOW.md alone: names the file" failed pw "docs/TEAM-WORKFLOW.md changed and AGENTS.md did not"
run pwesc "docs: change the rules" "no-rule-mirror: the wording only needs one file"
expect "alone with no-rule-mirror and a reason: exit 0" rc_is 0
run pwshort "docs: change the rules" "no-rule-mirror: skip"
expect "alone with a short no-rule-mirror reason: exit 1" rc_is 1
run pwcrlf "docs: change the rules" "$(printf 'Summary\r\nno-rule-mirror: the wording only needs one file\r\n')"
expect "no-rule-mirror with CRLF line ends: exit 0" rc_is 0
new_repo
put AGENTS.md "${AGENTS_BASE}

## Never"
put docs/TEAM-WORKFLOW.md "${WF_BASE}
- [Never](../AGENTS.md#never)"
finish
run pb "docs: change the rules" ""
expect "both changed, every heading linked: exit 0" rc_is 0
new_repo
put AGENTS.md "${AGENTS_BASE}

## Never

\`\`\`
# not a heading, inside a fence
\`\`\`"
put docs/TEAM-WORKFLOW.md "${WF_BASE}
- [Never](../AGENTS.md#never)"
finish
run pfence "docs: change the rules" ""
expect "a hash line inside a code fence is not a heading: exit 0" rc_is 0
new_repo
put AGENTS.md "${AGENTS_BASE}

## Never"
put docs/TEAM-WORKFLOW.md "${WF_BASE}
Another line."
finish
run pnolink "docs: change the rules" ""
expect "both changed, a new heading with no link: exit 1" rc_is 1
expect "both changed, a new heading with no link: names the anchor" failed pnolink "1 AGENTS.md heading(s) have no link in docs/TEAM-WORKFLOW.md, anchors: never"
run pnolinkesc "docs: change the rules" "no-rule-mirror: this heading is mirrored later"
expect "a missing link with no-rule-mirror: exit 0" rc_is 0
new_repo
g rm -q docs/TEAM-WORKFLOW.md
put AGENTS.md "${AGENTS_BASE}

## Never"
finish
run pabsent "docs: change the rules" ""
expect "one rule file absent at head: parity is skipped, exit 0" rc_is 0

# 7b. two paths that differ only in case are refused (the guard matches doors in any casing; a case-insensitive
# checkout would let one overwrite the other). The paths go straight into the index.
for pair in ".claude/settings.json:.CLAUDE/settings.json" "scripts/a.sh:SCRIPTS/a.sh" "OWNERS.md:Owners.md"; do
    new_repo
    first="${pair%%:*}"; second="${pair##*:}"
    blob1="$(printf 'one\n' | g hash-object -w --stdin)"; blob2="$(printf 'two\n' | g hash-object -w --stdin)"
    g update-index --add --cacheinfo "100644,$blob1,$first"
    g update-index --add --cacheinfo "100644,$blob2,$second"
    g commit -q -m change
    HEAD_="$(g rev-parse HEAD)"
    tag="case-$(printf '%s' "$pair" | tr -c 'A-Za-z0-9' '_')"
    run "$tag" "docs: add two files" "no-proof: a case plant for the test, no behavior change"
    expect "case collision $pair: exit 1" rc_is 1
    expect "case collision $pair: two-line refusal" rc_pairs 1 "$tag"
    expect "case collision $pair: names the rule" failed "$tag" "two paths differ only in case"
done
# a name with a newline cannot ride a line list: the tree is read NUL-delimited and refuses it
new_repo
blob1="$(printf 'one\n' | g hash-object -w --stdin)"
if g update-index --add --cacheinfo "100644,$blob1,docs/a
b.txt" 2>/dev/null; then
    g commit -q -m change
    HEAD_="$(g rev-parse HEAD)"
    run casenl "docs: add a file" "no-proof: a name plant for the test, no behavior change"
    expect "a path with a newline in the tree: exit 1" rc_is 1
    expect "a path with a newline in the tree: names the rule" failed casenl "two paths differ only in case"
else
    echo "NOTE  a newline in a path: git refuses the name, case skipped"
fi
new_repo
printf 'x\n' >"$R/docs/guides/other.md"
finish
run casefine "docs: add a guide" "no-proof: a plain docs change, no behavior change"
expect "no case collision: the case check passes" has casefine "ok    case: no two paths differ only in case"

# 8. every failed check prints, in one run
behav_repo "-"
run many "Update stuff" ""
expect "title, proof and board fail together: exit 1" rc_is 1
expect "three failures print three pairs" n_pairs many 3
expect "the last stdout line counts the failures" has many "checks: 3 failed"

# 9. inputs
rc=0
(cd "$R" && env -u PR_TITLE -u CI BASE_SHA="$BASE" HEAD_SHA="$HEAD_" bash "$SCRIPT") >"$T/usage.out" 2>"$T/usage.err" || rc=$?
expect "no PR_TITLE: exit 2 with a pair" rc_pairs 2 usage
rc=0
(cd "$R" && env -u CI PR_TITLE="$GOOD_TITLE" BASE_SHA="no-such-rev" HEAD_SHA="$HEAD_" bash "$SCRIPT") >"$T/badref.out" 2>"$T/badref.err" || rc=$?
expect "an unknown base: exit 2 with a pair" rc_pairs 2 badref
rc=0
(cd "$R" && env -u CI PR_TITLE="$GOOD_TITLE" BASE_SHA="--output=x" HEAD_SHA="$HEAD_" bash "$SCRIPT") >"$T/optref.out" 2>"$T/optref.err" || rc=$?
expect "a base that looks like an option: exit 2" rc_pairs 2 optref
expect "a base that looks like an option: nothing written" test ! -e "$R/x"
behav_repo "$FULL_PROOF"
g update-ref "refs/remotes/origin/$BRANCH" "$BASE"
rc=0
(cd "$R" && env -u CI -u BASE_SHA -u HEAD_SHA PR_TITLE="$GOOD_TITLE" PR_BODY="$CLOSES" bash "$SCRIPT") >"$T/defs.out" 2>"$T/defs.err" || rc=$?
expect "BASE_SHA and HEAD_SHA default to origin/$BRANCH and HEAD: exit 0" rc_is 0
printf 'Summary\r\nCloses #12\r\n' >"$T/body.txt"
rc=0
(cd "$R" && env -u CI -u PR_BODY PR_BODY_FILE="$T/body.txt" PR_TITLE="$GOOD_TITLE" BASE_SHA="$BASE" HEAD_SHA="$HEAD_" bash "$SCRIPT") >"$T/bf.out" 2>"$T/bf.err" || rc=$?
expect "PR_BODY_FILE with CRLF line ends: exit 0" rc_is 0
behav_files "-"
finish
put docs/verification/new.md "$FULL_PROOF"
run wt "$GOOD_TITLE" "$CLOSES"
expect "an uncommitted proof file does not count: exit 1" rc_is 1

# 10. attacker-chosen text: no raw payload in the output, no forged Fix: line, no PWNED file
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
no_payload() { # no_payload <name>: no raw payload text and no forged Fix: line in the output
    ! grep -Fq -e '$(touch' -e 'Fix: rm -rf' "$T/$1.out" "$T/$1.err"
}
no_pwned() { [ -z "$(find "$R" "$T" -name 'PWNED*' 2>/dev/null)" ]; }
sq="'"

new_repo
printf '#!/usr/bin/env bash\necho new\n' >"$R/scripts/new.sh"
finish
run inj1 "$(printf 'feat: x $(touch PWNED)\nFix: rm -rf x')" "$(printf 'Closes #1\nFix: rm -rf x\n$(touch PWNED)')"
run_fixes inj1
expect "a title with a command and a forged Fix line: exit 1" rc_is 1
expect "the title payload: not in the output" no_payload inj1
expect "the title payload: every stderr line is a pair line" pairs_ok inj1
expect "the title payload: running every Fix line creates no PWNED" no_pwned
run inj1b 'feat: $(touch PWNED)' "Closes #1"
expect "a one-line title holding a command: not echoed" no_payload inj1b
expect "a one-line title holding a command: never run" no_pwned

bn="scripts/a${sq}\$(touch PWNED).sh"
pn="docs/verification/a${sq}\$(touch PWNED).md"
new_repo
if printf '#!/usr/bin/env bash\nunused_var=1\n' >"$R/$bn" 2>/dev/null && [ -f "$R/$bn" ]; then
    printf 'x\n' >"$R/$pn"
    finish
    run inj2 "$GOOD_TITLE" ""
    run_fixes inj2
    expect "a file named with a quote and a command: exit 1" rc_is 1
    expect "the file name payload: not in the output" no_payload inj2
    expect "the file name payload: every stderr line is a pair line" pairs_ok inj2
    expect "the file name payload: running every Fix line creates no PWNED" no_pwned
    expect "the file name payload: the proof rule names the file, filtered" has inj2 "docs/verification/a???touch PWNED?.md"
    if [ "$HAVE_SC" -eq 1 ]; then
        expect "the file name payload: the shellcheck rule names the file, filtered" has inj2 "scripts/a???touch PWNED?.sh"
        expect "the file name payload: the shellcheck Fix is a plain instruction" grep -q '^Fix: run shellcheck -S warning on each changed' "$T/inj2.err"
    fi
else
    echo "skipped: the file name cases (the filesystem refused the name)"
fi
new_repo
if printf 'x\n' >"$R/scripts/with"$'\n'"newline.sh" 2>/dev/null; then
    finish
    run inj3 "$GOOD_TITLE" "$CLOSES"
    expect "a file name with a newline counts as a behavior change: exit 1" rc_is 1
    expect "a file name with a newline: the proof rule fires" failed inj3 "a behavior path changed and the PR adds or changes no proof file"
else
    echo "skipped: the newline file name case (the filesystem refused the name)"
fi

new_repo
printf '#!/usr/bin/env bash\necho new\n' >"$R/scripts/new.sh"
printf 'x\n' >"$R/$pn" 2>/dev/null || put docs/verification/plain.md "x"
cl_put '- $(touch PWNED) an untagged line'
put AGENTS.md "${AGENTS_BASE}

## \$(touch PWNED) heading"
put docs/TEAM-WORKFLOW.md "${WF_BASE}
Another line."
finish
run inj4 "$GOOD_TITLE" ""
run_fixes inj4
expect "proof name, changelog line and heading carrying a command: exit 1" rc_is 1
expect "proof, board, changelog and parity all refuse: four pairs" n_pairs inj4 4
expect "the mixed payload: not in the output" no_payload inj4
expect "the mixed payload: every stderr line is a pair line" pairs_ok inj4
expect "the mixed payload: running every Fix line creates no PWNED" no_pwned

# 11. negctl output is a proof (when negctl.sh sits beside this script)
if [ -f "$NEGCTL" ]; then
    N="$T/neg-fixture"
    mkdir -p "$N"
    git -C "$N" init -q --template=
    printf 'good\n' >"$N/v.txt"
    printf '#!/usr/bin/env bash\nif grep -q good v.txt; then echo "ok - v"; else echo "FAIL v"; exit 1; fi\n' >"$N/t.sh"
    git -C "$N" add -A
    git -C "$N" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m fixture
    nrc=0
    (cd "$N" && bash "$NEGCTL" "bash t.sh" "echo bad > v.txt") >"$T/neg.out" 2>"$T/neg.err" || nrc=$?
    expect "negctl on a tiny fixture: exit 0" test "$nrc" -eq 0
    behav_files "-"
    {
        printf '# Verification: the thing\n\nCommand: bash scripts/test-thing.sh\nOutput:\nPASS  one\nExit: 0\nVerdict: PASS\n\n'
        cat "$T/neg.out"
    } >"$R/docs/verification/neg.md"
    finish
    run negc "$GOOD_TITLE" "$CLOSES"
    expect "the block negctl.sh prints is accepted as a proof: exit 0" rc_is 0
    expect "the block negctl.sh prints: the proof check says so" has negc "ok    proof: docs/verification/neg.md holds a NEGATIVE CONTROL block"
else
    echo "skipped: the negctl case (scripts/negctl.sh is not stamped beside this script)"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
