#!/usr/bin/env bash
# check-owners.sh - fail when a tracked script or workflow has no owner row in OWNERS.md.
#
#   bash scripts/check-owners.sh
#
# Checked: every tracked file under scripts/ and .github/workflows/ has a row; every row that
# names a path (the first cell in backticks) names a path that exists; every owner cell is
# filled; an owner that is not an @login is an agent and needs a sponsor. A row whose first cell
# has no backticks is a job with no file: only its owner and sponsor are checked. Rows are read
# from every table in OWNERS.md: | Path | What it does | Owner | Sponsor |.
# Each offender prints a two-line refusal on stderr (the rule, then a Fix line). Exit 1 when any
# refusal printed. A repo's own scripts that are not in OWNERS.md yet refuse until a row is added.
set -euo pipefail
cd "$(dirname "$0")/.."

OWNERS=OWNERS.md
refusals=""
# Repo text (a file name, a table cell) is attacker-chosen. clean() makes it printable on one line
# (every character outside a small set becomes ?); safe() says it may sit inside a pasted command.
clean() { local s="${1:0:80}"; printf '%s' "${s//[!A-Za-z0-9._\/@ ,=#()+-]/?}"; }
safe() { [[ "$1" =~ ^[A-Za-z0-9._/@][A-Za-z0-9._/@-]*$ ]]; }
refuse() { # refuse <rule> <fix>: queue one two-line refusal
    refusals="${refusals}check-owners: $1
Fix: $2
"
}
finish() {
    printf '%s' "$refusals" >&2
    exit 1
}

git rev-parse --git-dir >/dev/null 2>&1 || { refuse "this is not a git repository, so there is no list of tracked files" "git init"; finish; }
if [ ! -f "$OWNERS" ]; then
    refuse "$OWNERS is missing" "printf '# Owners\\n\\n| Path | What it does | Owner | Sponsor |\\n|---|---|---|---|\\n' > $OWNERS"
    finish
fi

# One line per table row: path, owner, sponsor, label (separated by byte 037). The path is empty for a job with no file.
# A header row is the row right before a |---| separator row; it is dropped.
rows="$(awk -F'|' '
    BEGIN { SEP = "\037" }
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function emit(line,   c, first, path, label) {
        split(line, c, "|")
        first = trim(c[2])
        if (first == "") return
        if (first ~ /^`.*`$/) { path = first; gsub(/`/, "", path); label = path }
        else { path = ""; label = first }
        print path SEP trim(c[4]) SEP trim(c[5]) SEP label
    }
    function flush() { if (have) { emit(buf); have = 0 } }
    /^\|/ {
        line = $0; gsub(/\r/, "", line)
        if (line ~ /^\|[ \t]*:?-+:?[ \t]*\|/) { have = 0; next }
        flush(); buf = line; have = 1; next
    }
    { flush() }
    END { flush() }
' "$OWNERS")"

tracked="$(git ls-files scripts .github/workflows)"
owned_paths="$(printf '%s\n' "$rows" | awk -F'\037' '$1 != "" { print $1 }')"

count=0
while IFS= read -r file; do
    [ -n "$file" ] || continue
    count=$((count + 1))
    if ! printf '%s\n' "$owned_paths" | grep -Fxq -- "$file"; then
        if safe "$file"; then
            fix="printf '%s\\n' '| \`$file\` | what it does | @github-login | |' >> $OWNERS"
        else
            fix="add a row for that file to $OWNERS by hand (its name holds characters this script will not put in a command)"
        fi
        refuse "no owner yet for $(clean "$file"); every script and workflow needs a row in $OWNERS" "$fix"
    fi
done <<EOF2
$tracked
EOF2

while IFS=$'\037' read -r path owner sponsor label; do
    [ -n "$label" ] || continue
    if [ -n "$path" ] && [ ! -e "$path" ]; then
        if safe "$path"; then
            fix="grep -vF '\`$path\`' $OWNERS > $OWNERS.new && mv $OWNERS.new $OWNERS"
        else
            fix="delete that row from $OWNERS by hand (its path holds characters this script will not put in a command)"
        fi
        refuse "row names a path that does not exist: $(clean "$path")" "$fix"
    fi
    if [ -z "$owner" ]; then
        refuse "empty owner: $(clean "$label")" "\${EDITOR:-vi} $OWNERS # put a @github-login in the Owner cell of that row"
    elif [ "${owner#@}" = "$owner" ] && [ -z "$sponsor" ]; then
        refuse "agent owner $(clean "$owner") has no sponsor: $(clean "$label")" "\${EDITOR:-vi} $OWNERS # name the human who answers for that agent in the Sponsor cell of its row"
    fi
done <<EOF2
$rows
EOF2

[ -z "$refusals" ] || finish
echo "check-owners: $count paths, all owned"
