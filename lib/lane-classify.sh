#!/usr/bin/env bash
# lane-classify.sh -- deterministic task-type -> risk-lane classifier.
#
# Turns a one-line task description into one of the WORKFLOW.md risk lanes
# (tiny | normal | full | bug | backfill) so the intake path (/kit:assign) and the
# dispatch path (/kit:dispatch) can auto-choose the lane instead of relying on ad-hoc
# judgment. Pure bash + grep; no binary.
#
# Flag-scoring model (absorbed from hoangnb24/repository-harness FEATURE_INTAKE, 2026-06-10;
# see docs/specs/SPEC-050 + docs/absorption/2026-06-10-repository-harness.md). Named risk flags
# are matched against the description:
#   - HARD-gate flags: any one hit -> `full` (mirrors the harness auto-escalate list + the
#     WORKFLOW full-lane triggers, PLUS a `kit-machinery` flag, the gap that misclassified the
#     adopt + install PRs as `normal` on 2026-06-10).
#   - SOFT flags: counted; 4+ -> `full`, 2-3 -> `normal` (noted as near-full).
# `explain` prints which flags fired so a classification (and any override) is auditable, not a
# black box. This SUGGESTS a lane; it never blocks ("Detect, don't dictate").
#
# Precedence (first match wins): backfill > tiny > hard-gate > bug > soft-count > normal. tiny
# stays above the hard-gate so "a typo about auth" is still a typo; backfill stays first so a
# keyword inside a doc task (e.g. "write its AGENTS.md") does not escalate.
#
# The `check` subcommand adds the floor guard (SPEC-053): given the lane actually CHOSEN
# plus the task text, it warns (advisory, exit 0) when the choice is lighter than the
# suggestion, so an under-sized full/bug task does not slip through /kit:assign unnoticed.
#
# Usage:
#   lane-classify.sh classify "<desc>"                 -> prints the lane, exit 0
#   lane-classify.sh explain  "<desc>"                 -> prints the lane + reason + fired flags
#   lane-classify.sh check <chosen-lane> "<desc>"      -> warn+log if chosen < floor, exit 0
#   lane-classify.sh lanes                              -> prints the 5 lane names
#   lane-classify.sh flags                              -> prints the flag names

set -euo pipefail

# Hard-gate flags (any hit -> full). name <-> regex, index-aligned.
_hard_name=(auth data-model audit-security external-provider public-contract weaken-validation kit-machinery)
_hard_re=(
  'auth[a-z]*|login|logout|password|jwt|\bsession(s)?\b|refresh token|permission|\brole(s)?\b|tenant'
  'migrat|schema|data[ -]model|uniqueness|retention|data loss|delete[s]? .*data|drop (table|column)'
  'audit|privacy|sensitive data|access log|secret|token|crypto|encrypt|\bsecurity\b|harden|vulnerab|exploit|injection|\bxss\b|\bcsrf\b|rate.?limit'
  'external (api|provider|service)|payment|billing|webhook|provider sdk|\bqueue(s)?\b|email send'
  'api contract|response envelope|public (api|contract)|client[ -]visible|breaking change'
  'weaken[s]? .*validation|remove[s]? .*validation|disabl[a-z]* .*(check|guard|validation)'
  '\bhook(s)?\b|gate-ledger|ship-gate|lane-classify|proof-gate|install\.sh|adopt\.sh|workflow\.md|adopt @|/?kit:adopt|adopt(s|ed|ing)? .{0,30}(agents?\.md|contract|kit|loader|marker|workflow|gate)|gate machinery|the kit.{0,12}(lane|gate|machinery|classifier)'
)
# Soft flags (counted; 4+ -> full, 2-3 -> normal-noted). name <-> regex, index-aligned.
_soft_name=(cross-platform existing-behavior weak-proof multi-domain concurrency)
_soft_re=(
  'cross[ -]platform|desktop.*mobile|native shell|deep link'
  'existing behavio|already (implemented|test-covered|shipped)|change[s]? .*(existing|current) behavio'
  'no tests?|missing tests?|untested|unclear test|weak (proof|coverage)'
  'multi[ -]domain|more than one .*domain|two domains'
  'concurren|race condition|\bparallel\b|locking|index\.lock'
)

# A name array out of sync with its regex array would mislabel `explain` output silently
# (review: parallel-array footgun). Fail loud at load instead.
[ "${#_hard_name[@]}" -eq "${#_hard_re[@]}" ] && [ "${#_soft_name[@]}" -eq "${#_soft_re[@]}" ] \
  || { echo "lane-classify: flag name/regex arrays are misaligned (bug)" >&2; exit 70; }

LANE=""; REASON=""; FIRED=""

# classify_core "<desc>" -- sets LANE, REASON, FIRED. The single source of truth both
# `classify` and `explain` read.
classify_core() {
  local lc; lc="$(printf '%s' "$*" | tr '[:upper:]' '[:lower:]')"
  LANE=""; REASON=""; FIRED=""

  # 1. backfill: brownfield operating-layer documentation (first, so an in-doc keyword like
  #    "write its AGENTS.md" does not pull the task into the kit-machinery hard-gate).
  if printf '%s' "$lc" | grep -qE 'backfill|operating[ -]layer|brownfield|document the existing|write (agents|claude)\.md'; then
    LANE=backfill; REASON="brownfield operating-layer docs"; FIRED=backfill; return 0
  fi

  # 2. tiny: pure cosmetic, regardless of subject (a typo about auth is still a typo).
  if printf '%s' "$lc" | grep -qE 'typo|whitespace|re-?word|copy[ -]?edit|comment|rename|formatting|one[ -]liner?|wording|doc(s)? fix|fix .*(typo|wording|comment)'; then
    LANE=tiny; REASON="pure cosmetic"; FIRED=tiny; return 0
  fi

  # 3. hard-gate flags -> full.
  local i hard=""
  for i in "${!_hard_re[@]}"; do
    if printf '%s' "$lc" | grep -qE "${_hard_re[$i]}"; then hard="$hard ${_hard_name[$i]}"; fi
  done
  if [ -n "$hard" ]; then
    LANE=full; REASON="hard-gate flag(s):$hard"; FIRED="${hard# }"; return 0
  fi

  # 4. bug: a defect, not a new feature.
  if printf '%s' "$lc" | grep -qE '\bbug\b|regression|failing test|broken|crash|defect|hotfix|stack ?trace|exception|fix the|fix a |repro'; then
    LANE=bug; REASON="defect / regression"; FIRED=bug; return 0
  fi

  # 5. soft-flag count: 4+ -> full, 2-3 -> normal (near-full), else default normal.
  local soft="" n=0
  for i in "${!_soft_re[@]}"; do
    if printf '%s' "$lc" | grep -qE "${_soft_re[$i]}"; then soft="$soft ${_soft_name[$i]}"; n=$((n + 1)); fi
  done
  if [ "$n" -ge 4 ]; then LANE=full;   REASON="$n soft flags (>=4):$soft"; FIRED="${soft# }"; return 0; fi
  if [ "$n" -ge 2 ]; then LANE=normal; REASON="$n soft flags (2-3, near full):$soft"; FIRED="${soft# }"; return 0; fi
  LANE=normal; REASON="bounded feature/fix (default)"; FIRED="${soft# }"; FIRED="${FIRED:-none}"; return 0
}

# Risk rank for the floor check (SPEC-053). Under-sizing (a lighter lane than the text
# implies) is the only dangerous direction; over-sizing is always safe ("when in doubt,
# heavier"). normal/bug/backfill share rank 2 (same ceremony weight); full is the headline
# floor. An unrecognized lane returns -1 so lane_check can flag it distinctly.
lane_rank() {
  case "$1" in
    tiny)                echo 1;;
    normal|bug|backfill) echo 2;;
    full)                echo 3;;
    *)                   echo -1;;
  esac
}

# Advisory floor check: compare the lane a human/LLM CHOSE against the deterministic
# suggestion for the same text. Warn (stderr) + log (completeness.log) ONLY when the
# chosen lane is lighter than the floor. Never blocks; always exits 0 ("Detect, don't
# dictate"). This is the guard the classify-then-route audit found missing: classify
# suggests, but nothing caught an under-sized choice.
lane_check() {
  local chosen desc suggested cr sr log_dir desc_trunc
  chosen="${1:-}"; shift 2>/dev/null || true
  desc="$*"
  [ -n "$chosen" ] || { echo "usage: lane-classify.sh check <chosen-lane> \"<description>\"" >&2; return 64; }

  cr="$(lane_rank "$chosen")"
  if [ "$cr" -lt 0 ]; then
    echo "LANE-UNKNOWN: '$chosen' is not a lane (tiny|normal|full|bug|backfill); not checked" >&2
    return 0
  fi

  classify_core "$desc"
  suggested="$LANE"
  sr="$(lane_rank "$suggested")"

  if [ "$cr" -lt "$sr" ]; then
    echo "LANE-DOWNGRADE: chosen=$chosen suggested=$suggested -- the task text matches a heavier lane; size up or say why" >&2
    desc_trunc="$(printf '%s' "$desc" | tr '\n' ' ' | cut -c1-100)"
    log_dir="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
    mkdir -p "$log_dir" 2>/dev/null || true
    printf '%s | LANE-CHECK | downgrade | chosen=%s suggested=%s | %s\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$chosen" "$suggested" "$desc_trunc" \
      >> "$log_dir/completeness.log" 2>/dev/null || true
  fi
  return 0
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify) classify_core "$@"; printf '%s\n' "$LANE";;
    explain)  classify_core "$@"; printf '%s\nreason: %s\nflags: %s\n' "$LANE" "$REASON" "${FIRED:-none}";;
    check)    lane_check "$@";;
    lanes)    printf 'tiny\nnormal\nfull\nbug\nbackfill\n';;
    flags)    printf '%s\n' "${_hard_name[@]}" "${_soft_name[@]}";;
    *) echo "usage: lane-classify.sh {classify \"<desc>\"|explain \"<desc>\"|check <chosen-lane> \"<desc>\"|lanes|flags}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
