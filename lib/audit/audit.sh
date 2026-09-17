#!/usr/bin/env bash
# audit.sh -- the cadence trigger for the audit-loop instances (docs/patterns/audit-loop.md).
#
# Every instance (doc-drift, ci-drift, backlog-reconcile, ...) ran on demand only: nothing
# said when a pass was OVERDUE, so an instance that nobody remembered simply never ran. This
# script is the smallest thing that answers "which passes are due?" and nothing more. It
# starts no daemon, installs no cron, and never runs an instance itself.
#
# The cadence per instance is declared ONCE, in the `## Cadence` table of
# docs/patterns/audit-loop.md, and parsed from there. A new instance becomes schedulable by
# adding a row to that table; there is no second list to keep in sync.
#
# The last-run marker is a line in the kit's own append-only ledger (lib/ledger/ledger.sh),
# stream `audit-runs.log`. No marker exists until a pass records one, so an instance that
# never ran reads as due, which is the honest answer.
#
# Verbs:
#   audit due                      report each instance: cadence, last run, age, due or not
#   audit cadences                 the declared table, as <instance><TAB><days>
#   audit ran <instance> [note]    record that a pass just ran (the only write path)
#
# Exit: 0 whenever the command itself ran. `due` reports; it does not fail on a due
# instance, because a scheduled caller reads the list rather than an exit code.

set -euo pipefail

LIB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KIT_DIR="$(cd "$LIB_ROOT/.." && pwd)"
PATTERN_DOC="$KIT_DIR/docs/patterns/audit-loop.md"
RUNS_STREAM="audit-runs.log"

# shellcheck source=lib/ledger/ledger.sh
source "$LIB_ROOT/ledger/ledger.sh"

cadence_days() { # <name> -> days, empty when the word is not a legal cadence
  case "$1" in
    weekly) echo 7 ;;
    biweekly) echo 14 ;;
    monthly) echo 30 ;;
    quarterly) echo 90 ;;
    *) echo "" ;;
  esac
}

# Parse the `## Cadence` table only: the doc has several other tables, and a row elsewhere
# must not become a schedulable instance by accident. Emits <instance><TAB><days>.
read_cadences() {
  [ -f "$PATTERN_DOC" ] || { echo "audit: pattern doc missing: $PATTERN_DOC" >&2; return 1; }
  awk '
    /^## Cadence[[:space:]]*$/ { in_section = 1; next }
    /^## / { in_section = 0 }
    in_section && /^\|/ {
      split($0, cell, "|")
      name = cell[2]; cadence = cell[3]
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", cadence)
      if (name == "Instance" || name ~ /^-*$/ || name == "") next
      print name "\t" cadence
    }
  ' "$PATTERN_DOC" | while IFS="$(printf '\t')" read -r name cadence; do
    days="$(cadence_days "$cadence")"
    if [ -z "$days" ]; then
      echo "audit: unknown cadence '$cadence' for '$name' in $PATTERN_DOC" >&2
      continue
    fi
    printf '%s\t%s\n' "$name" "$days"
  done
}

# Last recorded run for one instance, as an epoch second. Empty when it never ran.
# Lines are `<epoch> <iso8601> <instance> <note>`; the last matching line wins, so the
# ledger stays append-only and no reader has to sort it.
last_run_epoch() { # <instance>
  local instance="$1" line
  line="$(ledger_read "$RUNS_STREAM" | awk -v i="$instance" '$3 == i { last = $1 } END { if (last) print last }')" || true
  printf '%s' "$line"
}

cmd_cadences() { read_cadences; }

cmd_ran() {
  local instance="${1:-}"; shift || true
  [ -n "$instance" ] || { echo "audit ran: usage: audit ran <instance> [note]" >&2; return 64; }
  # Refuse an instance the pattern doc does not declare: a typo would otherwise write a
  # marker nothing ever reads, and `due` would keep reporting the real instance as overdue.
  if ! read_cadences | cut -f1 | grep -qxF "$instance"; then
    echo "audit ran: '$instance' is not declared in the Cadence table of $PATTERN_DOC" >&2
    return 1
  fi
  local now iso
  now="$(date +%s)"
  iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ledger_append "$RUNS_STREAM" "$now $iso $instance ${*:-recorded}"
  echo "recorded: $instance at $iso"
}

cmd_due() {
  local now; now="$(date +%s)"
  printf '%-22s %-10s %-12s %-6s %s\n' "INSTANCE" "CADENCE" "LAST RUN" "AGE" "DUE"
  local instance days last age lastlabel agelabel due
  while IFS="$(printf '\t')" read -r instance days; do
    [ -n "$instance" ] || continue
    last="$(last_run_epoch "$instance")"
    if [ -z "$last" ]; then
      lastlabel="never"; agelabel="-"; due="DUE"
    else
      age=$(( (now - last) / 86400 ))
      lastlabel="$(date -u -r "$last" +%Y-%m-%d 2>/dev/null || date -u -d "@$last" +%Y-%m-%d)"
      agelabel="${age}d"
      if [ "$age" -ge "$days" ]; then due="DUE"; else due="-"; fi
    fi
    printf '%-22s %-10s %-12s %-6s %s\n' "$instance" "${days}d" "$lastlabel" "$agelabel" "$due"
  done < <(read_cadences)
}

main() {
  local cmd="${1:-}"; shift 2>/dev/null || true
  case "$cmd" in
    due) cmd_due "$@" ;;
    cadences) cmd_cadences "$@" ;;
    ran) cmd_ran "$@" ;;
    ""|-h|--help|help)
      cat >&2 <<'USAGE'
audit -- cadence trigger for the audit-loop instances (docs/patterns/audit-loop.md)
  audit due                     which instances the cadence has come around for
  audit cadences                the declared instance -> period (days) table
  audit ran <instance> [note]   record that a pass just ran
Cadence is declared in the `## Cadence` table of docs/patterns/audit-loop.md.
The kit ships no cron and no daemon: a human or a scheduled job reads `due`.
USAGE
      return 0 ;;
    *) echo "audit: unknown verb '$cmd' (try: due, cadences, ran)" >&2; return 64 ;;
  esac
}

main "$@"
