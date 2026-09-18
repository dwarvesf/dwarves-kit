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
#     <age>d  <repo-relative path>  next: <excerpt>  <liveness>
#   <excerpt> is the first non-empty line under a heading matching
#   /^## (Next|Next step|Open)/, truncated to 80 chars, or
#   "(no Next section)" when no such heading exists. Last line is
#   "<n> open handoffs", or "no handoffs" when the scan found none.
#
#   <liveness> checks every board ID (`[A-Z]+-[0-9]+`) the file cites
#   against the repo's board AS IT STANDS ON ORIGIN (`git fetch origin`,
#   then `_meta/BACKLOG.md` + `_meta/BACKLOG-archive.md` off
#   origin/<default-branch>), falling back to the working tree with a
#   "(local)" suffix when there is no origin remote:
#     LIVE (n open: ID-a, ID-b)   -- at least one cited row is still open
#     DEAD (all n cited rows closed, delete it)  -- every cited row shipped/
#       dropped/done/resolved
#     UNCITED (no row IDs; read it)  -- the file names no board row
#   A row ID this repo's board cannot resolve counts as open (unproven, not
#   confirmed closed). The board owns the work; the handoff owns only the
#   context (see AGENTS.md's handoff rule). A DEAD handoff is deleted by the
#   session that finds it, git history keeps it.
set -euo pipefail
shopt -s nullglob

usage() { sed -n '2,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

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

# --- board liveness ----------------------------------------------------

# Best-effort default branch of origin: refs/remotes/origin/HEAD symref
# (set by a normal clone), else the first of master/main that exists.
_origin_default_branch() { # <repo>
  local repo="$1" ref cand
  ref="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then printf '%s\n' "${ref#origin/}"; return 0; fi
  for cand in master main; do
    if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$cand"; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  return 1
}

# Loads the board content this repo's liveness checks should read against,
# into the globals BOARD_CONTENT (BACKLOG.md + BACKLOG-archive.md,
# concatenated) and BOARD_SOURCE ("origin/<branch>" or "local"). Origin
# first, working tree only when there is no origin remote or no resolvable
# default branch.
_load_board() { # <repo>
  local repo="$1" branch
  BOARD_CONTENT="" BOARD_SOURCE="local"
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo" fetch -q origin >/dev/null 2>&1 || true
    branch="$(_origin_default_branch "$repo" || true)"
    if [ -n "$branch" ]; then
      BOARD_CONTENT="$(git -C "$repo" show "origin/$branch:_meta/BACKLOG.md" 2>/dev/null || true)"
      BOARD_CONTENT="$BOARD_CONTENT
$(git -C "$repo" show "origin/$branch:_meta/BACKLOG-archive.md" 2>/dev/null || true)"
      BOARD_SOURCE="origin/$branch"
      return 0
    fi
  fi
  BOARD_CONTENT="$(cat "$repo/_meta/BACKLOG.md" 2>/dev/null || true)"
  BOARD_CONTENT="$BOARD_CONTENT
$(cat "$repo/_meta/BACKLOG-archive.md" 2>/dev/null || true)"
}

# Leading status keyword of one board row (lowercased), or empty when the
# id has no row in BOARD_CONTENT.
_row_status() { # <id>
  printf '%s\n' "$BOARD_CONTENT" | awk -F'|' -v id="$1" '
    $0 ~ ("^\\| *" id " *\\|") {
      cell=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", cell)
      split(cell, a, /[ \[(]/); print tolower(a[1]); exit
    }'
}

_status_is_closed() { # <status>
  case "$1" in
    shipped|dropped|done|resolved) return 0 ;;
    *) return 1 ;;
  esac
}

# One-line liveness verdict for a handoff file, reading the already-loaded
# BOARD_CONTENT/BOARD_SOURCE globals (see _load_board).
handoff_liveness() { # <file>
  local f="$1" ids id status n=0
  local open=()
  ids="$(grep -oE '[A-Z]+-[0-9]+' "$f" 2>/dev/null | sort -u || true)"
  [ -n "$ids" ] || { echo "UNCITED (no row IDs; read it)"; return 0; }
  for id in $ids; do
    n=$((n + 1))
    status="$(_row_status "$id")"
    if [ -n "$status" ] && _status_is_closed "$status"; then
      continue
    fi
    open+=("$id")
  done
  local suffix=""
  [ "$BOARD_SOURCE" = "local" ] && suffix=" (local)"
  if [ "${#open[@]}" -eq 0 ]; then
    echo "DEAD (all $n cited rows closed, delete it)$suffix"
  else
    local joined; joined="$(IFS=,; echo "${open[*]}")"
    joined="$(printf '%s' "$joined" | sed 's/,/, /g')"
    echo "LIVE (${#open[@]} open: $joined)$suffix"
  fi
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

  _load_board "$repo"

  local now; now="$(date +%s)"
  local rows=()
  for f in "${files[@]}"; do
    local mtime age rel excerpt liveness
    mtime="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
    age=$(( (now - mtime) / 86400 ))
    [ -n "$days" ] && [ "$age" -lt "$days" ] && continue
    rel="${f#"$repo"/}"
    excerpt="$(next_excerpt "$f")"
    [ -n "$excerpt" ] || excerpt="(no Next section)"
    liveness="$(handoff_liveness "$f")"
    rows+=("$(printf '%09d\t%sd  %s  next: %s  %s' "$age" "$age" "$rel" "$excerpt" "$liveness")")
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
