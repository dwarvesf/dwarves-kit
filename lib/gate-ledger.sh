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
#   start    <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]   record routing facts (SPEC-061/062)
#   record   <rid> <phase> <ran|skipped> [reason]   append a gate decision
#   action   <rid> <text>              append an action-log line
#   override <rid> <phase> <reason>    record a human override for a gate
#   check    <lane> <rid>              exit 0 if every required gate has a ran|override entry; else 1
#   show     <rid>                     print the run's ledger
#   plan     <lane>                    the lane's ordered phase checklist (SPEC-063)
#   progress <rid> <lane>              plan x ledger -> "step k/n" + checklist (SPEC-063)
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

# START records the run's routing facts for lane telemetry (SPEC-061): the lane the
# operator chose, the classifier's suggestion, the work type, and the repo. One line per
# run, written at assign/start time; lib/lane-telemetry.sh aggregates these read-side.
start() {
  local rid="${1:-}" lane="${2:-}" classified="${3:-}" type="${4:-}" ctype="${5:-}" repo="${6:-}"
  if [ -z "$rid" ] || [ -z "$lane" ] || [ -z "$classified" ] || [ -z "$type" ]; then
    echo "usage: start <rid> <chosen-lane> <classified-lane> <chosen-type> [classified-type] [repo]" >&2; return 64
  fi
  [ -n "$repo" ] || repo="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
  # the KV blob is space-split read-side; a space in any value corrupts the parse
  repo="$(printf '%s' "$repo" | tr ' ' '-')"
  type="$(printf '%s' "$type" | tr ' ' '-')"
  ctype="$(printf '%s' "$ctype" | tr ' ' '-')"
  lane="$(printf '%s' "$lane" | tr ' ' '-')"
  classified="$(printf '%s' "$classified" | tr ' ' '-')"
  mkdir -p "$RUNS_DIR"
  local line
  line="$(printf '%s | START | lane=%s classified=%s type=%s' "$(now)" "$lane" "$classified" "$type")"
  [ -n "$ctype" ] && line="$line ctype=$ctype"
  printf '%s repo=%s\n' "$line" "$repo" >> "$(ledger_file "$rid")"
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

# plan: the lane's ordered phase checklist, derived from the WORKFLOW matrix (skip cells
# omitted; measure-twice = required, run-lite = lite). grill is prepended as the universal
# intake phase (SPEC-058; tiny lane exempt). This is what /kit:assign prints right after a
# lane is committed, so the operator sees the road before the run starts (SPEC-063).
plan() {
  local lane="${1:-}"; [ -n "$lane" ] || { echo "usage: plan <lane>" >&2; return 64; }
  local rows; rows="$(matrix_for_lane "$lane")"
  [ -n "$rows" ] || { echo "unknown lane '$lane' (not a column in the WORKFLOW matrix)" >&2; return 1; }
  local i=0 ph cell mark
  if [ "$lane" != "tiny" ]; then
    i=1; printf '%2d. %-18s %s\n' 1 "grill" "intake (universal, SPEC-058)"
  fi
  while IFS=$'\t' read -r ph cell; do
    case "$cell" in
      measure-twice) mark="required" ;;
      run-lite)      mark="lite" ;;
      *) continue ;;
    esac
    i=$((i+1))
    printf '%2d. %-18s %s\n' "$i" "$(normalize_phase "$ph")" "$mark"
  done <<< "$rows"
}

# progress: plan x ledger -> one status line + checklist. A phase counts done when the
# ledger carries ANY entry for it (ran, skipped-with-reason, override); the current step
# is the first phase without one. Commands print this at phase entry (SPEC-063).
progress() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: progress <rid> <lane>" >&2; return 64; }
  local f; f="$(ledger_file "$rid")"
  local total=0 done_n=0 cur="" cur_idx=0 list=""
  local idx ph rest
  while IFS= read -r pline; do
    idx="${pline%%.*}"; idx="$(printf '%s' "$idx" | tr -d ' ')"
    ph="$(printf '%s' "$pline" | awk '{print $2}')"
    total=$((total+1))
    # disposed = ran / override / skipped WITH a reason; a bare skip stays visible as a gap
    if [ -f "$f" ] && awk -F' [|] ' -v p="$ph" '$2=="GATE" && $3==p && ($4!="skipped" || (NF>=5 && $5!="")) {found=1} END{exit !found}' "$f"; then
      done_n=$((done_n+1)); list="$list ✓$ph"
    elif [ -z "$cur" ]; then
      cur="$ph"; cur_idx="$idx"; list="$list ▶$ph"
    else
      list="$list ·$ph"
    fi
  done < <(plan "$lane")
  [ "$total" -gt 0 ] || return 1
  if [ -z "$cur" ]; then
    printf '%s · %s · complete (%d/%d)\n' "$rid" "$lane" "$done_n" "$total"
  else
    printf '%s · %s · step %s/%d (%s)\n' "$rid" "$lane" "$cur_idx" "$total" "$cur"
  fi
  printf ' %s\n' "$list"
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  required) required "$@" ;;
  start)    start "$@" ;;
  record)   record "$@" ;;
  action)   action "$@" ;;
  override) override "$@" ;;
  check)    check "$@" ;;
  show)     show "$@" ;;
  plan)     plan "$@" ;;
  progress) progress "$@" ;;
  *) echo "usage: gate-ledger.sh {required|start|record|action|override|check|show|plan|progress} ..." >&2; exit 64 ;;
esac
