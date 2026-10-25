#!/usr/bin/env bash
# refcheck.sh -- the Tier 1 path check of the kit:doc-drift audit loop
# (skills/doc-drift/SKILL.md step 3, "every backtick path or file reference resolves").
#
# Reads living docs and reports a path reference that does not resolve. It is built to be
# quiet: a reference is judged only when the doc plainly claims a file in THIS repo, so a
# clean run means "no dead in-repo pointer", not "every word was checked".
#
# A reference is a backticked token (kind `tick`) or the target of a markdown link
# (kind `link`). It is judged only when:
#   tick  contains a "/" and its first segment is a top-level entry of the repo
#   link  is relative (not a URL, mailto, or #anchor)
# It is skipped when it sits inside a fenced code block, is a URL, or carries a placeholder
# character (< > * $ ~ { } | = , ; quotes, parens) or an ellipsis. A trailing :LINE or :LINE-LINE is
# stripped first (docs cite file:line). A ref resolves when it exists as a tracked file or
# directory, or on disk, against: the repo root, then each ancestor directory of the doc
# (so a tool's own doc may name a path relative to the tool). A link resolves against the
# doc's own directory only, as a markdown renderer reads it.
#
# It never writes. It never leaves the repo it is pointed at.
#
# Output is TSV: <doc>\t<line>\t<kind>\t<ref>, one per dead ref, then
#   SUMMARY\t<docs> docs\t<refs> refs checked\t<dead> dead
#
# Usage:
#   refcheck.sh scan --repo DIR [--docs PATHSPEC]...
#     --docs   a git pathspec for the item set, repeatable. Default is the living-doc set of
#              skills/doc-drift/SKILL.md: README.md AGENTS.md CLAUDE.md
#              CONTRIBUTING.md ':(glob)docs/*.md' ':(glob)docs/reference/*.md' ':(glob)docs/guides/*.md' ':(glob)docs/patterns/*.md'
#
# Exit: 0 when the scan ran (dead refs are output, not failure); 2 on bad usage or a target
# that is not a git repo.

set -uo pipefail

REPO="."
DOCS=()

usage() { sed -n '2,/^# Exit/p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "refcheck: $*" >&2; exit 2; }

CMD="${1:-}"
case "$CMD" in
  scan) shift ;;
  -h|--help|help|"") usage; [ -z "$CMD" ] && exit 2; exit 0 ;;
  *) die "unknown verb '$CMD' (try: scan)" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a directory"; REPO="$2"; shift 2 ;;
    --docs) [ $# -ge 2 ] || die "--docs needs a pathspec"; DOCS+=("$2"); shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown flag '$1'" ;;
  esac
done

[ -d "$REPO" ] || die "not a directory: $REPO"
cd "$REPO" || die "cannot enter $REPO"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "not a git repo: $REPO"
cd "$(git rev-parse --show-toplevel)" || die "cannot enter the repo top"

if [ "${#DOCS[@]}" -eq 0 ]; then
  DOCS=(README.md AGENTS.md CLAUDE.md CONTRIBUTING.md ':(glob)docs/*.md' ':(glob)docs/reference/*.md' ':(glob)docs/guides/*.md' ':(glob)docs/patterns/*.md')
fi

TRACKED="$(mktemp "${TMPDIR:-/tmp}/refcheck.XXXXXX")" || die "mktemp failed"
DOCLIST="$(mktemp "${TMPDIR:-/tmp}/refcheck.XXXXXX")" || die "mktemp failed"
trap 'rm -f "$TRACKED" "$DOCLIST"' EXIT

git ls-files >"$TRACKED"
git ls-files -- "${DOCS[@]}" >"$DOCLIST"

# One awk pass. It loads the tracked file list into a file set, a directory set and a
# top-level-entry set, then reads each doc. Only a ref the sets cannot place falls through to
# a `test -e`, so the subprocess cost scales with misses, not with refs.
awk -v trackedfile="$TRACKED" -v doclist="$DOCLIST" '
function parent(p,    i) {
  i = length(p)
  while (i > 0 && substr(p, i, 1) != "/") i--
  return i > 0 ? substr(p, 1, i - 1) : ""
}
function norm(p,    n, i, parts, out, k, seg) {
  n = split(p, parts, "/"); k = 0
  for (i = 1; i <= n; i++) {
    seg = parts[i]
    if (seg == "" || seg == ".") continue
    if (seg == "..") { if (k == 0) return ""; k--; continue }
    out[++k] = seg
  }
  seg = ""
  for (i = 1; i <= k; i++) seg = seg (i > 1 ? "/" : "") out[i]
  return seg
}
function on_disk(p) { return system("test -e \047" p "\047") == 0 }
function known(p) {
  if (p == "") return 0
  if (p in FILES || p in DIRS) return 1
  if (index(p, "\047") > 0) return 0
  return on_disk(p)
}
function resolves_tick(ref, doc,    d) {
  if (known(norm(ref))) return 1
  d = parent(doc)
  while (d != "") {
    if (known(norm(d "/" ref))) return 1
    d = parent(d)
  }
  return 0
}
function resolves_link(ref, doc) {
  return known(norm(parent(doc) == "" ? ref : parent(doc) "/" ref))
}
function placeholder(s,    i, c) {
  for (i = 1; i <= length(PH); i++) { c = substr(PH, i, 1); if (index(s, c) > 0) return 1 }
  return 0
}
function check(doc, ln, kind, ref,    r, c) {
  r = ref
  if (placeholder(r) || index(r, "...") > 0) return
  sub(/#.*$/, "", r)
  sub(/\?.*$/, "", r)
  sub(/:[0-9]+(-[0-9]+)?$/, "", r)
  if (r == "" || r ~ /:/) return
  if (r ~ /^[\/@-]/) return
  sub(/\/+$/, "", r)
  if (kind == "tick") {
    sub(/^\.\//, "", r)
    if (r !~ /\//) return
    c = r; sub(/\/.*$/, "", c)
    if (!(c in TOP)) return
    CHECKED++
    if (!resolves_tick(r, doc)) { print doc "\t" ln "\t" kind "\t" ref; DEAD++ }
  } else {
    if (r == "") return
    CHECKED++
    if (!resolves_link(r, doc)) { print doc "\t" ln "\t" kind "\t" ref; DEAD++ }
  }
}
BEGIN {
  PH = "<>*$~{}|=,;\"\047()"
  while ((getline f < trackedfile) > 0) {
    FILES[f] = 1
    split(f, seg, "/")
    TOP[seg[1]] = 1
    d = parent(f)
    while (d != "" && !(d in DIRS)) { DIRS[d] = 1; d = parent(d) }
  }
  close(trackedfile)
  CHECKED = 0; DEAD = 0; NDOCS = 0
  while ((getline doc < doclist) > 0) {
    NDOCS++; INFENCE = 0; ln = 0
    while ((getline line < doc) > 0) {
      ln++
      if (line ~ /^[ \t]*(```|~~~)/) { INFENCE = !INFENCE; continue }
      if (INFENCE) continue
      rest = line
      while (match(rest, /`[^` \t]+`/)) {
        check(doc, ln, "tick", substr(rest, RSTART + 1, RLENGTH - 2))
        rest = substr(rest, RSTART + RLENGTH)
      }
      nocode = line
      gsub(/`[^`]*`/, "", nocode)
      rest = nocode
      while (match(rest, /\]\([^) \t]+\)/)) {
        check(doc, ln, "link", substr(rest, RSTART + 2, RLENGTH - 3))
        rest = substr(rest, RSTART + RLENGTH)
      }
    }
    close(doc)
  }
  printf "SUMMARY\t%d docs\t%d refs checked\t%d dead\n", NDOCS, CHECKED, DEAD
}
' </dev/null
