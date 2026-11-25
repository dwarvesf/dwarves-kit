#!/usr/bin/env bash
# test-stamp-queue.sh -- the work-queue group of the team stamp: the task issue form, the PR
# template, scripts/issues-from-rows.sh and its generated test, stamped into scratch repos.
# The issue form is checked by structure with awk and grep on the keys the form needs: this suite
# assumes no python or ruby YAML parser on the machine, so it reads the file as text.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }
expect() { local label="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$label"; else no "$label"; fi; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/test-stamp-queue.XXXXXX")" || exit 1
KIT_PATTERN='\.claude/dwarves-kit|CLAUDE_PLUGIN_ROOT|KIT_ROOT|lib/gate/|/bin/(gate|classify|wrap|board)([^A-Za-z0-9_-]|$)|/Users/[A-Za-z0-9._-]+|/home/[A-Za-z0-9._-]+'
EM="$(printf '\342\200\224')"; EN="$(printf '\342\200\223')"
TPL=templates/team-stamp
FORM="$TPL/files/.github/ISSUE_TEMPLATE/task.yml"
PRT="$TPL/files/.github/pull_request_template.md"
SCR="$TPL/files/scripts/issues-from-rows.sh.tpl"
TST="$TPL/files/scripts/test-issues-from-rows.sh.tpl"
newrepo() { local d; d="$(mktemp -d "$WORK/r.XXXXXX")" && git -C "$d" init -q 2>/dev/null && echo "$d"; }

# 1. manifest
M="$TPL/manifest.d/50-queue.tsv"
expect "manifest exists" [ -f "$M" ]
expect "manifest: every row has five tab-separated columns" bash -c "grep -v '^#' '$M' | grep -v '^\$' | awk -F'\t' 'NF != 5 { exit 1 }'"
expect "manifest: the two scripts declare BOARD_FILE and DECISION_TAG" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$3 ~ /issues-from-rows/ { n++; if (\$5 != \"BOARD_FILE,DECISION_TAG\") bad = 1 } END { exit !(n == 2 && !bad) }'"
expect "manifest: the form and the PR template are plain copies with no key" bash -c "grep -v '^#' '$M' | awk -F'\t' '\$3 ~ /task.yml|pull_request_template/ { n++; if (\$1 != \"copy\" || \$5 != \"-\") bad = 1 } END { exit !(n == 2 && !bad) }'"

# 2. the issue form, read as text (no YAML parser is assumed)
expect "form: no tab character (YAML forbids it)" bash -c "! grep -q \"\$(printf '\\t')\" '$FORM'"
expect "form: top-level name, description and body keys" bash -c "grep -q '^name: .' '$FORM' && grep -q '^description: .' '$FORM' && grep -q '^body:\$' '$FORM'"
# one record per body item: type, id, label, required
awk '
  /^  - type: / { if (n) print type "|" id "|" label "|" req; n++; type = $3; id = ""; label = ""; req = "no"; next }
  /^      label: / { sub(/^      label: /, ""); label = $0; next }
  /^    id: / { id = $2; next }
  /^      required: true/ { req = "yes"; next }
  END { if (n) print type "|" id "|" label "|" req }' "$FORM" >"$WORK/form.items"
expect "form: five body items, a markdown note then four textareas in order" [ "$(cut -d'|' -f1,2 "$WORK/form.items" | tr '\n' ' ')" = "markdown| textarea|goal textarea|done_when textarea|scope textarea|notes " ]
expect "form: labels are Goal, Done when, Scope, Notes" [ "$(awk -F'|' 'NR > 1 { printf "%s,", $3 }' "$WORK/form.items")" = "Goal,Done when,Scope,Notes," ]
expect "form: Goal and Done when are required, Scope and Notes are not" [ "$(awk -F'|' 'NR > 1 { printf "%s,", $4 }' "$WORK/form.items")" = "yes,yes,no,no," ]
expect "form: every textarea carries an attributes block with a label" bash -c "[ \"\$(grep -c '^    attributes:\$' '$FORM')\" -eq 5 ] && [ \"\$(grep -c '^      label: ' '$FORM')\" -eq 4 ]"
expect "form: the note names the four headings the form writes" bash -c "grep -q '### Goal.*### Done when.*### Scope.*### Notes' '$FORM'"
expect "form: Notes says optional" bash -c "grep -A3 'id: notes' '$FORM' | grep -qi optional"

# 3. the PR template
expect "PR template: a Closes # line" grep -q '^Closes #' "$PRT"
expect "PR template: the three sections" bash -c "[ \"\$(grep -c '^## ' '$PRT')\" -eq 3 ] && grep -q '^## What\$' '$PRT' && grep -q '^## Proof\$' '$PRT' && grep -q '^## Bookkeeping\$' '$PRT'"
expect "PR template: names the opt-out marker lines pr-shape reads" bash -c "grep -q 'no-board-row:' '$PRT' && grep -q 'no-changelog:' '$PRT' && grep -q 'no-proof:' '$PRT' && grep -q 'no-rule-mirror:' '$PRT'"

# 4. the script's issue headings are the form's labels
expect "script body headings match the form labels" bash -c "[ \"\$(grep -Eo '^ *(body=.)?### (Goal|Done when|Scope)\$' '$SCR' | sed 's/^ *body=.//; s/^ *//' | tr '\n' ',')\" = '### Goal,### Done when,### Scope,' ]"

# 5. stamp with defaults (no board file)
R1="$(newrepo)"
bash lib/stamp.sh --only queue --default-branch main --owner testowner "$R1" >"$WORK/s1.out" 2>&1
expect "stamp the queue group, defaults" [ $? -eq 0 ]
for f in .github/ISSUE_TEMPLATE/task.yml .github/pull_request_template.md scripts/issues-from-rows.sh scripts/test-issues-from-rows.sh; do
  expect "created: $f" [ -f "$R1/$f" ]
done
expect "both scripts are executable" bash -c "[ -x '$R1/scripts/issues-from-rows.sh' ] && [ -x '$R1/scripts/test-issues-from-rows.sh' ]"
expect "the form and the PR template are byte-identical to the templates (agnostic)" bash -c "cmp -s '$FORM' '$R1/.github/ISSUE_TEMPLATE/task.yml' && cmp -s '$PRT' '$R1/.github/pull_request_template.md'"
expect "no {{KEY}} is left in the stamped scripts" bash -c "! grep -q '{{' '$R1/scripts/issues-from-rows.sh' '$R1/scripts/test-issues-from-rows.sh'"
expect "defaults: the board default is empty" grep -q "^BOARD_DEFAULT=''\$" "$R1/scripts/issues-from-rows.sh"
expect "defaults: the decision tag is decision" grep -q "^DECISION_TAG='decision'\$" "$R1/scripts/issues-from-rows.sh"
(cd "$R1" && bash scripts/issues-from-rows.sh) >"$WORK/e1.out" 2>"$WORK/e1.err"
expect "defaults: with no board file the script exits 0" [ $? -eq 0 ]
expect "defaults: with no board file it prints the one line" bash -c "[ \"\$(cat '$WORK/e1.out')\" = 'issues-from-rows: no board file set; nothing to read' ] && [ ! -s '$WORK/e1.err' ]"
(cd "$R1" && bash scripts/test-issues-from-rows.sh) >"$WORK/t1.out" 2>&1
expect "defaults: the generated test passes" [ $? -eq 0 ]
expect "defaults: the generated test ran many cases" bash -c "[ \"\$(grep -c '^PASS' '$WORK/t1.out')\" -ge 60 ]"

# 6. idempotent
bash lib/stamp.sh --only queue --default-branch main --owner testowner "$R1" >"$WORK/s2.out" 2>&1
expect "second run prints only unchanged" bash -c "[ -s '$WORK/s2.out' ] && ! grep -v '^unchanged: ' '$WORK/s2.out'"

# 7. stamp with non-default values
R2="$(newrepo)"
bash lib/stamp.sh --only queue --default-branch master --owner testowner --board-file docs/BOARD.md --decision-tag waiting "$R2" >"$WORK/s3.out" 2>&1
expect "stamp the queue group, custom values" [ $? -eq 0 ]
expect "custom: the board default and the decision tag are rendered" bash -c "grep -q \"^BOARD_DEFAULT='docs/BOARD.md'\$\" '$R2/scripts/issues-from-rows.sh' && grep -q \"^DECISION_TAG='waiting'\$\" '$R2/scripts/issues-from-rows.sh'"
expect "custom: the default board path is in the usage header" grep -q 'default docs/BOARD.md' "$R2/scripts/issues-from-rows.sh"
(cd "$R2" && bash scripts/test-issues-from-rows.sh) >"$WORK/t2.out" 2>&1
expect "custom: the generated test passes" [ $? -eq 0 ]

# 8. the stamped script reads the stamped board, skips the stamped decision tag, and applies labels (fake gh)
FAKE="$WORK/fake"; mkdir -p "$FAKE/bin" "$R2/docs"
cat >"$FAKE/bin/gh" <<'EOF'
#!/bin/bash
case "$1 $2" in
"label list") printf 'ready\n' ;;
"label create") printf 'label %s\n' "$3" >>"$FAKE_LOG" ;;
"issue list") ;;
"issue create") printf 'issue\n' >>"$FAKE_LOG"; echo "https://github.example/issues/1" ;;
*) exit 1 ;;
esac
EOF
chmod +x "$FAKE/bin/gh"
printf '| ID | Item | Notes | Status |\n|---|---|---|---|\n| ID-001 | One | Do it. Done when: it is done. #alice | queued |\n| ID-002 | Two | Pick. Done when: chosen. #waiting #P0 #alice | queued |\n' >"$R2/docs/BOARD.md"
: >"$FAKE/log"
(cd "$R2" && FAKE_LOG="$FAKE/log" PATH="$FAKE/bin:$PATH" bash scripts/issues-from-rows.sh --apply) >"$WORK/a1.out" 2>&1
expect "stamped board: one issue for the ready row, none for the decision row" bash -c "[ \"\$(grep -c '^issue\$' '$FAKE/log')\" -eq 1 ]"
expect "stamped board: the two missing labels are created, the present one is not" bash -c "grep -qx 'label one-way-door' '$FAKE/log' && grep -qx 'label blocked' '$FAKE/log' && ! grep -qx 'label ready' '$FAKE/log'"

# 9. portability and scope of the template text
for f in "$SCR" "$TST" "$FORM" "$PRT"; do
  expect "$f: no kit path and no home path" bash -c "! grep -Eq '$KIT_PATTERN' '$f'"
  expect "$f: no em or en dash" bash -c "! grep -q -e '$EM' -e '$EN' '$f'"
  expect "$f: no bare 40 or 64 hex run" bash -c "! grep -Eq '[0-9a-f]{40}' '$f'"
done
for f in "$SCR" "$TST"; do
  expect "$f: no python3, jq or GNU-only construct" bash -c "! grep -Eq 'python3|(^|[^-A-Za-z])jq |grep -P|sed -r|readarray|mapfile|declare -A|\\$\\{[A-Za-z_]+(,,|\\^\\^)' '$f'"
done
expect "script: never evaluates row text" bash -c "! grep -v '^ *#' '$SCR' | grep -Eq '(^|[^A-Za-z_])eval '"
if command -v shellcheck >/dev/null 2>&1; then
  expect "shellcheck -S warning on the stamped scripts" shellcheck -S warning "$R2/scripts/issues-from-rows.sh" "$R2/scripts/test-issues-from-rows.sh" "$R1/scripts/issues-from-rows.sh" "$R1/scripts/test-issues-from-rows.sh"
else
  echo "note: shellcheck not installed, skipped"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
