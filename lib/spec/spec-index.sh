#!/usr/bin/env bash
# spec-index.sh -- read-only SPEC registry view across every docs/specs namespace.
#
# Specs can live co-located under any `*/docs/specs/` (the central docs/specs/ AND
# co-located ones like tools/<name>/docs/specs/, experiments/<slug>/docs/specs/,
# _meta/megagoals/<prog>/docs/specs/). Numbering is deliberately PER-NAMESPACE and
# LOCAL: each namespace owns its own SPEC-001.. sequence, so the same number can
# (and does) recur across namespaces. This command does NOT change that, and is NOT
# wired into spec-next / goal-drafts / precedent -- those stay namespace-scoped.
#
# This is purely the "show me every spec in one place" READ view: it scans every
# `*/docs/specs/SPEC-*.md` in the repo and prints them grouped by namespace, each
# group sorted by local number:
#
#   <namespace>
#     SPEC-NNN | <title> | <Status>
#
# namespace = "central docs/specs" for the central tree, else the co-located prefix
#             (e.g. "tools/bar" for tools/bar/docs/specs/)
# title     = the first `# ` heading (leading "# " / "Spec: " stripped), else the filename
# Status    = the first `Status:` header value if present, else "(none)"
#
# Stdlib/bash only -- no deps, no index, no daemon. Re-run to regenerate.
#
# Usage:
#   spec-index.sh          -> the grouped table (default; same as `list`)
#   spec-index.sh list     -> the grouped table
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Pull the title cheaply from a spec file (first `# ` heading wins).
_title() {
  local f="$1" t
  t="$(grep -m1 -E '^# ' "$f" 2>/dev/null || true)"
  if [ -n "$t" ]; then
    t="${t#\# }"          # drop leading "# "
    t="${t#Spec: }"       # drop a leading "Spec: " (kit idiom), if present
    printf '%s\n' "$t"
    return 0
  fi
  basename "$f" .md       # fall back to the filename
}

_status() {
  local f="$1" s
  s="$(grep -m1 -iE '^Status:[[:space:]]*' "$f" 2>/dev/null || true)"
  s="${s#*[Ss]tatus:}"
  # trim surrounding whitespace
  s="$(printf '%s' "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  printf '%s\n' "${s:-(none)}"
}

# Namespace label for a spec dir (e.g. "$ROOT/tools/bar/docs/specs").
_namespace() {
  local rel="${1#"$ROOT"/}"
  if [ "$rel" = "docs/specs" ]; then
    printf 'central docs/specs\n'
  else
    printf '%s\n' "${rel%/docs/specs}"   # strip trailing /docs/specs
  fi
}

list_specs() {
  local f num ns title status
  # Emit "namespace<TAB>NNN<TAB>row" per spec, sort by namespace then local number,
  # then walk the sorted stream printing a header per new namespace.
  find "$ROOT" -type f -path '*/docs/specs/SPEC-*.md' -not -path '*/.git/*' 2>/dev/null \
    | while IFS= read -r f; do
        num="$(basename "$f" | grep -oE 'SPEC-[0-9]+' | head -1)"
        [ -n "$num" ] || continue
        ns="$(_namespace "$(dirname "$f")")"
        title="$(_title "$f")"
        status="$(_status "$f")"
        printf '%s\t%s\t%s | %s | %s\n' \
          "$ns" "$(printf '%s' "$num" | grep -oE '[0-9]+')" \
          "$num" "$title" "$status"
      done \
    | sort -t$'\t' -k1,1 -k2,2n \
    | { last_ns=""
        while IFS=$'\t' read -r ns _num row; do
          if [ "$ns" != "$last_ns" ]; then
            [ -n "$last_ns" ] && printf '\n'
            printf '%s\n' "$ns"
            last_ns="$ns"
          fi
          printf '  %s\n' "$row"
        done; }
}

main() {
  local sub="${1:-list}"; shift 2>/dev/null || true
  case "$sub" in
    list) list_specs ;;
    *) echo "usage: spec-index.sh [list]" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
