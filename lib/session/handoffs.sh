#!/usr/bin/env bash
# handoffs.sh -- list open handoff files so kit:start surfaces them at session
# entry instead of them piling up unread. A handoff (written by the `handoff`
# skill) is a one-off note, not a lifecycle-managed draft like .claude/goals/
# (see lib/goal/goal-drafts.sh): there is no archive/ship flow here, only a
# `done/` or `_archive/` convention a repo may use to mark one consumed.
#
# Read-only. Pure bash + find/awk/sed, no python (same shape as
# lib/session/parse-transcript.sh's sibling test, lib/session/tests/).
#
# Usage:
#   handoffs.sh list [--repo DIR] [--days N]
#     --repo DIR   repo to scan (default: git rev-parse --show-toplevel of
#                  cwd, else cwd itself)
#     --days N     only include handoffs at least N days old (staleness
#                  filter; default: no filter, show every open handoff)
#
#   Scans <repo>/_meta/handoffs/ and <repo>/.claude/handoffs/ for *.md files,
#   skipping anything under a done/ or _archive/ subdirectory. One line per
#   file, oldest first:
#     <age>d  <repo-relative path>  next: <excerpt>
#   <excerpt> is the first non-empty line under a heading matching
#   /^## (Next|Next step|Open)/, truncated to 80 chars, or
#   "(no Next section)" when no such heading exists. Last line is
#   "<n> open handoffs", or "no handoffs" when the scan found none.
set -euo pipefail
shopt -s nullglob

usage() { sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# First non-empty line under a heading matching /^## (Next|Next step|Open)/,
# truncated to 80 chars. Empty output means no such heading was found.
next_excerpt() { # <file>
  awk '
    /^## (Next|Next step|Open)/ { infm=1; next }
    infm && /^#/ { exit }
    infm && NF > 0 { print; exit }
  ' "$1" | cut -c1-80
}

cmd_list() {
  local repo="" days=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || { echo "handoffs list: --repo needs a value" >&2; return 64; }; repo="$2"; shift 2 ;;
      --days) [ $# -ge 2 ] || { echo "handoffs list: --days needs a value" >&2; return 64; }; days="$2"; shift 2 ;;
      *) echo "handoffs list: unknown arg '$1'" >&2; return 64 ;;
    esac
  done
  [ -n "$repo" ] || repo="$(repo_root)"
  repo="$(cd "$repo" 2>/dev/null && pwd || true)"
  [ -n "$repo" ] || { echo "handoffs list: repo not found" >&2; return 1; }

  local files=()
  local d f
  for d in "$repo/_meta/handoffs" "$repo/.claude/handoffs"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do
      files+=("$f")
    done < <(find "$d" -type f -name '*.md' \
      -not -path '*/done/*' -not -path '*/_archive/*' 2>/dev/null)
  done

  if [ "${#files[@]}" -eq 0 ]; then
    echo "no handoffs"
    return 0
  fi

  local now; now="$(date +%s)"
  local rows=()
  for f in "${files[@]}"; do
    local mtime age rel excerpt
    mtime="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
    age=$(( (now - mtime) / 86400 ))
    [ -n "$days" ] && [ "$age" -lt "$days" ] && continue
    rel="${f#"$repo"/}"
    excerpt="$(next_excerpt "$f")"
    [ -n "$excerpt" ] || excerpt="(no Next section)"
    rows+=("$(printf '%09d\t%sd  %s  next: %s' "$age" "$age" "$rel" "$excerpt")")
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "no handoffs"
    return 0
  fi

  # Sort oldest first (largest age first) by the zero-padded sort key, then
  # strip the key before printing.
  printf '%s\n' "${rows[@]}" | sort -rn -t"$(printf '\t')" -k1,1 | cut -f2-
  echo "${#rows[@]} open handoffs"
}

main() {
  local sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    list) cmd_list "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "handoffs: unknown subcommand '$sub' (try: handoffs.sh --help)" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
