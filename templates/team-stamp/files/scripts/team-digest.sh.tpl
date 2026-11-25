#!/usr/bin/env bash
# Team digest: what merged, what is open, who works on what, what waits on a
# decision. Reads GitHub through `gh` and the board file. Prints markdown to
# stdout. Posts nothing and writes nothing.
#
#   bash scripts/team-digest.sh              # last 24 hours
#   bash scripts/team-digest.sh --hours 72   # a longer window
#   bash scripts/team-digest.sh --board-file PATH
#
# With no `gh` it prints one note and exits 0. With no board file set it prints
# the GitHub sections and one note in place of the board sections. Run it from a
# current checkout so the board file is fresh. bash 3.2 safe.
set -euo pipefail

board_default="{{BOARD_FILE}}"
decision_tag="{{DECISION_TAG}}"

usage() {
  cat <<'EOF'
Usage: team-digest.sh [--hours N] [--board-file PATH] [--help]

Prints a markdown digest to stdout:
  1. PRs merged in the last N hours (default 24)
  2. Open PRs with author and age
  3. Open issues with assignee and whether they carry the ready label
  4. Executing rows: board rows whose status starts with executing
  5. Decisions waiting: open board rows tagged with the decision tag and #P0, first 10

Needs gh (logged in) and standard tools. Posts nothing.
  --hours N          window for merged PRs, a whole number
  --board-file PATH  board file, default the stamped board file (empty: no board part)
EOF
}

refuse() { # refuse <rule> <fix>
  printf 'team-digest: %s\nFix: %s\n' "$1" "$2" >&2
  exit 2
}

hours=24
board="$board_default"
while [ $# -gt 0 ]; do
  case "$1" in
    --hours)
      [ $# -ge 2 ] || refuse "--hours needs a value." "bash scripts/team-digest.sh --hours 72"
      hours="$2"; shift 2 ;;
    --board-file)
      [ $# -ge 2 ] || refuse "--board-file needs a path." "bash scripts/team-digest.sh --board-file docs/BOARD.md"
      board="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) refuse "unknown argument: $1" "bash scripts/team-digest.sh --help" ;;
  esac
done

case "$hours" in
  ''|*[!0-9]*) refuse "--hours must be a whole number." "bash scripts/team-digest.sh --hours 24" ;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "team-digest: gh is not installed; nothing to read"
  exit 0
fi

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
case "$board" in
  "") ;;
  /*) ;;
  *) board="$root/$board" ;;
esac

# ISO time N hours ago. The branch is on the OS: BSD date takes -v, GNU date takes -d.
case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin|*BSD)
    since="$(date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${hours} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || since="" ;;
  *)
    since="$(date -u -d "${hours} hours ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"${hours}"H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || since="" ;;
esac
[ -n "$since" ] || refuse "could not compute the window start with this date command." "bash scripts/team-digest.sh --hours 24 (run it where date supports -d or -v)"

echo "# Team digest"
echo
echo "Window: merged since $since (last ${hours}h)."
echo

# Titles, logins and board cells are chosen by whoever wrote them: every one goes through cl (jq and awk)
# or clean (shell), which keeps a short set of safe characters, so a title cannot forge a line.
clean() { local s="${1:0:80}"; printf '%s' "${s//[!A-Za-z0-9._\/@ ,=#()+-]/?}"; }
JQ_CL='def cl: (. // "") | tostring | gsub("[^A-Za-z0-9._/@ ,=#()+-]"; "?") | .[0:80]; '

echo "## Merged PRs"
echo
if merged="$(gh pr list --state merged --limit 100 --search "merged:>=${since}" \
  --json number,title,author,mergedAt \
  --jq "$JQ_CL"'sort_by(.mergedAt) | reverse | .[] | "- #\(.number | cl) \(.title | cl) (\(.author.login | cl))"' 2>&1)"; then
  if [ -n "$merged" ]; then echo "$merged"; else echo "- none"; fi
else
  echo "- gh failed: $(clean "$merged")"
fi
echo

echo "## Open PRs"
echo
# shellcheck disable=SC2016  # $h and $age are jq variables
if open="$(gh pr list --state open --limit 100 \
  --json number,title,author,createdAt,isDraft \
  --jq "$JQ_CL"'.[] | ((now - (.createdAt | fromdateiso8601)) / 3600 | floor) as $h
    | (if $h >= 48 then "\($h / 24 | floor)d" else "\($h)h" end) as $age
    | "- #\(.number | cl) \(.title | cl) (\(.author.login | cl), \($age) old\(if .isDraft then ", draft" else "" end))"' 2>&1)"; then
  if [ -n "$open" ]; then echo "$open"; else echo "- none"; fi
else
  echo "- gh failed: $(clean "$open")"
fi
echo

echo "## Open issues"
echo
# shellcheck disable=SC2016  # $who is a jq variable
if issues="$(gh issue list --state open --limit 100 \
  --json number,title,assignees,labels \
  --jq "$JQ_CL"'.[] | ([.assignees[].login | cl] | join(",")) as $who
    | "- #\(.number | cl) \(.title | cl) (\(if $who == "" then "unassigned" else $who end), \(if any(.labels[]; .name == "ready") then "ready" else "not ready" end))"' 2>&1)"; then
  if [ -n "$issues" ]; then echo "$issues"; else echo "- none"; fi
else
  echo "- gh failed: $(clean "$issues")"
fi
echo

if [ -z "$board" ]; then
  echo "## Board"
  echo
  echo "- no board file set; nothing to read"
  exit 0
fi
if [ ! -f "$board" ]; then
  echo "## Board"
  echo
  echo "- board file not found: $(clean "$board")"
  exit 0
fi

# Row shape: | ID-NNN | item | notes and tags | status |. Notes never hold a raw pipe.
awk_common='
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function cl(s) { gsub(/[^A-Za-z0-9._\/@ ,=#()+-]/, "?", s); return substr(s, 1, 80) }
function has_tag(notes, tag,   n, w, i, t) {
  n = split(notes, w, /[ \t]+/)
  for (i = 1; i <= n; i++) {
    t = w[i]
    gsub(/[.,;)]+$/, "", t)
    if (t == tag) return 1
  }
  return 0
}
function owner_tags(notes, dtag,   n, w, i, t, out) {
  n = split(notes, w, /[ \t]+/); out = ""
  for (i = 1; i <= n; i++) {
    t = w[i]
    if (t !~ /^#/) continue
    gsub(/[.,;)]+$/, "", t)
    if (t ~ /^#P[0-3]$/ || t == dtag) continue
    out = out " " cl(t)
  }
  return out
}
'

echo "## Executing rows"
echo
executing="$(awk -F'|' -v dtag="#$decision_tag" "$awk_common"'
  /^\| ID-[0-9]+ / {
    status = trim($5)
    if (status !~ /^executing/) next
    split(status, s, /[ \[]/)
    printf "- %s (%s)%s, %s\n", cl(trim($2)), cl(trim($3)), owner_tags($4, dtag), cl(s[1])
  }' "$board")"
if [ -n "$executing" ]; then echo "$executing"; else echo "- none"; fi
echo

echo "## Decisions waiting"
echo
waiting="$(awk -F'|' -v dtag="#$decision_tag" "$awk_common"'
  /^\| ID-[0-9]+ / {
    status = trim($5)
    if (status ~ /^(shipped|dropped|parked)/) next
    if (!has_tag($4, dtag) || !has_tag($4, "#P0")) next
    if (++count > 10) next
    printf "- %s (%s)\n", cl(trim($2)), cl(trim($3))
  }' "$board")"
if [ -n "$waiting" ]; then echo "$waiting"; else echo "- none"; fi
