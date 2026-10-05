#!/usr/bin/env bash
# wrap-flick.sh -- `wrap flick-7b`: the mechanical half of step 7b's shadow second opinion.
# Sourced by wrap.sh; defines cmd_flick_7b only.
#
# Step 7b used to say, in one prose paragraph, "pipe the pairs to bin/flick once and report a
# STATE row". Twenty-odd real wraps in the first five days read that paragraph and none ran it,
# so the shadow log stayed at its smoke rows. Prose that a session can skip without a trace is
# the failure; this verb turns the call and the report row into one command the step runs.
#
# stdin: one pair per line, `<candidate-slug> <hit-name> <existing-verdict>` (enhance, new, or none).
#        No lines means the session produced no pair; flick is not called.
# stdout: exactly one line, the text of the report's STATE row:
#           flick wrap-7b: <answered> answered, <denied> denied, <error> error (<backend>[, <reason>])
#           flick wrap-7b: no pairs (<backend>)      the point is on and the session had no pair
#           flick wrap-7b: off                       decide.points lacks wrap-7b; add no row
# Exit 0 on every path: flick fails open, and so does this.
#
# WRAP_FLICK_BIN overrides the flick entrypoint (a test seam). The default is the kit's own
# bin/flick, derived from this file's path, never the cwd.

cmd_flick_7b() {
  local points flick_bin backend pairs n=0 cand hit existing req out answered denied errors reason

  points="$(kit_config_get_root decide.points "" 2>/dev/null || true)"
  case " $points " in
    *" wrap-7b "*) : ;;
    *) echo "flick wrap-7b: off"; return 0 ;;
  esac

  command -v jq >/dev/null 2>&1 || { echo "flick wrap-7b: error (jq missing)"; return 0; }

  backend="$(kit_config_get_root decide.backend none 2>/dev/null || true)"
  [ -n "$backend" ] || backend="none"

  pairs="[]"
  while IFS=' ' read -r cand hit existing; do
    [ -n "$cand" ] || continue
    n=$((n + 1))
    pairs="$(printf '%s' "$pairs" | jq -c --arg id "p$n" --arg c "$cand" --arg h "$hit" --arg e "$existing" \
      '. + [{id:$id,candidate:$c,hit:$h,existing:$e}]')" || { echo "flick wrap-7b: error (bad pair line)"; return 0; }
  done

  if [ "$n" -eq 0 ]; then
    echo "flick wrap-7b: no pairs ($backend)"
    return 0
  fi

  req="$(jq -nc --argjson q "$pairs" '{point:"wrap-7b",questions:$q}')"
  flick_bin="${WRAP_FLICK_BIN:-$LIB_ROOT/../bin/flick}"
  out="$(printf '%s' "$req" | "$flick_bin" 2>/dev/null)" || out=""

  if ! printf '%s' "$out" | jq -e '.counts' >/dev/null 2>&1; then
    echo "flick wrap-7b: error ($backend, no result from flick)"
    return 0
  fi

  answered="$(printf '%s' "$out" | jq -r '.counts.answered // 0')"
  denied="$(printf '%s' "$out" | jq -r '.counts.denied // 0')"
  errors="$(printf '%s' "$out" | jq -r '.counts.error // 0')"
  backend="$(printf '%s' "$out" | jq -r '.backend // ""')"
  [ -n "$backend" ] || backend="none"
  reason="$(printf '%s' "$out" | jq -r '.error // ""')"
  echo "flick wrap-7b: $answered answered, $denied denied, $errors error ($backend${reason:+, $reason})"
  return 0
}
