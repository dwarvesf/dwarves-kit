#!/usr/bin/env bash
# Print the public release notes for one CHANGELOG.md section.
#
#   bash scripts/release-notes.sh Unreleased          # the section waiting for a release
#   bash scripts/release-notes.sh 0.3.0 [changelog]   # a version section, optional file path
#
# Every entry starts with a tag from this repo's list ({{TAGS}}), then a colon and a space.
# Public notes keep every tag except `dev:`. A heading left with no entries is dropped. Exit 1
# when the section is missing, an entry has no tag, or nothing is left for a user to read. Each
# refusal prints two lines on stderr: the rule, then a Fix line. awk, bash and coreutils only.
set -euo pipefail

TAGS='{{TAGS}}'
TAGS_ERE='{{TAGS_ERE}}'

# Repo text and arguments are attacker-chosen. clean() makes text printable on one line (every
# character outside a small set becomes ?); safe() says a value may sit inside a pasted command.
clean() { local s="${1:0:200}"; printf '%s' "${s//[!A-Za-z0-9._\/@ :,=#()+-]/?}"; }
safe() { [[ "$1" =~ ^[A-Za-z0-9._/@][A-Za-z0-9._/@-]*$ ]]; }
refuse() { # refuse <rule> <fix>: the two-line refusal on stderr
    printf 'release-notes: %s\nFix: %s\n' "$1" "$2" >&2
}

usage() {
    cat <<'EOF2'
Usage: release-notes.sh <section> [changelog]

Print the public release notes of one CHANGELOG.md section: every entry except the `dev:` ones.
<section> is Unreleased or a version (0.3.0 or v0.3.0). The changelog defaults to CHANGELOG.md
at the repo root.
EOF2
}

case "${1-}" in
-h | --help) usage; exit 0 ;;
"") refuse "no section given" "bash scripts/release-notes.sh Unreleased"; exit 2 ;;
esac
[ "$#" -le 2 ] || { refuse "too many arguments" "bash scripts/release-notes.sh --help"; exit 2; }

section="$1"
if [[ "$section" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then section="${section#v}"; fi
case "$0" in
*/*) here="${0%/*}" ;;
*) here="." ;;
esac
file="${2:-$here/../CHANGELOG.md}"
if [ ! -f "$file" ]; then
    if safe "$file"; then
        fix="printf '# Changelog\\n\\n## [Unreleased]\\n' > $file"
    else
        fix="create the changelog by hand (its path holds characters this script will not put in a command)"
    fi
    refuse "$(clean "$file") not found" "$fix"
    exit 1
fi

rc=0
result="$(SEC="$section" TAGS_ERE="$TAGS_ERE" awk '
function add(line,   c) {
    c = substr(line, 1, 1)
    if (line ~ /^[-*] /) { nb++; kind[nb] = "entry"; txt[nb] = line; first[nb] = line }
    else if ((c == " " || c == "\t") && nb > 0 && kind[nb] == "entry") { txt[nb] = txt[nb] "\n" line }
    else if (line ~ /^### /) { nb++; kind[nb] = "head"; txt[nb] = line }
    else { nb++; kind[nb] = "text"; txt[nb] = line }
}
function emit(s,   a, k, c) {
    if (s == "") { c = 1; a[1] = "" } else c = split(s, a, "\n")
    for (k = 1; k <= c; k++) {
        if (a[k] == "") { if (printed) pending = 1; continue }
        if (pending) { print ""; pending = 0 }
        print a[k]; printed = 1
    }
}
BEGIN { hdr = "## [" ENVIRON["SEC"] "]"; tre = "^[-*] (" ENVIRON["TAGS_ERE"] "):( |$)" }
{ sub(/\r$/, "") }
!found { if (index($0, hdr) == 1) found = 1; next }
!done {
    if ($0 ~ /^## / || $0 ~ /^\[[^]]+\]: /) { done = 1; next }
    add($0)
}
END {
    if (!found) { print "ERR\tNOSECTION\t"; exit 1 }
    for (i = 1; i <= nb; i++)
        if (kind[i] == "entry" && first[i] !~ tre) { print "ERR\tUNTAGGED\t" substr(first[i], 1, 100); exit 1 }
    m = 0; users = 0
    for (i = 1; i <= nb; i++) {
        if (kind[i] == "entry" && first[i] ~ /^[-*] dev:( |$)/) continue
        ki[++m] = i
        if (kind[i] == "entry") users++
    }
    if (users == 0) { print "ERR\tNOUSER\t"; exit 1 }
    for (j = 1; j <= m; j++) {
        i = ki[j]
        if (kind[i] == "head") {
            keep = 0
            for (k = j + 1; k <= m; k++) {
                ii = ki[k]
                if (kind[ii] == "head") break
                if (kind[ii] == "entry" || txt[ii] ~ /[^ \t\r\n]/) { keep = 1; break }
            }
            if (!keep) continue
        }
        emit(txt[i])
    }
}' "$file")" || rc=$?

if [ "$rc" -ne 0 ]; then
    if safe "$file"; then edit="\${EDITOR:-vi} $file # "; else edit="edit the changelog by hand: "; fi
    IFS=$'\t' read -r _ kind detail <<EOF2
$result
EOF2
    case "$kind" in
    NOSECTION)
        if safe "$section" && safe "$file"; then
            fix="printf '\\n## [%s]\\n' '$section' >> $file"
        else
            fix="add that section heading to the changelog by hand (a name holds characters this script will not put in a command)"
        fi
        refuse "no ## [$(clean "$section")] section in $(clean "$file")" "$fix"
        ;;
    UNTAGGED)
        refuse "entry without a tag (${TAGS//,/, }): $(clean "$detail")" "${edit}start the entry with one of: ${TAGS//,/: }:"
        ;;
    *)
        product=""
        oldifs="$IFS"
        IFS=','
        for t in $TAGS; do [ "$t" = dev ] || product="$product $t:"; done
        IFS="$oldifs"
        refuse "[$(clean "$section")] has no entry for a user; only dev: lines, or none at all" "${edit}add an entry tagged with one of:${product:- a product tag}"
        ;;
    esac
    exit 1
fi
printf '%s\n' "$result"
