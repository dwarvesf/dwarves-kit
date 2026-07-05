#!/usr/bin/env bash
# dispatch-gate.sh -- the disjointness gate + drift guard for /kit:dispatch.
#
# The moat that makes bounded cross-goal fan-out safe (ADR-0019, SPEC-032). Pure
# bash + glob; no binary, no runtime, no scheduler. Two goals run concurrently only
# when their declared `## Touches` file globs are provably disjoint; any pair the gate
# cannot PROVE disjoint is serialized (DEC-008, conservative prove-or-serialize). The
# drift guard then checks the real diff stayed inside the declared globs and never
# touched a lead-owned shared surface.
#
# `## Touches` is constrained to directory-prefix globs (`dir/**`, `dir/sub/**`).
# Anything fancier (`*.md`, `**/x`, `a/*.ext`, brace globs) is NOT a clean prefix and
# forces a conservative "cannot prove disjoint" (= overlap = serialize).
#
# The hands-off shared-surface list is NOT hardcoded here: it is extracted from
# WORKFLOW.md at runtime (single source, no drift), the same list test-meta.sh reads.
#
# Subcommands:
#   touches <spec>            print the spec's normalized dir prefixes (one per line)
#   disjoint <specA> <specB>  exit 0 disjoint | 1 overlap (serialize) | 2 undeclared
#   plan <spec...>            print "PARALLEL <spec>" / "WAIT <spec> after <spec>" lines
#   drift <base> <branch> <spec>   exit 0 clean | 1 drift (out-of-glob or hands-off)
#
# Usage from a command: source it, or call as `bash lib/gate/dispatch-gate.sh <subcmd> ...`.

set -euo pipefail

# Resolve the kit root (this file lives in <root>/lib/).
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$GATE_DIR/../.." && pwd)"  # repo root = two levels above lib/<subsystem>/
WORKFLOW="${DISPATCH_GATE_WORKFLOW:-$KIT_ROOT/WORKFLOW.md}"

# --- prefix extraction ------------------------------------------------------

# Normalize ONE glob to a directory prefix. A clean directory-prefix glob (`dir/**`,
# `dir/sub/**`) -> the prefix with the trailing `/**` dropped. Anything else (`*.md`,
# `**/x`, `a/*.ext`, a brace glob) -> the glob verbatim with a leading "?" marker so
# callers treat it as unprovable (forces conservative overlap). This is the single
# source for the prefix rule, shared by gate_touches (spec `## Touches` lists) and
# lib/goal/goal-registry.sh (cross-session CLI globs). Keep them on one rule (ID-029).
gate_normalize_glob() {
  local g="$1"
  if printf '%s' "$g" | grep -qE '^[A-Za-z0-9._/-]+/\*\*$'; then
    printf '%s\n' "${g%/\*\*}"
  else
    printf '?%s\n' "$g"
  fi
}

# Pull the `## Touches` list from a spec and normalize each entry to a directory
# prefix (strip the trailing `/**`). A non-conforming glob is emitted verbatim with a
# leading "?" marker so callers can treat it as unprovable.
gate_touches() {
  local spec="$1"
  [ -f "$spec" ] || return 0
  # The section runs from "## Touches" to the next "## " heading.
  awk '
    /^## Touches/ {grab=1; next}
    /^## / {grab=0}
    grab {print}
  ' "$spec" | while IFS= read -r line; do
    # Strip markdown list markers, backticks, and surrounding whitespace.
    local g
    g="$(printf '%s' "$line" | sed -E 's/^[[:space:]]*[-*][[:space:]]*//; s/`//g; s/[[:space:]]+$//; s/^[[:space:]]+//')"
    [ -n "$g" ] || continue
    # Skip prose lines (must look like a path glob, not a sentence).
    case "$g" in *" "*) continue;; esac
    gate_normalize_glob "$g"
  done
}

# Does prefix $1 overlap prefix $2? Overlap iff equal, or one is an ancestor dir of
# the other (compared on path-segment boundaries, so a/ does NOT match ab/).
prefix_overlap() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  case "$b" in "$a"/*) return 0;; esac
  case "$a" in "$b"/*) return 0;; esac
  return 1
}

# --- disjointness gate ------------------------------------------------------

gate_disjoint() {
  local specA="$1" specB="$2"
  local pa pb
  pa="$(gate_touches "$specA")"
  pb="$(gate_touches "$specB")"
  # Undeclared file-set is the "gate lies" default failure -> REJECT (exit 2).
  if [ -z "$pa" ] || [ -z "$pb" ]; then
    echo "REJECT: a dispatch-eligible spec has no '## Touches' globs (undeclared file-set)" >&2
    return 2
  fi
  # Any unprovable glob (marked with ?) forces conservative overlap.
  if printf '%s\n%s\n' "$pa" "$pb" | grep -q '^?'; then
    return 1
  fi
  local x y
  while IFS= read -r x; do
    [ -n "$x" ] || continue
    while IFS= read -r y; do
      [ -n "$y" ] || continue
      if prefix_overlap "$x" "$y"; then
        return 1
      fi
    done <<< "$pb"
  done <<< "$pa"
  return 0
}

# --- parallel-safe set + wait-queue -----------------------------------------
# Greedy: walk specs in order; a spec is PARALLEL if it is disjoint from every spec
# already admitted to the parallel set, else it WAITs on the first admitted spec it
# overlaps. Over-serializing is safe-but-slower; merges are human-gated (DEC-008).
gate_plan() {
  local specs=("$@")
  local admitted=()
  local s a waits
  for s in "${specs[@]}"; do
    waits=""
    for a in "${admitted[@]:-}"; do
      [ -n "$a" ] || continue
      if ! gate_disjoint "$s" "$a" >/dev/null 2>&1; then
        waits="$a"
        break
      fi
    done
    if [ -z "$waits" ]; then
      admitted+=("$s")
      echo "PARALLEL $s"
    else
      echo "WAIT $s after $waits"
    fi
  done
}

# --- hands-off extraction (from WORKFLOW.md, single source) ------------------
# The "### Hands-off shared-surface list" bullets. Normalize each to a match prefix:
# strip a trailing glob (docs/retro/v*.md -> docs/retro/), keep exact files as-is.
handsoff_prefixes() {
  awk '
    /^### Hands-off shared-surface list/ {grab=1; next}
    grab && /^### / {grab=0}
    grab && /^- / {print}
  ' "$WORKFLOW" | sed -E 's/^- +//; s/`//g; s/ +\(.*$//; s/[[:space:]]+$//' \
    | while IFS= read -r e; do
        [ -n "$e" ] || continue
        case "$e" in
          */v\**) printf '%s\n' "${e%%v\**}";;   # docs/retro/v*.md -> docs/retro/
          *\**)   printf '%s\n' "${e%%\**}";;     # any other glob -> dir prefix
          *)      printf '%s\n' "$e";;            # exact file
        esac
      done
}

# Is path $1 under (or equal to) any hands-off entry?
is_handsoff() {
  local f="$1" h
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    [ "$f" = "$h" ] && return 0
    case "$f" in "$h"*) return 0;; esac   # h is a dir prefix ending in / or an exact stem
  done < <(handsoff_prefixes)
  return 1
}

# --- drift guard ------------------------------------------------------------

gate_drift() {
  local base="$1" branch="$2" spec="$3"
  local prefixes changed f under
  prefixes="$(gate_touches "$spec" | grep -v '^?' || true)"
  changed="$(git diff --name-only "$base..$branch" 2>/dev/null || true)"
  local drift=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if is_handsoff "$f"; then
      echo "DRIFT: $f is a lead-owned hands-off surface (worker must not write it)" >&2
      drift=1; continue
    fi
    under=1
    local p
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$f" in "$p"/*) under=0; break;; "$p") under=0; break;; esac
    done <<< "$prefixes"
    if [ "$under" -ne 0 ]; then
      echo "DRIFT: $f is outside the spec's declared ## Touches globs" >&2
      drift=1
    fi
  done <<< "$changed"
  return "$drift"
}

# --- dispatch ---------------------------------------------------------------

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    touches)  gate_touches "$@";;
    disjoint) gate_disjoint "$@";;
    plan)     gate_plan "$@";;
    drift)    gate_drift "$@";;
    *) echo "usage: dispatch-gate.sh {touches|disjoint|plan|drift} ..." >&2; return 64;;
  esac
}

# Only run main when executed, not when sourced.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
