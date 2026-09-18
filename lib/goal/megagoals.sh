#!/usr/bin/env bash
# megagoals.sh -- list mega-goal folders (ROADMAP.md + sub-goal checklist)
# that still have open work, for kit:start's Pick up block. The counterpart
# to lib/goal/goal-drafts.sh (single-goal drafts) and lib/session/handoffs.sh
# (session handoff notes): this one reads the multi-sub-goal roadmap shape
# (see docs/patterns or a real one, e.g. tieubao/ops-toolkit
# _meta/megagoals/<slug>/ROADMAP.md, for the sample this was built against).
#
# A mega-goal folder is any directory holding a ROADMAP.md under one of the
# four known shapes:
#   _meta/megagoals/*/        experiments/*/megagoals/*/
#   tools/*/docs/megagoals/*/ docs/megagoals/*/
#
# Sub-goal progress is counted from the "## Sub-goals" and "## Status"
# sections only: every line carrying a `- [ ]` or `- [x]` token counts,
# whether it is a top-level checklist bullet or embedded inside a markdown
# table's Status cell (both real-world ROADMAP shapes use the same checkbox
# literal, so one grep handles both without a table parser). A `- [x]`
# outside those two sections (e.g. an "## Imported history" bullet) is not
# counted.
#
# Why both sections: some real ROADMAPs (e.g. ops-toolkit's
# herdr-quicklook/megagoals/*) track completion under a
# "## Status (source of truth; ...)" header instead of "## Sub-goals" --
# sometimes as the ONLY checklist section, sometimes alongside a
# "## Sub-goals" table that lists sub-goals with no checkboxes at all (a
# wave/dependency declaration, not a status tracker). Observed real files
# never carry live checkboxes in both sections at once, so summing them is
# safe.
#
# Read-only. Pure bash + find/awk, no python. Zero network calls. bash 3.2
# compatible (no associative arrays, no mapfile/readarray).
#
# Usage:
#   megagoals.sh list [--repo DIR] [--limit N] [--all]
#     --repo DIR   repo to scan (default: git rev-parse --show-toplevel of
#                  cwd, else cwd itself)
#     --limit N    max mega-goal lines to print before collapsing the rest
#                  to "+N more" (default: 5; 0 means unlimited)
#     --all        also print fully-done mega-goals (done == total > 0),
#                  which are hidden by default
#
#   One line per mega-goal, sorted by path:
#     <slug>  <done>/<total>  HANDOFF:<yes|no>  POINTER:<path or ->
#   <slug> is the mega-goal directory's basename. <path> (when a
#   POINTER_PROMPT.md exists) is repo-relative. Last line is
#   "<n> mega-goals", or "no mega-goals" when the scan found none (after the
#   done-filter, unless --all).
set -uo pipefail
shopt -s nullglob

usage() { sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# Every ROADMAP.md under one of the four known mega-goal shapes, sorted.
# Prunes .claude/worktrees, node_modules, and .git: each worktree under a
# repo is a full checkout, so an unpruned find double-counts every
# mega-goal once per worktree (610-line real-world blowup on ops-toolkit,
# 547 of them worktree copies -- the true count was 63).
find_roadmaps() { # <repo>
  find "$1" \( \
      -path '*/.claude/worktrees' -o \
      -path '*/node_modules' -o \
      -path '*/.git' \
    \) -prune -o -type f -name ROADMAP.md \( \
      -path '*/_meta/megagoals/*/ROADMAP.md' -o \
      -path '*/experiments/*/megagoals/*/ROADMAP.md' -o \
      -path '*/tools/*/docs/megagoals/*/ROADMAP.md' -o \
      -path '*/docs/megagoals/*/ROADMAP.md' \
    \) -print 2>/dev/null | sort
}

# done/total sub-goals, counted from the "## Sub-goals" section only.
# Prints "<done> <total>" on one line.
count_subgoals() { # <roadmap-file>
  awk '
    /^## Sub-goals/ { insec=1; next }
    /^## Status/    { insec=1; next }
    insec && /^## / { insec=0 }
    insec && /- \[x\]/ { done++; total++; next }
    insec && /- \[ \]/ { total++; next }
    END { printf "%d %d\n", done+0, total+0 }
  ' "$1"
}

cmd_list() {
  local repo="" limit=5 all=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || { echo "megagoals list: --repo needs a value" >&2; return 64; }; repo="$2"; shift 2 ;;
      --limit) [ $# -ge 2 ] || { echo "megagoals list: --limit needs a value" >&2; return 64; }; limit="$2"; shift 2 ;;
      --all) all=1; shift ;;
      *) echo "megagoals list: unknown arg '$1'" >&2; return 64 ;;
    esac
  done
  case "$limit" in
    ''|*[!0-9]*) echo "megagoals list: --limit must be a non-negative integer (got '$limit')" >&2; return 64 ;;
  esac
  [ -n "$repo" ] || repo="$(repo_root)"
  repo="$(cd "$repo" 2>/dev/null && pwd || true)"
  [ -n "$repo" ] || { echo "megagoals list: repo not found" >&2; return 1; }

  local files=() f
  while IFS= read -r f; do
    [ -n "$f" ] && files+=("$f")
  done < <(find_roadmaps "$repo")

  local rows=() dir slug dn tot handoff pointer
  for f in "${files[@]}"; do
    dir="$(dirname "$f")"
    slug="$(basename "$dir")"
    read -r dn tot < <(count_subgoals "$f")
    if [ "$tot" -eq 0 ]; then
      [ "$all" -eq 1 ] || continue
    elif [ "$all" -eq 0 ] && [ "$dn" -eq "$tot" ]; then
      continue   # fully done, hidden unless --all
    fi
    handoff="no"; [ -f "$dir/HANDOFF.md" ] && handoff="yes"
    pointer="-"; [ -f "$dir/POINTER_PROMPT.md" ] && pointer="${dir#"$repo"/}/POINTER_PROMPT.md"
    rows+=("$(printf '%s  %d/%d  HANDOFF:%s  POINTER:%s' "$slug" "$dn" "$tot" "$handoff" "$pointer")")
  done

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "no mega-goals"
    return 0
  fi

  local total_n="${#rows[@]}" shown=0 i=0 line
  if [ "$limit" -gt 0 ] && [ "$total_n" -gt "$limit" ]; then
    for line in "${rows[@]}"; do
      i=$((i + 1))
      [ "$i" -gt "$limit" ] && break
      echo "$line"
      shown=$((shown + 1))
    done
    echo "+$((total_n - shown)) more"
  else
    printf '%s\n' "${rows[@]}"
  fi
  echo "$total_n mega-goals"
}

main() {
  local sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    list) cmd_list "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "megagoals: unknown subcommand '$sub' (try: megagoals.sh --help)" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
