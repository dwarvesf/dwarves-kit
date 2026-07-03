#!/usr/bin/env bash
# significance-classify.sh -- deterministic understanding-gate classifier (ADR-0031, SPEC-122).
#
# Sibling to lib/lane-classify.sh (same shape: pure bash + grep, no binary, no LLM). Where
# lane-classify decides HOW MUCH RISK a task carries, this decides WHEN the understanding gate
# fires: it emits TWO signals per ADR-0031's Refinement --
#
#   significance          -- "did a lot change?" (full lane OR design-bearing OR a new public
#                             surface). Fires on big-but-boring refactors too.
#   understanding-worthiness -- "will NOT understanding this cost a later loop?" Triggers:
#                             introduces a primitive future work builds on; irreversible or
#                             costly-to-reverse (data model / API contract / security boundary);
#                             first-of-kind/novel; high blast radius if misunderstood; the human
#                             will have to explain/defend/decide on it. `docs/implementation-
#                             notes/<slug>.md` is read as a FEED: a non-empty impl-note is itself
#                             an unspecified-decision signal (ADR-0031 Refinement point 4).
#
# The verdict taps ONLY high x high (the anti-fatigue guard -- over-tap fatigues the human,
# under-tap lets debt return untracked, ADR-0031's load-bearing knob):
#
#            worthiness LOW              worthiness HIGH
#   sig LOW  not-significant             not-significant
#   sig HIGH wave (silent log)           tap  (the only ★)
#
# `record` writes the verdict as an ADDITIVE marker via `gate-ledger.sh debt` (the worker-side
# half of ADR-0032 section 3's debt-ledger split; the human-facing ★-tap nudge is a SEPARATE,
# LATER marker written by SG-04 -- this lib never asks the human anything).
#
# ONE tunable knob (documented, not magic): SIGNIFICANCE_WORTHINESS_MIN (default 1) -- the
# number of distinct worthiness triggers that must fire before worthiness is called HIGH. Raise
# it (e.g. 2) to demand corroborating signals and tap less; the double gate (significance AND
# worthiness both high) already does most of the anti-fatigue work, so the default stays at the
# most sensitive setting.
#
# Usage:
#   significance-classify.sh classify [--files "<paths>"] [--impl-notes "<path>"] "<desc>"
#     -> prints the verdict (tap|wave|not-significant), exit 0
#   significance-classify.sh explain  [--files ...] [--impl-notes ...] "<desc>"
#     -> verdict + both signals + fired triggers, exit 0
#   significance-classify.sh record <rid> [--files ...] [--impl-notes ...] "<desc>"
#     -> classifies, then writes the debt-ledger marker (gate-ledger.sh debt), prints the verdict
#   significance-classify.sh signals
#     -> the worthiness trigger names, one per line

set -euo pipefail

SC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANE_CLASSIFY="$SC_DIR/lane-classify.sh"
GATE_LEDGER="$SC_DIR/gate-ledger.sh"

# Significance triggers (any one -> high). "full lane" is checked separately (it calls out to
# lane-classify.sh, not a regex here) so the two classifiers never carry two copies of the same
# risk-flag list (drift guard, mirrors lane-classify's own single-source discipline).
_sig_name=(design-bearing new-public-surface)
_sig_re=(
  'new (component|module)|non-obvious control flow|schema (change|migration)|data[ -]model (change|shift)|external integration|irreversible (choice|decision)|2\+ (viable )?approaches|multiple approaches considered|2 or more (viable )?approaches'
  'new (public )?(api|cli|command|endpoint|interface)|expose[sd]? a new|new public (function|method|surface)'
)

# Understanding-worthiness triggers (ADR-0031 Refinement point 2). name <-> regex, index-aligned;
# the same parallel-array discipline as lane-classify.sh (fail loud if they drift out of sync).
_wor_name=(primitive irreversible novel blast-radius must-explain)
_wor_re=(
  'new primitive|introduces? a (primitive|concept|abstraction)|building block|future work (will )?build[s]? on|other (work|code|features?) (will )?build on|base (class|abstraction)|foundation(al)? (piece|component)'
  'irreversible|costly to reverse|hard to reverse|data model|schema change|api contract|breaking change|security boundary|access control boundary|auth(entication|orization)? boundary'
  'first[ -]of[ -](its[ -])?kind|novel (pattern|approach)|no precedent|never (done|built) before|greenfield'
  'blast radius|widely (used|shared)|every (caller|consumer|downstream)|core (path|module|surface)|critical path|shared (by|across) (multiple|many)'
  'must (explain|defend|justify)|will (need to |have to )?(explain|defend|justify)|design decision|architecture(al)? decision|human (must|will) (decide|approve)'
)

[ "${#_sig_name[@]}" -eq "${#_sig_re[@]}" ] && [ "${#_wor_name[@]}" -eq "${#_wor_re[@]}" ] \
  || { echo "significance-classify: flag name/regex arrays are misaligned (bug)" >&2; exit 70; }

# Tunable knob (documented in the header + the spec). Not a magic number: it is the count of
# distinct worthiness triggers required before worthiness is HIGH.
WORTHINESS_MIN="${SIGNIFICANCE_WORTHINESS_MIN:-1}"

FILES=""; IMPL_NOTES=""; REMAIN=()

# _extract_opts "$@" -- pull optional --files / --impl-notes out of the args (mirrors
# lane-classify.sh's _extract_files), leaving the description in REMAIN.
_extract_opts() {
  FILES=""; IMPL_NOTES=""; REMAIN=()
  local a skip=""
  for a in "$@"; do
    if [ -n "$skip" ]; then
      case "$skip" in files) FILES="$a";; impl-notes) IMPL_NOTES="$a";; esac
      skip=""; continue
    fi
    case "$a" in
      --files)        skip=files ;;
      --files=*)      FILES="${a#--files=}" ;;
      --impl-notes)   skip=impl-notes ;;
      --impl-notes=*) IMPL_NOTES="${a#--impl-notes=}" ;;
      *)              REMAIN+=("$a") ;;
    esac
  done
}

# _impl_notes_signal -- true (0) if IMPL_NOTES points at a non-empty impl-note file (has at
# least one "## " dated entry). Per ADR-0031 Refinement point 4: an impl-note entry IS an
# unspecified decision the agent made -- exactly a worthiness candidate, so its mere presence
# (not its content) is the signal. Missing/empty file -> no signal (2, not an error).
_impl_notes_signal() {
  [ -n "$IMPL_NOTES" ] || return 2
  [ -f "$IMPL_NOTES" ] || return 2
  grep -qE '^## ' "$IMPL_NOTES" 2>/dev/null && return 0
  return 2
}

SIGNIFICANCE=""; SIG_REASON=""; WORTHINESS=""; WOR_FIRED=""; VERDICT=""

classify_core() {
  local desc="$*" lc i
  lc="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  # 1. Significance: full lane (delegates to lane-classify.sh, so there is exactly one place
  #    that knows the lane-escalation rules) OR a design-bearing / new-public-surface phrase.
  SIGNIFICANCE=low; SIG_REASON="no significance trigger"
  local lane
  if [ -n "$FILES" ]; then
    lane="$(bash "$LANE_CLASSIFY" classify --files "$FILES" "$desc" 2>/dev/null || echo "")"
  else
    lane="$(bash "$LANE_CLASSIFY" classify "$desc" 2>/dev/null || echo "")"
  fi
  if [ "$lane" = full ]; then
    SIGNIFICANCE=high; SIG_REASON="full lane"
  else
    for i in "${!_sig_re[@]}"; do
      if printf '%s' "$lc" | grep -qE "${_sig_re[$i]}"; then
        SIGNIFICANCE=high; SIG_REASON="${_sig_name[$i]}"; break
      fi
    done
  fi

  # 2. Understanding-worthiness: count distinct triggers (text + the impl-notes feed).
  local fired="" n=0
  for i in "${!_wor_re[@]}"; do
    if printf '%s' "$lc" | grep -qE "${_wor_re[$i]}"; then
      fired="$fired ${_wor_name[$i]}"; n=$((n + 1))
    fi
  done
  if _impl_notes_signal; then
    fired="$fired impl-notes-feed"; n=$((n + 1))
  fi
  WOR_FIRED="${fired# }"; WOR_FIRED="${WOR_FIRED:-none}"
  if [ "$n" -ge "$WORTHINESS_MIN" ]; then WORTHINESS=high; else WORTHINESS=low; fi

  # 3. Verdict: the two-signal matrix (ADR-0031 Refinement point 2). Tap only high x high.
  if [ "$SIGNIFICANCE" != high ]; then
    VERDICT=not-significant
  elif [ "$WORTHINESS" = high ]; then
    VERDICT=tap
  else
    VERDICT=wave
  fi
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify)
      _extract_opts "$@"; classify_core ${REMAIN[@]+"${REMAIN[@]}"}
      printf '%s\n' "$VERDICT"
      ;;
    explain)
      _extract_opts "$@"; classify_core ${REMAIN[@]+"${REMAIN[@]}"}
      printf '%s\nsignificance: %s (%s)\nworthiness: %s (%s)\n' \
        "$VERDICT" "$SIGNIFICANCE" "$SIG_REASON" "$WORTHINESS" "$WOR_FIRED"
      ;;
    record)
      local rid="${1:-}"; shift || { echo "usage: significance-classify.sh record <rid> [--files ...] [--impl-notes ...] \"<desc>\"" >&2; exit 64; }
      _extract_opts "$@"; classify_core ${REMAIN[@]+"${REMAIN[@]}"}
      bash "$GATE_LEDGER" debt "$rid" \
        "significance=$SIGNIFICANCE" "worthiness=$WORTHINESS" "verdict=$VERDICT" \
        "reason=sig:${SIG_REASON} wor:${WOR_FIRED}"
      printf '%s\n' "$VERDICT"
      ;;
    signals) printf '%s\n' "${_wor_name[@]}" ;;
    *) echo "usage: significance-classify.sh {classify [--files ...] [--impl-notes ...] \"<desc>\"|explain ...|record <rid> ...|signals}" >&2; exit 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
