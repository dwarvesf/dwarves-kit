#!/usr/bin/env bash
# test-issues-from-rows.sh - run issues-from-rows.sh against a fixture board and a fake gh on
# PATH. The fake serves a canned issue list and a canned label list, records every `issue create`
# and `label create` call one argument per line, and adds what was created to its lists, so a
# second run shows the idempotence. No network. Leaves its temp dir behind; the path is printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/issues-from-rows.sh"
STAMPED_BOARD='{{BOARD_FILE}}'
TAG='{{DECISION_TAG}}'
T="$(mktemp -d "${TMPDIR:-/tmp}/issues-from-rows-test.XXXXXX")"
echo "test dir: $T"

mkdir -p "$T/bin"
cat >"$T/bin/gh" <<'EOF'
#!/bin/bash
# fake gh: `issue list` and `label list` print canned files; `issue create` and `label create`
# record their arguments and add what they made to the canned file.
case "$1 $2" in
"issue list")
    printf '%s\n' "$*" >>"$FAKE_T/list-calls"
    [ -f "$FAKE_T/list-fails" ] && { echo "boom" >&2; exit 1; }
    cat "$FAKE_T/existing"
    ;;
"issue create")
    printf 'CALL issue\n' >>"$FAKE_T/calls"
    title=""
    while [ $# -gt 0 ]; do
        printf 'ARG:%s\n' "$1" >>"$FAKE_T/calls"
        [ "$1" = "--title" ] && title="$2"
        shift
    done
    printf '%s\n' "$title" >>"$FAKE_T/existing"
    echo "https://github.example/issues/1"
    ;;
"label list")
    [ -f "$FAKE_T/label-list-fails" ] && { echo "nolabels" >&2; exit 1; }
    cat "$FAKE_T/labels"
    ;;
"label create")
    printf 'CALL label\nLABEL:%s\n' "$3" >>"$FAKE_T/calls"
    [ -f "$FAKE_T/label-create-fails" ] && { echo "denied" >&2; exit 1; }
    printf '%s\n' "$3" >>"$FAKE_T/labels"
    ;;
*) exit 1 ;;
esac
EOF
chmod +x "$T/bin/gh"
export FAKE_T="$T"
export PATH="$T/bin:$PATH"

# Fixture board. Row shape: | ID | Item | Notes | Status |.
cat >"$T/BACKLOG.md" <<'EOF'
# Backlog

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | Plain tagged row | Make the thing work. Done when: the test passes. #P1 #alice #S | queued |
| ID-002 | Tagged row with no check | Make the other thing work. #P1 #alice #S | queued |
| ID-004 | Shipped row | Was done. Done when: it ran. #P1 #alice #S | shipped [(#5)] |
| ID-005 | Open issue row | Has an issue already. Done when: it exists. #P1 #bob #S | queued |
| ID-006 | Closed issue row | Had an issue, now closed. Done when: it was closed. #P1 #bob #S | queued |
| ID-007 | Fix the "quoted" thing with a `tick` and $HOME and 'single' | Goal with $(touch PWNED) and `touch PWNED2` inside. Done when: run $(touch PWNED3) and expect "ok". #P1 #carol #S | queued |
| ID-008 | Agent row | Unassigned build work. Done when: it builds. #P1 #agent #S | queued |
| ID-009 | Tags before the login | Reorder the tags. Done when: the order is right. #P1 #critical #dave-x #M | queued |
| ID-070 | Prefix neighbour | Its id is a prefix of another issue id. Done when: it is created. #P1 #erin #S | queued |
| ID-010 | Parked row | Waiting. Done when: the trigger fires. #P2 #alice #S | parked [waiting on X] |
EOF
printf '| ID-003 | Decision row | Pick a price. Done when: the owner decides. #P0 #%s #S | queued |\n' "$TAG" >>"$T/BACKLOG.md"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

reset() { # reset: a fresh call log, the canned issue list, the canned label list
    : >"$T/calls"
    : >"$T/list-calls"
    rm -f "$T/list-fails" "$T/label-list-fails" "$T/label-create-fails"
    cat >"$T/existing" <<'EOF'
ID-005: Open issue row
ID-006: Closed issue row
ID-0701: A different row whose id starts with ID-070
Some plain title
EOF
    printf '%s\n' bug enhancement >"$T/labels"
}
# run <name> <args...>: output in $T/out-<name> (stdout), $T/err-<name> (stderr), exit code in $rc
run() {
    local name="$1"
    shift
    rc=0
    (cd "$T" && bash "$SCRIPT" --board-file "$T/BACKLOG.md" "$@") >"$T/out-$name" 2>"$T/err-$name" || rc=$?
}
has() { grep -Fq -- "$2" "$T/out-$1"; }
hasnt() { ! grep -Fq -- "$2" "$T/out-$1"; }
errhas() { grep -Fq -- "$2" "$T/err-$1"; }
issue_calls() { grep -c '^CALL issue$' "$T/calls" || true; }
label_calls() { grep -c '^CALL label$' "$T/calls" || true; }
no_calls() { [ ! -s "$T/calls" ]; }
called_with() { grep -Fxq -- "ARG:$1" "$T/calls"; }
# pair <name>: stderr is exactly the two-line refusal
pair() {
    [ "$(wc -l <"$T/err-$1" | tr -d ' ')" -eq 2 ] \
        && sed -n 1p "$T/err-$1" | grep -q '^issues-from-rows: ' \
        && sed -n 2p "$T/err-$1" | grep -q '^Fix: '
}
# body_of_call <title>: the --body argument of the call with that title
body_of_call() {
    awk -v want="ARG:$1" '
        $0 == "CALL issue" { t = ""; on = 0 }
        $0 == "ARG:--title" { getline; t = $0; next }
        $0 == "ARG:--body" { on = (t == want); first = 1; next }
        /^ARG:--(label|assignee|title)$/ { on = 0 }
        on { line = $0; if (first) { sub(/^ARG:/, "", line); first = 0 } print line }' "$T/calls"
}

# 1. dry run is the default and creates nothing
reset
run dry
expect "default run: exit 0" [ "$rc" -eq 0 ]
expect "default run: creates nothing" no_calls
expect "default run: lists a tagged row" has dry "would create: ID-001: Plain tagged row (assignee alice, label ready)"
expect "default run: summary says dry run" has dry "issues-from-rows: dry run, 4 to create, 2 with an issue, 1 without Done when"
expect "default run: prints the label step for each missing label" bash -c 'grep -Fq "would create label: ready" "$1" && grep -Fq "would create label: one-way-door" "$1" && grep -Fq "would create label: blocked" "$1"' _ "$T/out-dry"
reset
run dry2 --dry-run
expect "--dry-run: creates nothing" no_calls

# 2. skips
expect "row with no Done when: skipped and named" has dry "skip: ID-002 has a #alice tag but no Done when: text"
expect "decision row: not listed" hasnt dry "ID-003"
expect "shipped row: not listed" hasnt dry "ID-004"
expect "parked row: not listed" hasnt dry "ID-010"
expect "#agent row: not listed" hasnt dry "ID-008"
expect "row with an open issue: skipped" has dry "skip: ID-005 already has an issue"
expect "row with a closed issue: skipped" has dry "skip: ID-006 already has an issue"
expect "an issue ID-0701 does not hide ID-070" has dry "would create: ID-070: Prefix neighbour"
expect "login found after other tags" has dry "would create: ID-009: Tags before the login (assignee dave-x, label ready)"

# 3. apply creates the labels first, then the right issues, with the right arguments
reset
run apply --apply
expect "--apply: exit 0" [ "$rc" -eq 0 ]
expect "--apply: three labels created" [ "$(label_calls)" -eq 3 ]
expect "--apply: label ready created" grep -Fxq "LABEL:ready" "$T/calls"
expect "--apply: label one-way-door created" grep -Fxq "LABEL:one-way-door" "$T/calls"
expect "--apply: label blocked created" grep -Fxq "LABEL:blocked" "$T/calls"
expect "--apply: every label is created before the first issue" bash -c 'awk "/^CALL issue\$/ { seen = 1 } /^CALL label\$/ { if (seen) bad = 1 } END { exit bad }" "$1"' _ "$T/calls"
expect "--apply: four issues created" [ "$(issue_calls)" -eq 4 ]
expect "--apply: lists the issues once" [ "$(wc -l <"$T/list-calls" | tr -d ' ')" -eq 1 ]
expect "--apply: the issue list covers every state" grep -Fq -- "--state all" "$T/list-calls"
expect "--apply: title is ID-NNN: title" called_with "ID-001: Plain tagged row"
expect "--apply: label ready on the issue" called_with "ready"
expect "--apply: assignee is the login" called_with "alice"
body="$(body_of_call "ID-001: Plain tagged row")"
expect "body: Goal section holds the notes before Done when" grep -Fxq -- "Make the thing work." <<<"$body"
expect "body: Done when section holds the check" grep -Fxq -- "the test passes." <<<"$body"
expect "body: Scope names the board row and the board file" grep -Fxq -- "Board row ID-001 in $T/BACKLOG.md" <<<"$body"
expect "body: sections match the task form, in order" [ "$(grep -E '^### ' <<<"$body" | tr '\n' ',')" = "### Goal,### Done when,### Scope," ]
expect "body: tags are not copied into the text" bash -c '! grep -Fq "#alice" <<<"$1"' _ "$body"

# 4. untrusted text survives intact and never runs
q_title='ID-007: Fix the "quoted" thing with a `tick` and $HOME and '"'single'"
expect "quotes, backtick, dollar: title arrives intact" called_with "$q_title"
qbody="$(body_of_call "$q_title")"
expect "untrusted body: command substitution kept as text" grep -Fq -- '$(touch PWNED)' <<<"$qbody"
expect "untrusted body: backticks kept as text" grep -Fq -- '`touch PWNED2`' <<<"$qbody"
expect "untrusted body: nothing executed in the test dir" bash -c '! ls "$1"/PWNED* >/dev/null 2>&1' _ "$T"
expect "untrusted body: nothing executed in the working dir" bash -c '! ls PWNED* >/dev/null 2>&1'

# 5. idempotence: the second --apply sees the first run's titles and labels
run apply2 --apply
expect "second --apply: exit 0" [ "$rc" -eq 0 ]
expect "second --apply: creates no more issues" [ "$(issue_calls)" -eq 4 ]
expect "second --apply: creates no more labels" [ "$(label_calls)" -eq 3 ]
expect "second --apply: every row has an issue" has apply2 "issues-from-rows: 0 created, 6 with an issue, 1 without Done when, 0 failed"

# 6. labels that already exist are left alone
reset
printf '%s\n' ready one-way-door blocked >"$T/labels"
run haslabels --apply
expect "labels present: none created" [ "$(label_calls)" -eq 0 ]
expect "labels present: issues still created" [ "$(issue_calls)" -eq 4 ]
reset
printf '%s\n' ready >"$T/labels"
run onelabel
expect "one label present: only the other two are named in the dry run" bash -c '! grep -Fq "would create label: ready" "$1" && grep -Fq "would create label: blocked" "$1"' _ "$T/out-onelabel"

# 7. failures: each is the two-line refusal
reset
: >"$T/list-fails"
run listfail --apply
expect "gh issue list fails: exit 1" [ "$rc" -eq 1 ]
expect "gh issue list fails: nothing created" [ "$(issue_calls)" -eq 0 ]
expect "gh issue list fails: says why" errhas listfail "gh issue list failed"
expect "gh issue list fails: rule then Fix" pair listfail
reset
: >"$T/label-list-fails"
run labellist --apply
expect "gh label list fails: exit 1, nothing created" bash -c '[ "$1" -eq 1 ] && [ ! -s "$2" ]' _ "$rc" "$T/calls"
expect "gh label list fails: rule then Fix" pair labellist
reset
: >"$T/label-create-fails"
run labelcreate --apply
expect "gh label create fails: exit 1, no issue created" bash -c '[ "$1" -eq 1 ] && [ "$(grep -c "^CALL issue\$" "$2" || true)" -eq 0 ]' _ "$rc" "$T/calls"
expect "gh label create fails: rule then Fix" pair labelcreate
run badarg --nope
expect "unknown argument: exit 2" [ "$rc" -eq 2 ]
expect "unknown argument: rule then Fix" pair badarg
rc=0
(cd "$T" && bash "$SCRIPT" --board-file "$T/missing.md") >"$T/out-nofile" 2>"$T/err-nofile" || rc=$?
expect "missing board file: exit 1" [ "$rc" -eq 1 ]
expect "missing board file: rule then Fix" pair nofile

# 8. no gh on PATH
mkdir -p "$T/bin-nogh"
for tool in bash env git awk sed grep cat printf tr wc dirname head; do
    p="$(command -v "$tool" 2>/dev/null || true)"
    case "$p" in /*) ln -sf "$p" "$T/bin-nogh/$tool" ;; esac
done
rc=0
(cd "$T" && PATH="$T/bin-nogh" bash "$SCRIPT" --board-file "$T/BACKLOG.md") >"$T/out-nogh" 2>"$T/err-nogh" || rc=$?
expect "no gh: exit 1" [ "$rc" -eq 1 ]
expect "no gh: says so, rule then Fix" pair nogh
expect "no gh: names gh" errhas nogh "gh is not installed"

# 9. an empty board file value: one line, exit 0, gh never called
reset
run empty --board-file ""
expect "empty board file: exit 0" [ "$rc" -eq 0 ]
expect "empty board file: one line" [ "$(wc -l <"$T/out-empty" | tr -d ' ')" -eq 1 ]
expect "empty board file: says there is nothing to read" has empty "no board file set; nothing to read"
expect "empty board file: gh never called" bash -c '[ ! -s "$1" ] && [ ! -s "$2" ]' _ "$T/calls" "$T/list-calls"
rc=0
(cd "$T" && PATH="$T/bin-nogh" bash "$SCRIPT" --board-file "") >"$T/out-empty2" 2>&1 || rc=$?
expect "empty board file: exit 0 even with no gh installed" [ "$rc" -eq 0 ]

# 10. the stamped default board file
reset
mkdir -p "$T/repo/scripts"
git -C "$T/repo" init -q 2>/dev/null
cp "$SCRIPT" "$T/repo/scripts/issues-from-rows.sh"
if [ -z "$STAMPED_BOARD" ]; then
    rc=0
    (cd "$T/repo" && bash scripts/issues-from-rows.sh) >"$T/out-default" 2>&1 || rc=$?
    expect "stamped with no board file: exit 0 and the one-line note" bash -c '[ "$1" -eq 0 ] && grep -Fq "no board file set; nothing to read" "$2"' _ "$rc" "$T/out-default"
else
    mkdir -p "$T/repo/$(dirname "$STAMPED_BOARD")"
    cp "$T/BACKLOG.md" "$T/repo/$STAMPED_BOARD"
    rc=0
    (cd "$T/repo/scripts" && bash issues-from-rows.sh --apply) >"$T/out-default" 2>&1 || rc=$?
    expect "stamped board file: read with no argument, from a subdirectory" bash -c '[ "$1" -eq 0 ] && grep -Fq "created: ID-001: Plain tagged row" "$2"' _ "$rc" "$T/out-default"
    expect "stamped board file: the Scope line names it" grep -Fxq -- "Board row ID-001 in $STAMPED_BOARD" "$T/calls"
fi

echo "failures: $fails"
[ "$fails" -eq 0 ]
