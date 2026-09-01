#!/usr/bin/env bash
# goal-drafts.sh -- the goal-draft lifecycle helper (ADR-0023, SPEC-037).
#
# Goal DRAFTS live at .claude/goals/<slug>.md: the design-time "what's active"
# candidate work, gitignored and per-machine (ADR-0011). They are NOT the
# cross-session running-goal REGISTRY (.git/kit-goals/<slug>.goal, ADR-0022); the
# slug is the shared key, draft = candidate work, registry = the run-time lock.
# See docs/architecture.md "## State model" for the two stores side by side.
#
# This helper gives drafts a lifecycle so the directory stops being a graveyard:
# a draft is "drafted" while its work is live, and is ARCHIVED (moved, never
# deleted) to .claude/goals/done/ once its target_spec ships. The render commands
# (/kit:start, /kit:next) enumerate top-level *.md only, so a moved draft drops
# out of "what's active" with no filter code. The archive trigger is /kit:ship.
#
# The filesystem is the SOLE source of truth (ADR-0023 dropped the never-built
# INDEX.md derived-cache). No daemon, no scheduler, no durability state. Pure bash.
#
# Roots (override for tests):
#   GOAL_DRAFTS_DIR   default $(git rev-parse --show-toplevel)/.claude/goals
#   GOAL_SPECS_DIR    default $(git rev-parse --show-toplevel)/docs/specs
#
# Subcommands:
#   archive [--dry-run]   move every draft whose target_spec is a SHIPPED spec
#                         into done/ (status: shipped). Idempotent; specless or
#                         unresolvable drafts are left in place.
#   list                  print active drafts (top-level, excludes done/) as
#                         "slug -> target_spec (status)"
#   dir                   print the resolved drafts root

set -euo pipefail

# Empty globs expand to nothing instead of staying literal (safe iteration under set -e).
shopt -s nullglob

# --- roots ------------------------------------------------------------------

drafts_dir() {
  if [ -n "${GOAL_DRAFTS_DIR:-}" ]; then
    printf '%s\n' "$GOAL_DRAFTS_DIR"
    return 0
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "goal-drafts: not a git repository" >&2
    return 3
  }
  printf '%s/.claude/goals\n' "$top"
}

specs_dir() {
  if [ -n "${GOAL_SPECS_DIR:-}" ]; then
    printf '%s\n' "$GOAL_SPECS_DIR"
    return 0
  fi
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "goal-drafts: not a git repository" >&2
    return 3
  }
  printf '%s/docs/specs\n' "$top"
}

# --- frontmatter read -------------------------------------------------------

# Print the value of one frontmatter key (e.g. target_spec, status) from a draft.
# Reads only the leading `---` ... `---` block. Missing key/file -> empty, exit 0
# (kept exit-0 so it is safe inside command substitution under set -e).
draft_get() {
  local file="$1" key="$2"
  [ -f "$file" ] || return 0
  awk -v k="$key" '
    NR==1 && /^---[[:space:]]*$/ {infm=1; next}
    infm && /^---[[:space:]]*$/ {exit}
    infm {
      line=$0
      if (line ~ "^"k":[[:space:]]*") {
        sub("^"k":[[:space:]]*", "", line)
        print line
        exit
      }
    }
  ' "$file"
}

# Is SPEC <id> (e.g. SPEC-027) SHIPPED? Resolves docs/specs/<id>-*.md and reads its
# Status: header the same way the hooks do (prefix-match, case-insensitive).
# exit 0 = SHIPPED; exit 1 = not shipped / unresolvable / no spec.
spec_is_shipped() {
  local id="$1" sdir; sdir="$(specs_dir)" || return 1
  local matches=("$sdir/$id-"*.md)
  [ "${#matches[@]}" -ge 1 ] || return 1
  local f="${matches[0]}"
  grep -qiE '^Status:[[:space:]]*SHIPPED' "$f"
}

# --- subcommands ------------------------------------------------------------

drafts_archive() {
  local dry=0
  [ "${1:-}" = "--dry-run" ] && dry=1
  local dir; dir="$(drafts_dir)" || return $?
  [ -d "$dir" ] || { echo "(no goal drafts)"; return 0; }

  local moved=0 f slug target id done_dir="$dir/done"
  for f in "$dir"/*.md; do
    slug="$(basename "$f" .md)"
    target="$(draft_get "$f" target_spec)"
    # Pull a SPEC-NNN token out of target_spec ("SPEC-027", "(none)", "(none yet; ...)").
    id="$(printf '%s\n' "$target" | grep -oE 'SPEC-[0-9]+' | head -1 || true)"
    [ -n "$id" ] || continue                       # specless draft: stays
    spec_is_shipped "$id" || continue              # unresolvable or not shipped: stays

    if [ "$dry" -eq 1 ]; then
      echo "would archive $slug ($id SHIPPED) -> done/"
      moved=$((moved + 1))
      continue
    fi
    # Never clobber an already-archived copy (never destroy on archive).
    if [ -e "$done_dir/$slug.md" ]; then
      echo "skip $slug: done/$slug.md already exists (not overwriting)" >&2
      continue
    fi
    mkdir -p "$done_dir"
    # Flip status -> shipped in the frontmatter, then move (atomic write + mv, no rm of content).
    local tmp="$f.tmp.$$"
    awk '
      NR==1 && /^---[[:space:]]*$/ {infm=1; print; next}
      infm && /^---[[:space:]]*$/ {infm=0; print; next}
      infm && /^status:[[:space:]]*/ && !d {print "status: shipped"; d=1; next}
      {print}
    ' "$f" > "$tmp" && mv "$tmp" "$f"
    mv "$f" "$done_dir/$slug.md"
    echo "archived $slug ($id SHIPPED) -> done/"
    moved=$((moved + 1))
  done

  [ "$moved" -eq 0 ] && echo "no shipped drafts to archive"
  return 0
}

drafts_list() {
  local dir; dir="$(drafts_dir)" || return $?
  local files=()
  [ -d "$dir" ] && files=("$dir"/*.md)
  if [ "${#files[@]}" -eq 0 ]; then
    echo "(no goal drafts)"
    return 0
  fi
  local f slug target st
  for f in "${files[@]}"; do
    slug="$(basename "$f" .md)"
    target="$(draft_get "$f" target_spec)"
    st="$(draft_get "$f" status)"
    printf '%s -> %s (%s)\n' "$slug" "${target:-(none)}" "${st:-?}"
  done
}

# --- dispatch ---------------------------------------------------------------

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    archive) drafts_archive "$@";;
    list)    drafts_list "$@";;
    dir)     drafts_dir;;
    *) echo "usage: goal-drafts.sh {archive [--dry-run]|list|dir}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
