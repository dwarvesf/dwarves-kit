#!/usr/bin/env bash
# gate-ledger.sh -- lane-aware gate ledger + action log + ship-completeness check.
#
# The single source for "which gates a lane requires" is the WORKFLOW.md lane×phase
# matrix; this parses it at runtime (no second copy), mirroring lib/dispatch-gate.sh's
# hands-off extraction. A matrix cell of `measure-twice` => the gate is REQUIRED for
# that lane. Records are append-only, operator-readable, and redacted (no command
# bodies). See docs/decisions/0024-gate-ledger-and-ship-enforcement.md.
#
# Subcommands:
#   required <lane>                     print the lane's required (measure-twice) gate keys
#   record   <rid> <phase> <ran|skipped> [reason]   append a gate decision
#   action   <rid> <text>              append an action-log line
#   override <rid> <phase> <reason>    record a human override for a gate
#   check    <lane> <rid>              exit 0 if every required gate has a ran|override entry; else 1
#   show     <rid>                     print the run's ledger
set -euo pipefail

GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$GATE_DIR/.." && pwd)"
WORKFLOW="${GATE_LEDGER_WORKFLOW:-$KIT_ROOT/WORKFLOW.md}"
LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
RUNS_DIR="$LOG_DIR/runs"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
runid() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }
ledger_file() { printf '%s/%s.log' "$RUNS_DIR" "$(runid "$1")"; }

# Stable key for a phase name: drop "(...)", lowercase, spaces -> dashes.
# "Design (opt-in)"->design, "Design critique (opt-in)"->design-critique,
# "Test plan (opt-in)"->test-plan, "Debug (off-cycle)"->debug, "UI design"->ui-design.
normalize_phase() {
  printf '%s' "$1" | sed -E 's/\([^)]*\)//g' | tr 'A-Z' 'a-z' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/-/g'
}

# print "<rawphase>\t<cell>" for each matrix row under the given lane column.
# Empty output => the lane column was not found (unknown lane).
matrix_for_lane() {
  awk -v lane="$1" '
    /^## Lane.*depth matrix/ {inmx=1; next}
    inmx && /^## / {exit}
    inmx && /^\| *Phase *\|/ {
      n=split($0, h, "|");
      for (i=1;i<=n;i++){gsub(/^ +| +$/,"",h[i]); if(h[i]==lane) col=i}
      next
    }
    inmx && col>0 && /^\|/ {
      if ($0 ~ /^\| *-+/) next;
      split($0, c, "|");
      ph=c[2]; gsub(/^ +| +$/,"",ph);
      cell=c[col]; gsub(/^ +| +$/,"",cell);
      if (ph!="" && ph!="Phase") print ph "\t" cell;
    }
  ' "$WORKFLOW"
}

required() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: required <lane>" >&2; return 64; }
  local rows ph cell
  rows="$(matrix_for_lane "$lane")"
  [ -n "$rows" ] || { echo "unknown lane '$lane' (not a column in the WORKFLOW matrix)" >&2; return 1; }
  while IFS=$'\t' read -r ph cell; do
    [ "$cell" = "measure-twice" ] && printf '%s\n' "$(normalize_phase "$ph")"
  done <<< "$rows"
  return 0
}

record() {
  local rid="${1:-}" raw="${2:-}" state="${3:-}"; shift 3 2>/dev/null || { echo "usage: record <rid> <phase> <ran|skipped> [reason]" >&2; return 64; }
  case "$state" in ran|skipped) ;; *) echo "state must be ran|skipped" >&2; return 64;; esac
  mkdir -p "$RUNS_DIR"
  printf '%s | GATE | %s | %s | %s\n' "$(now)" "$(normalize_phase "$raw")" "$state" "${*:-}" >> "$(ledger_file "$rid")"
}

action() {
  local rid="${1:-}"; shift 2>/dev/null || { echo "usage: action <rid> <text>" >&2; return 64; }
  mkdir -p "$RUNS_DIR"
  printf '%s | ACTION | %s\n' "$(now)" "${*:-}" >> "$(ledger_file "$rid")"
}

override() {
  local rid="${1:-}" raw="${2:-}"; shift 2 2>/dev/null || { echo "usage: override <rid> <phase> <reason>" >&2; return 64; }
  local reason="${*:-}"; [ -n "$reason" ] || { echo "override requires a reason" >&2; return 64; }
  mkdir -p "$RUNS_DIR"
  printf '%s | GATE | %s | override | %s\n' "$(now)" "$(normalize_phase "$raw")" "$reason" >> "$(ledger_file "$rid")"
}

show() { local f; f="$(ledger_file "${1:-}")"; if [ -f "$f" ]; then cat "$f"; else echo "(no ledger for '${1:-}')" >&2; return 1; fi; }

# exit 0 if every required (measure-twice) gate has a ran|override entry; else 1 + list gaps.
check() {
  local lane="${1:-}" rid="${2:-}"; [ -n "$lane" ] && [ -n "$rid" ] || { echo "usage: check <lane> <rid>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")"
  local missing=0 phase
  while IFS= read -r phase; do
    [ -n "$phase" ] || continue
    if [ ! -f "$f" ] || ! awk -F' [|] ' -v p="$phase" '$2=="GATE" && $3==p && ($4=="ran"||$4=="override"){f=1} END{exit !f}' "$f"; then
      echo "MISSING-GATE: $phase (required for lane '$lane'; no ran/override entry in the ledger)" >&2
      missing=1
    fi
  done < <(required "$lane")
  return "$missing"
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  required) required "$@" ;;
  record)   record "$@" ;;
  action)   action "$@" ;;
  override) override "$@" ;;
  check)    check "$@" ;;
  show)     show "$@" ;;
  *) echo "usage: gate-ledger.sh {required|record|action|override|check|show} ..." >&2; exit 64 ;;
esac
