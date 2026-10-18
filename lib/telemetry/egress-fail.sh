#!/usr/bin/env bash
# egress-fail.sh -- make a failed LLM call visible without ever blocking.
#
# WHY: harvest, backlog-stage, skill-review, session-audit and reflect propose call `claude -p`
# and exit 0 on any failure, so a model or auth outage read as "nothing learned". They stay
# fail-open; on a failed or empty call each one now appends ONE line to the ledger stream
# egress-failures.log (through lib/ledger/ledger.sh), and /kit:start shows a one-line summary.
#
# Line shape: <ISO8601 UTC> | <source> | <reason>
#
# Two use modes:
#   sourced   : `source lib/telemetry/egress-fail.sh` then `egress_fail <source> <reason>`
#   standalone: `egress-fail.sh record <source> <reason>` (for Python callers)
#               `egress-fail.sh summary [days]`   (default 7; prints ONE line, or nothing)
#
# Never fails and never prints on the record path: a hook calls it on its failure path.
[ -n "${_KIT_EGRESS_FAIL_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_EGRESS_FAIL_SOURCED=1

_EGRESS_FAIL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EGRESS_STREAM="egress-failures.log"

# egress_fail <source> <reason>: append one line; a field is stripped of pipes and newlines.
egress_fail() {
  local src="${1:-unknown}" reason="${2:-unknown}" ts
  src="${src//[|$'\n\r']/ }"; reason="${reason//[|$'\n\r']/ }"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ( source "$_EGRESS_FAIL_DIR/../ledger/ledger.sh" && ledger_append "$_EGRESS_STREAM" "$ts | $src | $reason" ) >/dev/null 2>&1 || true
  return 0
}

# egress_summary [days]: one line naming each source with failures in the window, else nothing.
egress_summary() {
  local days="${1:-7}" cutoff body
  case "$days" in ''|*[!0-9]*) days=7 ;; esac
  cutoff="$(date -u -v-"${days}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "$days days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
  [ -n "$cutoff" ] || return 0
  body="$( ( source "$_EGRESS_FAIL_DIR/../ledger/ledger.sh" && ledger_read "$_EGRESS_STREAM" ) 2>/dev/null \
    | awk -F' [|] ' -v cutoff="$cutoff" -v days="$days" '
        $1 >= cutoff && NF >= 3 { n[$2]++; if (!($2 in seen)) { seen[$2] = 1; order[++k] = $2 } }
        END {
          for (i = 1; i <= k; i++) {
            s = order[i]
            out = out (out == "" ? "" : "; ") s " failed " n[s] (n[s] == 1 ? " time" : " times")
          }
          if (out != "") print out " in the last " days " days (LLM egress, see egress-failures.log)"
        }')"
  [ -z "$body" ] || printf '%s\n' "$body"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1:-}" in
    record)  shift; egress_fail "$@" ;;
    summary) shift; egress_summary "$@" ;;
    *) echo "usage: egress-fail.sh record <source> <reason> | summary [days]" >&2; exit 64 ;;
  esac
fi
