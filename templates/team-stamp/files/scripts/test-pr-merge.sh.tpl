#!/usr/bin/env bash
# test-pr-merge.sh - run pr-merge.sh against a fake gh that serves canned PR JSON per case.
# The fake runs the script's --jq expression through jq, so jq must be on PATH here
# (pr-merge.sh itself needs gh only). No network. Door cases run a copy of the script with
# a known door list, so they hold for any stamped values; one case reads the stamped list.
# Leaves its temp dir behind; the path is printed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/pr-merge.sh"
if ! command -v jq >/dev/null 2>&1; then
    echo "test-pr-merge: jq not found, skipping (the fake gh needs it)"
    exit 0
fi
T="$(mktemp -d "${TMPDIR:-/tmp}/pr-merge-test.XXXXXX")"
echo "test dir: $T"

# The values this repo was stamped with.
DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"

mkdir -p "$T/bin"
# fake gh: `pr view` serves $T/case.json through the --jq expression, except that the Nth
# `pr view` call serves $T/seq-N.json when that file exists (a rollup that changes between
# polls). `pr merge` is recorded, and fails the way GitHub does when the pinned head is not
# the live head in $T/live-head.
cat >"$T/bin/gh" <<EOF
#!/bin/bash
echo "gh \$*" >> "$T/calls"
if [ "\$1 \$2" = "pr view" ]; then
    expr=""
    while [ \$# -gt 0 ]; do
        if [ "\$1" = "--jq" ]; then expr="\$2"; fi
        shift
    done
    n=\$(grep -c '^gh pr view' "$T/calls")
    src="$T/case.json"
    if [ -f "$T/seq-\$n.json" ]; then src="$T/seq-\$n.json"; fi
    jq -r "\$expr" "\$src"
elif [ "\$1 \$2" = "pr merge" ]; then
    want=""
    while [ \$# -gt 0 ]; do
        if [ "\$1" = "--match-head-commit" ]; then want="\$2"; fi
        shift
    done
    if [ -f "$T/live-head" ] && [ "\$want" != "\$(cat "$T/live-head")" ]; then
        echo "GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)" >&2
        exit 1
    fi
    exit 0
else
    exit 1
fi
EOF
chmod +x "$T/bin/gh"
export PATH="$T/bin:$PATH"

CHK_OK='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS"}'
CHK_DOCS='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SKIPPED"}'
CHK_FAIL='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"FAILURE"}'
CHK_PEND='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build","status":"IN_PROGRESS","conclusion":""}'
CHK_RERUN='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-01-01T00:00:00Z"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-01-01T00:01:00Z"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-01-01T00:05:00Z"}'
CHK_TWOMAKERS='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"ci"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"ci"},{"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","workflowName":"added-by-the-pr"}'
FILE_PLAIN='{"path":"docs/README.md"},{"path":"app/src/lib.rs"}'
FILE_DOOR='{"path":"docs/README.md"},{"path":"zz-door/vectors/pair.json"}'
REV_NONE=''
REV_OTHER='{"author":{"login":"reviewer"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"}'
REV_CAROL='{"author":{"login":"carol"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"}'
REV_SELF='{"author":{"login":"author"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"}'
REV_REVOKED='{"author":{"login":"reviewer"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"},{"author":{"login":"reviewer"},"state":"CHANGES_REQUESTED","submittedAt":"2026-01-03T00:00:00Z"}'

HEAD_SHA="head-judged"
OTHER_HEAD="head-pushed-later"

# mkcase_at <file> <isDraft> <mergeable> <checks> <files> <reviews>
mkcase_at() {
    local file="$1"
    shift
    printf '{"isDraft":%s,"mergeable":"%s","author":{"login":"%s"},"statusCheckRollup":[%s],"files":[%s],"reviews":[%s],"headRefOid":"%s","headRefName":"%s"}\n' \
        "$1" "$2" "${CASE_AUTHOR:-author}" "$3" "$4" "$5" "${CASE_HEAD-$HEAD_SHA}" "${CASE_BRANCH:-feature/x}" >"$file"
}
# mkcase <isDraft> <mergeable> <checks> <files> <reviews>: what every pr view serves;
# it also drops the sequence of the case before. Call mkseq after it.
mkcase() {
    rm -f "$T"/seq-*.json "$T/live-head"
    mkcase_at "$T/case.json" "$@"
}
# mkseq <N> <isDraft> <mergeable> <checks> <files> <reviews>: what the Nth pr view serves
mkseq() {
    local n="$1"
    shift
    mkcase_at "$T/seq-$n.json" "$@"
}

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

merged() { grep -qx "gh pr merge 7 --squash --delete-branch --match-head-commit $HEAD_SHA" "$T/calls"; }
not_merged() { ! grep -q "^gh pr merge" "$T/calls"; }
views_are() { [ "$(grep -c '^gh pr view' "$T/calls")" -eq "$1" ]; }
calls_are() { [ "$(grep -c '^gh ' "$T/calls")" -eq "$1" ]; }
# every refusal is two lines on stderr: a rule line, then a "Fix: " line (progress lines are skipped)
two_line_form() {
    awk '
        /^pr-merge: waiting on/ { next }
        /^Fix: / { if (!want) bad = 1; want = 0; next }
        { if (want) bad = 1; want = 1 }
        END { if (want) bad = 1; exit bad }' "$T/err-$1"
}
fix_is() { grep -qxF "Fix: $2" "$T/err-$1"; }

# variant <name> <door array body> <approver>: a copy of the script with other door values
variant() {
    mkdir -p "$T/v-$1"
    sed -e "s|^DOORS=(.*)\$|DOORS=($2)|" -e "s|^APPROVER=\".*\"\$|APPROVER=\"$3\"|" "$SCRIPT" >"$T/v-$1/pr-merge.sh"
}
variant door '"zz-door/*" "zz-two/*"' ''
variant approver '"zz-door/*"' 'carol'
variant nodoor '' ''

# Polls in the --wait tests run fast.
export PR_MERGE_POLL_SECS=0.1

# run <name> <args...>: fresh call log, stdout in $T/out-<name>, stderr in $T/err-<name>, exit code
# in $rc. SUT names the script (the stamped one unless a case sets another), RUNNER the bash.
SUT="$SCRIPT"
RUNNER="bash"
run() {
    local name="$1"
    shift
    : >"$T/calls"
    rc=0
    (cd "$T" && "$RUNNER" "$SUT" "$@") >"$T/out-$name" 2>"$T/err-$name" || rc=$?
}
text_has() { grep -qF -- "$2" "$T/out-$1" "$T/err-$1"; }

# the stamped values are the ones in the script
expect "stamped default branch is in the script" grep -qxF 'DEFAULT_BRANCH="{{DEFAULT_BRANCH}}"' "$SCRIPT"
expect "stamped approver is in the script" grep -qxF 'APPROVER="{{DOOR_APPROVER}}"' "$SCRIPT"
expect "stamped door list is in the script" grep -qxF 'DOORS=({{DOOR_ARRAY}})' "$SCRIPT"
expect "the script holds only the brief's rules: no CI-path flag" bash -c '! grep -q "allow-ci-change" "$0"' "$SCRIPT"
expect "the script holds only the brief's rules: no kit head variable" bash -c '! grep -q "KIT_" "$0"' "$SCRIPT"
if [ "$DEFAULT_BRANCH" != "main" ]; then
    expect "no literal main branch in the script" bash -c '! grep -Eq "origin/main|[^a-z]main[^a-z]" "$0"' "$SCRIPT"
fi

mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run green 7
expect "green merges: exit 0" [ "$rc" -eq 0 ]
expect "green merges: squash, delete-branch and the judged head in the call" merged
expect "green merges: one pr view and one pr merge, nothing else" calls_are 2

mkcase false MERGEABLE "$CHK_DOCS" "$FILE_PLAIN" "$REV_NONE"
run docs 7
expect "docs-only (other jobs skipped, changes passed) merges" merged

mkcase false MERGEABLE "$CHK_RERUN" "$FILE_PLAIN" "$REV_NONE"
run rerun 7
expect "an old failed run, rerun green, merges: only the newest run counts" merged

mkcase false MERGEABLE "" "$FILE_PLAIN" "$REV_NONE"
run nochecks 7
expect "zero checks is refused: exit 1" [ "$rc" -eq 1 ]
expect "zero checks is refused: names the changes job" text_has nochecks "changes job has not passed"
expect "zero checks is refused: two-line form" two_line_form nochecks
expect "zero checks is refused: no merge call" not_merged

mkcase true MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run draft 7
expect "draft refused: exit 1" [ "$rc" -eq 1 ]
expect "draft refused: says draft" text_has draft "is a draft"
expect "draft refused: two-line form, fix is gh pr ready" fix_is draft "gh pr ready 7"
expect "draft refused: two-line form" two_line_form draft
expect "draft refused: no merge call" not_merged

mkcase false MERGEABLE "$CHK_FAIL" "$FILE_PLAIN" "$REV_NONE"
run failing 7
expect "failing check refused: exit 1" [ "$rc" -eq 1 ]
expect "failing check refused: names the check" text_has failing "failing check: build"
expect "failing check refused: two-line form" two_line_form failing
expect "failing check refused: no merge call" not_merged

mkcase false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run pending 7
expect "pending check refused without --wait: exit 1" [ "$rc" -eq 1 ]
expect "pending check refused: names the check" text_has pending "pending check: build"
expect "pending check refused: the fix is --wait" fix_is pending "bash scripts/pr-merge.sh --wait 7"
expect "pending check refused: two-line form" two_line_form pending
expect "pending check refused: no merge call" not_merged
expect "pending check refused: a single gh call" calls_are 1

mkcase false MERGEABLE "$CHK_TWOMAKERS" "$FILE_PLAIN" "$REV_NONE"
run ambiguous 7
expect "a check name from two producers is refused" [ "$rc" -eq 1 ]
expect "a check name from two producers: names it, two-line form" two_line_form ambiguous
expect "a check name from two producers: no merge call" not_merged

mkcase false CONFLICTING "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run conflict 7
expect "conflict refused: exit 1" [ "$rc" -eq 1 ]
expect "conflict refused: says conflicts" text_has conflict "merge conflicts"
expect "conflict refused: the fix merges the stamped default branch" grep -qF "git merge origin/$DEFAULT_BRANCH" "$T/err-conflict"
expect "conflict refused: two-line form" two_line_form conflict
expect "conflict refused: no merge call" not_merged

mkcase false UNKNOWN "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run nowaitunknown 7
expect "no wait, mergeability UNKNOWN: refused, exit 1" [ "$rc" -eq 1 ]
expect "no wait, mergeability UNKNOWN: says try again" text_has nowaitunknown "mergeability is UNKNOWN, try again in a minute"
expect "no wait, mergeability UNKNOWN: two-line form" two_line_form nowaitunknown

# --wait: poll the PR's own rollup until nothing is pending, then judge as usual.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
mkseq 1 false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
mkseq 2 false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run waitgreen --wait 7
expect "wait, pending then green: exit 0" [ "$rc" -eq 0 ]
expect "wait, pending then green: merge call recorded" merged
expect "wait, pending then green: read the PR three times" views_are 3
expect "wait, pending then green: progress line counts pending checks" text_has waitgreen "waiting on 1 pending check"

# Right after a push no check has registered: an empty rollup is still a wait.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
mkseq 1 false MERGEABLE "" "$FILE_PLAIN" "$REV_NONE"
run waitempty --wait 7
expect "wait, no checks yet then green: exit 0" [ "$rc" -eq 0 ]
expect "wait, no checks yet then green: read the PR twice" views_are 2
expect "wait, no checks yet then green: says why it waits" text_has waitempty "checks not registered yet"

# Right after a push GitHub has not computed mergeability: UNKNOWN is a wait too.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
mkseq 1 false UNKNOWN "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
mkseq 2 false UNKNOWN "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run waitunknown --wait 7
expect "wait, mergeability UNKNOWN then MERGEABLE: exit 0" [ "$rc" -eq 0 ]
expect "wait, mergeability UNKNOWN then MERGEABLE: read the PR three times" views_are 3

mkcase false UNKNOWN "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run waitunknowntimeout --wait --timeout 1 7
expect "wait, mergeability stays UNKNOWN: exit 1" [ "$rc" -eq 1 ]
expect "wait, mergeability stays UNKNOWN: the timeout line names it" text_has waitunknowntimeout "still pending: mergeability UNKNOWN"
expect "wait, mergeability stays UNKNOWN: no merge call" not_merged

mkcase false MERGEABLE "$CHK_FAIL" "$FILE_PLAIN" "$REV_NONE"
mkseq 1 false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run waitred --wait 7
expect "wait, pending then red: exit 1" [ "$rc" -eq 1 ]
expect "wait, pending then red: names the failing check" text_has waitred "failing check: build"
expect "wait, pending then red: two-line form" two_line_form waitred
expect "wait, pending then red: no merge call" not_merged
expect "wait, pending then red: read the PR twice" views_are 2

mkcase false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run waittimeout --wait --timeout 1 7
expect "wait that never finishes: exit 1" [ "$rc" -eq 1 ]
expect "wait that never finishes: no merge call" not_merged
expect "wait timeout line names the pending check" text_has waittimeout "timed out after 1s waiting on #7, still pending: build"
expect "wait timeout: two-line form (the rule, then the fix)" two_line_form waittimeout
expect "wait timeout: the fix line is the last line" bash -c 'tail -n 1 "$0" | grep -q "^Fix: "' "$T/err-waittimeout"

mkcase true MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run waitdraft --wait 7
expect "wait on a draft: exit 1" [ "$rc" -eq 1 ]
expect "wait on a draft: says draft" text_has waitdraft "is a draft"
expect "wait on a draft: read the PR once, no polling" views_are 1
expect "wait on a draft: no merge call" not_merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run waitnopending --wait 7
expect "wait on a PR with nothing pending: one pr view, then the merge" calls_are 2

# --dry-run judges and merges nothing.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run dry --dry-run 7
expect "dry-run on green: exit 0" [ "$rc" -eq 0 ]
expect "dry-run on green: says dry run" text_has dry "dry run"
expect "dry-run on green: no merge call" not_merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
mkseq 1 false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run waitdry --dry-run --wait 7
expect "dry-run with wait: exit 0, waited, nothing merged" bash -c '[ "$1" -eq 0 ]' _ "$rc"
expect "dry-run with wait: read the PR twice" views_are 2
expect "dry-run with wait: no merge call" not_merged

mkcase false MERGEABLE "$CHK_FAIL" "$FILE_PLAIN" "$REV_NONE"
run dryred --dry-run 7
expect "dry-run on red: refused, exit 1" [ "$rc" -eq 1 ]
expect "dry-run on red: no merge call" not_merged

# The merge is pinned to the judged head: GitHub refuses it when the head moved after the check.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
printf '%s\n' "$OTHER_HEAD" >"$T/live-head"
run moved 7
expect "head moved after the judgment: exit 1" [ "$rc" -eq 1 ]
expect "head moved after the judgment: the call was pinned to the judged head" merged
expect "head moved after the judgment: names the refusal, two-line form" two_line_form moved
expect "head moved after the judgment: the fix judges it again" fix_is moved "bash scripts/pr-merge.sh --wait 7"

# --wait pins the head of the final poll, not the first read.
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
CASE_HEAD=$OTHER_HEAD mkseq 1 false MERGEABLE "$CHK_PEND" "$FILE_PLAIN" "$REV_NONE"
run pinwait --wait 7
expect "wait: merge is pinned to the head of the last poll, not the first" merged

# One-way doors, with a known door list (zz-door/*, zz-two/*) and no named approver.
SUT="$T/v-door/pr-merge.sh"
mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_NONE"
run door 7
expect "door path without approval refused: exit 1" [ "$rc" -eq 1 ]
expect "door path refused: names the path" text_has door "zz-door/vectors/pair.json"
expect "door path refused: with no named approver the fix is a plain instruction" grep -q '^Fix: ask a person other than the author to approve PR 7' "$T/err-door"
expect "door path refused: two-line form" two_line_form door
expect "door path refused: no merge call" not_merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_SELF"
run doorself 7
expect "door path with only the author's approval refused" [ "$rc" -eq 1 ]
expect "door path with only the author's approval: no merge call" not_merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_REVOKED"
run doorrevoked 7
expect "door path with a later change request refused" [ "$rc" -eq 1 ]

mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_OTHER"
run dooroked 7
expect "door path with another person's approval merges: exit 0" [ "$rc" -eq 0 ]
expect "door path with approval: merge call recorded" merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run nodoorpath 7
expect "a PR that touches no door path merges without a review" merged

# 100 files or more may be a capped list: with a door list it counts as touching a door.
files100=""
i=0
while [ "$i" -lt 100 ]; do
    files100="${files100:+$files100,}{\"path\":\"docs/f$i.md\"}"
    i=$((i + 1))
done
mkcase false MERGEABLE "$CHK_OK" "$files100" "$REV_NONE"
run files100 7
expect "100 files with a door list and no approval: refused" [ "$rc" -eq 1 ]
mkcase false MERGEABLE "$CHK_OK" "$files100" "$REV_OTHER"
run files100ok 7
expect "100 files with a door list and an approval: merges" merged

# A named approver: the approval must come from that login, unless they wrote the PR.
SUT="$T/v-approver/pr-merge.sh"
mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_OTHER"
run approther 7
expect "named approver, approval from someone else: refused" [ "$rc" -eq 1 ]
expect "named approver, approval from someone else: names the approver" text_has approther "needs an approving review from carol"
expect "named approver, approval from someone else: two-line form" two_line_form approther
expect "named approver, approval from someone else: the fix adds the approver" fix_is approther "gh pr edit 7 --add-reviewer carol"
expect "named approver, approval from someone else: no merge call" not_merged

mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_CAROL"
run apprcarol 7
expect "named approver approves: merges" merged

CASE_AUTHOR=carol mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_OTHER"
run apprauthor 7
expect "the approver wrote the PR, another person approves: merges" merged

CASE_AUTHOR=carol mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_NONE"
run apprauthornone 7
expect "the approver wrote the PR, nobody approves: refused" [ "$rc" -eq 1 ]

CASE_AUTHOR=carol mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" '{"author":{"login":"carol"},"state":"APPROVED","submittedAt":"2026-01-02T00:00:00Z"}'
run apprself 7
expect "the approver approves their own PR: refused (the author is never the second person)" [ "$rc" -eq 1 ]

# An empty door list under set -u. Bash 3.2 dies on an empty array expansion that is not guarded.
if /bin/bash --version 2>/dev/null | head -n 1 | grep -q 'version 3\.'; then
    EMPTY_RUNNER="/bin/bash"
else
    EMPTY_RUNNER="bash"
    echo "note: /bin/bash here is not bash 3.x, so the empty-door-list cases run under the bash on PATH"
fi
SUT="$T/v-nodoor/pr-merge.sh"
RUNNER="$EMPTY_RUNNER"
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run emptydoors 7
expect "empty door list, set -u: a clean PR merges" merged
expect "empty door list, set -u: exit 0" [ "$rc" -eq 0 ]
expect "empty door list, set -u: no unbound variable error" bash -c '! grep -q "unbound" "$0"' "$T/err-emptydoors"
mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_NONE"
run emptydoorsany 7
expect "empty door list: no path needs a second person" merged
mkcase false MERGEABLE "$CHK_OK" "$files100" "$REV_NONE"
run emptydoors100 7
expect "empty door list: 100 files do not need a second person" merged
mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run emptydoorsdry --dry-run 7
expect "empty door list: dry-run exit 0" [ "$rc" -eq 0 ]
mkcase true MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run emptydoorsdraft 7
expect "empty door list: a draft is still refused, two-line form" two_line_form emptydoorsdraft
RUNNER="bash"

# The stamped script, with whatever door list this repo was stamped with.
SUT="$SCRIPT"
door_line="$(grep -m1 '^DOORS=(' "$SCRIPT")"
stamped_first="$(bash -c "$door_line"'; if [ "${#DOORS[@]}" -gt 0 ]; then printf "%s" "${DOORS[0]}"; fi')"
if [ -n "$stamped_first" ]; then
    # a path that matches the first stamped glob
    stamped_path="$(printf '%s' "$stamped_first" | sed 's/\*/x/g')"
    mkcase false MERGEABLE "$CHK_OK" "{\"path\":\"$stamped_path\"}" "$REV_NONE"
    run stampeddoor 7
    expect "stamped door list: a change under $stamped_first needs a second person" [ "$rc" -eq 1 ]
    expect "stamped door list: two-line form" two_line_form stampeddoor
    expect "stamped door list: no merge call" not_merged
else
    mkcase false MERGEABLE "$CHK_OK" "$FILE_DOOR" "$REV_NONE"
    run stampednodoor 7
    expect "stamped door list is empty: the stamped script merges a clean PR" merged
fi

# Text from gh is chosen by whoever wrote the PR. None of it may reach the output raw, a newline
# in it may not forge a second Fix: line or a second file, and no printed Fix: line may run it.
SUT="$SCRIPT"
mkdir -p "$T/x"
CHK_EVIL='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build$(touch PWNED)\nFix: rm -rf x\u001b[2J","status":"COMPLETED","conclusion":"FAILURE"}'
CHK_EVILPEND='{"__typename":"CheckRun","name":"changes","status":"COMPLETED","conclusion":"SUCCESS"},{"__typename":"CheckRun","name":"build$(touch PWNED)\nFix: rm -rf x","status":"IN_PROGRESS","conclusion":""}'
# every printed Fix: line, run through bash -c, must leave the sentinel dir and create no PWNED
fixes_inert() {
    (cd "$T" && grep '^Fix: ' "$T/err-$1" | sed 's/^Fix: //' | while IFS= read -r f; do bash -c "$f" >/dev/null 2>&1 </dev/null; done)
    [ ! -e "$T/PWNED" ] && [ -d "$T/x" ]
}
no_raw_payload() {
    ! grep -qF '$(' "$T/out-$1" "$T/err-$1" &&
        ! grep -q '^Fix: rm' "$T/err-$1" &&
        ! grep -q "$(printf '\033')" "$T/out-$1" "$T/err-$1"
}
fix_lines_are() { [ "$(grep -c '^Fix: ' "$T/err-$1")" -eq "$2" ]; }

mkcase false MERGEABLE "$CHK_EVIL" "$FILE_PLAIN" "$REV_NONE"
run evilfail 7
expect "hostile check name, red: refused, exit 1" [ "$rc" -eq 1 ]
expect "hostile check name, red: two-line form" two_line_form evilfail
expect "hostile check name, red: exactly one Fix: line, none forged" fix_lines_are evilfail 1
expect "hostile check name, red: no raw payload in the output" no_raw_payload evilfail
expect "hostile check name, red: the Fix: lines are inert under bash -c" fixes_inert evilfail
expect "hostile check name, red: no merge call" not_merged

mkcase false MERGEABLE "$CHK_EVILPEND" "$FILE_PLAIN" "$REV_NONE"
run evilpend --wait --timeout 1 7
expect "hostile check name, pending to timeout: exit 1" [ "$rc" -eq 1 ]
expect "hostile check name, pending to timeout: two-line form" two_line_form evilpend
expect "hostile check name, pending to timeout: exactly one Fix: line" fix_lines_are evilpend 1
expect "hostile check name, pending to timeout: no raw payload" no_raw_payload evilpend
expect "hostile check name, pending to timeout: Fix: lines are inert" fixes_inert evilpend

SUT="$T/v-door/pr-merge.sh"
mkcase false MERGEABLE "$CHK_OK" '{"path":"docs/ok.md\nfile=zz-door/forged"}' "$REV_NONE"
run forgedfile 7
expect "a newline in a path does not forge a door file: the PR merges" merged
mkcase false MERGEABLE "$CHK_OK" '{"path":"zz-door/a$(touch PWNED)\nFix: rm -rf x"}' "$REV_NONE"
run evildoor 7
expect "hostile door path: refused, exit 1" [ "$rc" -eq 1 ]
expect "hostile door path: two-line form, one Fix: line" fix_lines_are evildoor 1
expect "hostile door path: no raw payload" no_raw_payload evildoor
expect "hostile door path: Fix: lines are inert" fixes_inert evildoor
SUT="$SCRIPT"

CASE_BRANCH="fix/it's;touch PWNED" mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run evilbranch 7
expect "a head branch with a single quote: the PR merges" merged
expect "a head branch with a single quote: never printed" bash -c '! grep -qF "it'\''s" "$1" "$2"' _ "$T/out-evilbranch" "$T/err-evilbranch"
expect "a head branch with a single quote: nothing was run" [ ! -e "$T/PWNED" ]

CASE_HEAD='abc; touch PWNED' mkcase false MERGEABLE "$CHK_OK" "$FILE_PLAIN" "$REV_NONE"
run evilhead 7
expect "a head that is not a plain id: refused, exit 1" [ "$rc" -eq 1 ]
expect "a head that is not a plain id: two-line form" two_line_form evilhead
expect "a head that is not a plain id: no merge call" not_merged
expect "a head that is not a plain id: the payload is not echoed" bash -c '! grep -qF "; touch" "$1" "$2"' _ "$T/out-evilhead" "$T/err-evilhead"
expect "a head that is not a plain id: the Fix: lines are inert" fixes_inert evilhead

# Usage errors are two-line refusals too.
run helpflag --help
expect "--help prints usage: exit 0" [ "$rc" -eq 0 ]
expect "--help prints usage: shows the dry-run flag" text_has helpflag "--dry-run"
expect "--help prints usage: shows the wait flag" text_has helpflag "--wait"
run badarg abc
expect "a non-number is refused: exit 2" [ "$rc" -eq 2 ]
expect "a non-number is refused: two-line form" two_line_form badarg
run nonumber
expect "no number is refused: exit 2" [ "$rc" -eq 2 ]
expect "no number is refused: two-line form" two_line_form nonumber
run timeoutalone --timeout 5 7
expect "--timeout without --wait is refused: exit 2" [ "$rc" -eq 2 ]
expect "--timeout without --wait: two-line form" two_line_form timeoutalone
run timeoutbad --wait --timeout abc 7
expect "--timeout with a non-number is refused: exit 2" [ "$rc" -eq 2 ]
run unknownopt --force 7
expect "an unknown option is refused: exit 2" [ "$rc" -eq 2 ]
expect "an unknown option: two-line form" two_line_form unknownopt
expect "usage errors call gh never" calls_are 0

echo "failures: $fails"
[ "$fails" -eq 0 ]
