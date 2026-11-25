#!/usr/bin/env bash
# issues-from-rows.sh - create one GitHub issue per queued board row that is ready for an agent.
#
#   bash scripts/issues-from-rows.sh                       dry run: print what would be created
#   bash scripts/issues-from-rows.sh --dry-run             the same, spelled out
#   bash scripts/issues-from-rows.sh --apply               create the labels and the issues
#   bash scripts/issues-from-rows.sh --board-file PATH     board file, default {{BOARD_FILE}}
#
# The board is a Markdown table whose rows read `| ID-NNN | item | notes | status |`. A row
# qualifies when its status starts with `queued`, its notes carry a `Done when:` text, and it has
# a #<github-login> tag. A row tagged #{{DECISION_TAG}} waits on a human and is skipped. The issue gets:
#   title     ID-NNN: <row title>
#   body      ### Goal (the notes before Done when:), ### Done when, ### Scope
#   label     ready
#   assignee  the login from the tag
# The labels ready, one-way-door and blocked must exist: --apply creates any that is missing
# first (the dry run prints that step). A row is skipped when an open or closed issue whose
# title starts with `ID-NNN:` exists, so a rerun creates nothing new. With no board file set it
# prints one line and exits 0. Row text is untrusted: it reaches gh only as an argument, never
# through eval or an unquoted expansion. Needs gh, logged in. bash 3.2 safe.
set -euo pipefail

BOARD_DEFAULT='{{BOARD_FILE}}'
DECISION_TAG='{{DECISION_TAG}}'

refuse() { # refuse <rule> <fix>: the two-line refusal on stderr
    printf 'issues-from-rows: %s\nFix: %s\n' "$1" "$2" >&2
}
first_line() { printf '%s\n' "$1" | head -n 1; }

usage() {
    cat <<'EOF2'
Usage: issues-from-rows.sh [--dry-run | --apply] [--board-file PATH] [--help]

One issue per queued row that has a #<github-login> tag and a Done when: text.
Dry run is the default and creates nothing.
EOF2
}

apply=0
board="$BOARD_DEFAULT"
while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) apply=0; shift ;;
    --apply) apply=1; shift ;;
    --board-file)
        [ $# -ge 2 ] || { refuse "--board-file needs a path" "bash scripts/issues-from-rows.sh --help"; exit 2; }
        board="$2"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    *) refuse "unknown argument: $1" "bash scripts/issues-from-rows.sh --help"; exit 2 ;;
    esac
done

if [ -z "$board" ]; then
    echo "issues-from-rows: no board file set; nothing to read"
    exit 0
fi

command -v gh >/dev/null 2>&1 || { refuse "gh is not installed" "brew install gh   # or see https://cli.github.com, then: gh auth login"; exit 1; }
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
case "$board" in
/*) board_path="$board" ;;
*) board_path="$root/$board" ;;
esac
[ -f "$board_path" ] || {
    refuse "board file not found: $board" "mkdir -p \"\$(dirname '$board_path')\" && printf '| ID | Item | Notes | Status |\\n|---|---|---|---|\\n' > '$board_path'"
    exit 1
}

# Labels first: a missing label would make every issue create fail.
if ! labels="$(gh label list --limit 200 --json name --jq '.[].name' </dev/null 2>&1)"; then
    refuse "gh label list failed: $(first_line "$labels")" "gh auth status"
    exit 1
fi
make_label() { # make_label <name> <color> <description>
    if printf '%s\n' "$labels" | grep -Fxq -- "$1"; then return 0; fi
    if [ "$apply" -eq 0 ]; then
        echo "would create label: $1"
        return 0
    fi
    if out="$(gh label create "$1" --color "$2" --description "$3" </dev/null 2>&1)"; then
        echo "created label: $1"
    else
        refuse "gh label create $1 failed: $(first_line "$out")" "gh auth status"
        exit 1
    fi
}
make_label ready 0E8A16 "Goal and Done when are filled; an agent can pick this up"
make_label one-way-door B60205 "Hard to undo; needs a second person before merge"
make_label blocked D93F0B "Waiting on something outside this issue"

# Titles of every issue, open and closed, one per line.
if ! existing="$(gh issue list --state all --limit 500 --json number,title --jq '.[].title' </dev/null 2>&1)"; then
    refuse "gh issue list failed: $(first_line "$existing")" "gh auth status"
    exit 1
fi
if [ -n "$existing" ] && [ "$(printf '%s\n' "$existing" | wc -l)" -ge 500 ]; then
    echo "issues-from-rows: note: 500 issues listed, older ones may be missing, so a rerun could duplicate" >&2
fi

# One record per candidate, tab separated:
#   ROW<TAB>id<TAB>login<TAB>title<TAB>goal<TAB>done_when
#   NODONE<TAB>id<TAB>login      queued and tagged, but no Done when: text
records="$(DECISION_TAG="$DECISION_TAG" awk -F'|' '
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function strip_tags(s,   n, w, i, out) {
  n = split(s, w, /[ \t]+/); out = ""
  for (i = 1; i <= n; i++) {
    if (w[i] ~ /^#[A-Za-z][A-Za-z0-9_-]*[.,;]?$/) continue
    out = out (out == "" ? "" : " ") w[i]
  }
  return out
}
/^\| ID-[0-9]+ / {
  id = trim($2); item = trim($3); notes = trim($4); status = trim($5)
  split(status, st, /[ \[]/)
  if (st[1] != "queued") next
  n = split(notes, w, /[ \t]+/); login = ""; wait = 0
  for (i = 1; i <= n; i++) {
    t = w[i]
    if (t !~ /^#/) continue
    gsub(/[.,;)]+$/, "", t)
    if (t == "#" ENVIRON["DECISION_TAG"]) { wait = 1; continue }
    if (t ~ /^#(agent|P[0-3]|later|S|M|L|critical)$/) continue
    if (login == "" && t ~ /^#[A-Za-z0-9][A-Za-z0-9-]*$/) login = substr(t, 2)
  }
  if (wait || login == "") next
  p = index(notes, "Done when:")
  if (p == 0) { print "NODONE\t" id "\t" login; next }
  goal = strip_tags(trim(substr(notes, 1, p - 1)))
  done = strip_tags(trim(substr(notes, p + 10)))
  if (done == "") { print "NODONE\t" id "\t" login; next }
  if (goal == "") goal = item
  gsub(/\t/, " ", item); gsub(/\t/, " ", goal); gsub(/\t/, " ", done)
  print "ROW\t" id "\t" login "\t" item "\t" goal "\t" done
}' "$board_path")"

nl='
'
created=0 existed=0 nodone=0 failed=0
while IFS=$'\t' read -r kind id login title goal check; do
    [ -n "$kind" ] || continue
    if [ "$kind" = "NODONE" ]; then
        nodone=$((nodone + 1))
        echo "skip: $id has a #$login tag but no Done when: text"
        continue
    fi
    case "$nl$existing$nl" in
    *"$nl$id:"*)
        existed=$((existed + 1))
        echo "skip: $id already has an issue"
        continue
        ;;
    esac
    issue_title="$id: $title"
    if [ "$apply" -eq 0 ]; then
        created=$((created + 1))
        echo "would create: $issue_title (assignee $login, label ready)"
        continue
    fi
    body="### Goal

$goal

### Done when

$check

### Scope

Board row $id in $board"
    if url="$(gh issue create --title "$issue_title" --body "$body" --label ready --assignee "$login" </dev/null 2>&1)"; then
        created=$((created + 1))
        echo "created: $issue_title $url"
    else
        failed=$((failed + 1))
        refuse "gh issue create failed for $id: $(first_line "$url")" "gh auth status"
    fi
done <<EOF2
$records
EOF2

if [ "$apply" -eq 0 ]; then
    echo "issues-from-rows: dry run, $created to create, $existed with an issue, $nodone without Done when"
else
    echo "issues-from-rows: $created created, $existed with an issue, $nodone without Done when, $failed failed"
fi
[ "$failed" -eq 0 ]
