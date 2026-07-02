#!/usr/bin/env bash
# mega-merge.sh -- ship-layer auto-merge ENFORCEMENT for the mega lane (ADR-0028 P2/P3,
# kit-hardening SG-08). Auto-merge RIDES ON the ship-gate; it never bypasses it.
#
# DECISION is separated from ACTION (two verbs) so the decision is testable without side
# effects, and the action is dry-run by default so a passing gate alone never touches `gh`:
#
#   gate  <rid> <lane>                     decision only, no side effects. Exit 0 iff
#                                           lib/gate-ledger.sh check <lane> <rid> passes
#                                           (every required measure-twice gate for <lane>
#                                           has a ran|override entry in <rid>'s ledger).
#                                           REUSES gate-ledger check verbatim -- never
#                                           re-implements or loosens the ship-gate's own
#                                           required-gate logic. Exit 1 + the gaps otherwise.
#
#   merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]
#                                           action. Runs `gate` FIRST; a failing or missing
#                                           gate REFUSES unconditionally (prints BLOCKED,
#                                           logs it, exits nonzero, never touches `gh`) --
#                                           a failing/missing gate can never auto-merge,
#                                           the exact mis-build ADR-0028 names as the risk.
#                                           A passing gate still only PRINTS the `gh pr
#                                           merge` it would run unless --execute is given.
#
# Per-run merge posture (mirrors the ops-toolkit plan-for-mega-goal skill's
# merge_autonomy knob; the ONE team-facing flag ADR-0028 calls out):
#   MEGA_MERGE_POSTURE=auto-to-final (default) | per-pr-review
#     auto-to-final  -- an `auto`-tagged sub-goal's PR merges once its gate passes
#                       (still requires --execute to actually call gh; see above).
#     per-pr-review  -- merge ALWAYS dry-runs, regardless of --execute or the gate
#                       result, so a team run keeps a human on every PR.
#   Resolution: --posture=<value> flag > MEGA_MERGE_POSTURE env > default auto-to-final.
#
# This script never sees a `gate`-tagged sub-goal or the held final PR under
# `gated-final` -- routing those away from `merge` is commands/mega.md's job (mirrors
# /kit:dispatch and the skill: a human always merges those).
#
# Subcommands:
#   gate  <rid> <lane>
#   merge <pr> <rid> <lane> [--execute] [--posture=<val>]
set -uo pipefail

MM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_LEDGER="${MEGA_MERGE_GATE_LEDGER:-$MM_DIR/gate-ledger.sh}"
# Durable run-telemetry root (SPEC-097): resolve + one-time additive migration.
# shellcheck source=lib/kit-log-dir.sh
source "$MM_DIR/kit-log-dir.sh" || { echo "FATAL: lib/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
kit_migrate_log_dir || true
LOG_DIR="$(kit_resolve_log_dir)"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

_log() {  # rid text
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  printf '%s | %s | %s\n' "$(now)" "${1:-?}" "${2:-}" >> "$LOG_DIR/mega-merge.log" 2>/dev/null || true
}

# gate <rid> <lane> -- DECISION ONLY. No file writes, no gh calls. Reuses
# gate-ledger.sh check() byte-for-byte (same lane x phase matrix hooks/ship-gate.sh
# enforces at push), so this can never drift looser than the ship-gate itself.
gate() {
  local rid="${1:-}" lane="${2:-}"
  [ -n "$rid" ] && [ -n "$lane" ] || { echo "usage: gate <rid> <lane>" >&2; return 64; }
  [ -f "$GATE_LEDGER" ] || { echo "gate: gate-ledger.sh not found at $GATE_LEDGER" >&2; return 1; }
  bash "$GATE_LEDGER" check "$lane" "$rid"
}

_resolve_posture() {
  local flag="${1:-}"
  if [ -n "$flag" ]; then printf '%s\n' "$flag"; return; fi
  printf '%s\n' "${MEGA_MERGE_POSTURE:-auto-to-final}"
}

# merge <pr> <rid> <lane> [--execute] [--posture=<val>] -- ACTION.
merge() {
  local pr="${1:-}" rid="${2:-}" lane="${3:-}"
  [ -n "$pr" ] && [ -n "$rid" ] && [ -n "$lane" ] || {
    echo "usage: merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]" >&2
    return 64
  }
  shift 3 2>/dev/null || true
  case "$pr" in
    ''|*[!0-9]*) echo "merge: <pr> must be a bare PR number (got '$pr')" >&2; return 64 ;;
  esac

  local execute=0 posture_flag="" arg
  for arg in "$@"; do
    case "$arg" in
      --execute) execute=1 ;;
      --posture=*) posture_flag="${arg#--posture=}" ;;
    esac
  done
  local posture; posture="$(_resolve_posture "$posture_flag")"

  local gate_out
  if ! gate_out="$(gate "$rid" "$lane" 2>&1)"; then
    {
      echo "BLOCKED: ship-gate not satisfied, refusing auto-merge for PR #$pr (rid=$rid, lane=$lane)."
      printf '%s\n' "$gate_out" | sed 's/^/  /'
      echo "Run the missing gate(s), or record an explicit override (audited):"
      echo "  bash \"$GATE_LEDGER\" override $rid <phase> \"<reason>\""
    } >&2
    _log "$rid" "BLOCKED merge pr=$pr lane=$lane (gate failed)"
    return 1
  fi

  local cmd_str="gh pr merge $pr --squash --delete-branch"
  if [ "$posture" = "per-pr-review" ]; then
    echo "DRY-RUN (posture=per-pr-review, a human reviews every PR): $cmd_str"
    _log "$rid" "DRY-RUN merge pr=$pr lane=$lane posture=per-pr-review"
    return 0
  fi
  if [ "$execute" -ne 1 ]; then
    echo "DRY-RUN (gate passed; pass --execute to actually run this): $cmd_str"
    _log "$rid" "DRY-RUN merge pr=$pr lane=$lane posture=$posture"
    return 0
  fi

  echo "EXECUTING: $cmd_str"
  _log "$rid" "EXECUTE merge pr=$pr lane=$lane posture=$posture"
  gh pr merge "$pr" --squash --delete-branch
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  gate)  gate "$@" ;;
  merge) merge "$@" ;;
  *) echo "usage: mega-merge.sh {gate <rid> <lane>|merge <pr> <rid> <lane> [--execute] [--posture=<auto-to-final|per-pr-review>]}" >&2; exit 64 ;;
esac
