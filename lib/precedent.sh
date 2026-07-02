#!/usr/bin/env bash
# precedent.sh -- "have we done something like this before?" at intake (SPEC-068 / ID-056).
#
# The kit WRITES knowledge constantly (specs, retros, run ledgers, ADRs) but nothing READ
# it back at intake, so every new task started from a blank page. This is the read-back:
# keyword-grep the durable surfaces, rank files by distinct-keyword hits, print the top
# matches. /kit:assign and /kit:grill run it right after classification so prior art
# shapes the questions and the Done=. Grep-based by design: no embeddings, no index, no
# daemon; if grep stops being enough, that is a future spec's problem.
#
# Usage:
#   precedent.sh find "<task description>" [max]   -> ranked precedent list (default 5)
#
# Surfaces searched (repo-relative when present): docs/specs/, docs/decisions/,
# docs/retro/, docs/verification/, plus run-ledger reasons in $DWARVES_KIT_LOG_DIR/runs/.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
# Durable run-telemetry root (SPEC-097): resolve + one-time additive migration.
PRECEDENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/kit-log-dir.sh
source "$PRECEDENT_DIR/kit-log-dir.sh" || { echo "FATAL: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"

# keywords: lowercase, dedup, drop stopwords + short tokens; keep the 8 most specific
_keywords() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]-' '\n' \
    | grep -vE '^(the|a|an|and|or|to|of|in|on|for|with|into|from|that|this|it|is|are|be|as|at|by|we|our|all|any|via|per|the)$' \
    | grep -vE '^-' | awk 'length($0) >= 4' | sort -u | head -8 || true   # empty after filtering is a valid result, not a pipeline failure
}

find_precedents() {
  local desc="${1:-}" max="${2:-5}"
  [ -n "$desc" ] || { echo "usage: find \"<task description>\" [max]" >&2; return 64; }
  printf '%s' "$max" | grep -qE '^[1-9][0-9]*$' || { echo "max must be a positive integer" >&2; return 64; }
  local kws; kws="$(_keywords "$desc")"
  [ -n "$kws" ] || { echo "(no searchable keywords in the description)"; return 0; }

  {
    # repo surfaces: one line per file per keyword hit
    local dir kw
    for dir in docs/specs docs/decisions docs/retro docs/verification; do
      [ -d "$ROOT/$dir" ] || continue
      while IFS= read -r kw; do
        grep -rlis -- "$kw" "$ROOT/$dir" 2>/dev/null || true
      done <<< "$kws"
    done
    # run-ledger reasons (the operational memory)
    if [ -d "$LOG_DIR/runs" ]; then
      while IFS= read -r kw; do
        grep -lis -- "$kw" "$LOG_DIR/runs/"*.log 2>/dev/null || true
      done <<< "$kws"
    fi
  } | sort | uniq -c | sort -rn | head -"$max" | while read -r hits file; do
    # one headline line per match: the file + its first heading or START line
    local head1
    head1="$(grep -m1 -E '^# |^\| START' "$file" 2>/dev/null | head -c 100 || true)"
    printf '%2dx  %s\n      %s\n' "$hits" "${file#"$ROOT"/}" "${head1:-"(no heading)"}"
  done
  return 0
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    find) find_precedents "$@" ;;
    *) echo "usage: precedent.sh find \"<task description>\" [max]" >&2; return 64 ;;
  esac
}

main "$@"
