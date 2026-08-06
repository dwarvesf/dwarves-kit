#!/usr/bin/env bash
# redteam-gate.sh -- the mechanical half of the done-condition ladder's rung 4 (an in-harness
# adversarial skeptic on the frozen diff, verbatim `VERDICT: SECURE`, fail-closed, cap 3 rounds;
# canonical block: dotfiles goal-craft/SKILL.md, plan-for-goal/SKILL.md,
# plan-for-mega-goal/references/subgoal-template.md).
#
# THE GAP THIS CLOSES (ops-toolkit research/2026-07-18-rung4-cost-checkpoint.md): real rung-4
# redteams HAVE run (board-tool 7-attempt, orchestrate-queue 3-round, board-writeback 4-attempt,
# all VERDICT: SECURE), but none ever emitted a `redteam` kit_gates row, so the rung-4 cost
# checkpoint (ID-372: tighten the trigger if rung 4 averages >15% of mega cost) can never be
# evaluated -- every existing primitive (gate-ledger.sh record/tokens/outcome) was already
# capable of recording a round, but nothing called them, because a round-in-progress needs THREE
# separate calls kept in sync (a GATE row, a TOKENS row, an OUTCOME bracket) and the redteam
# procedure never made them. This script is that ONE call per round.
#
# Design: one `round` call writes all three lines in sequence (argument-validation failures,
# the case every test here covers, write NOTHING -- see `cost=` below; a crash or kill BETWEEN
# the three subprocess calls, after validation passes, is a narrower residual window this script
# does not protect against). The FIFO pairing `lib/stats` `read_kit_gates` already uses for
# GATE<->OUTCOME (SPEC-129 DEC-002) extends unchanged to GATE<->TOKENS(phase=) here (kit_gates
# gains a `cost` column, additive, NULL for every pre-existing gate). `read_kit_gates` itself
# tolerates a phase-scoped TOKENS line with no cost= (or a malformed one): it lands `cost=NULL`
# in that queue slot, FIFO position preserved, no desync -- so the FIFO pairing is not actually
# why `cost=` is REQUIRED here. The real reason: this tool exists solely to make rung-4 cost
# measurable (ID-372), so a round allowed to record itself WITHOUT a cost would reproduce the
# checkpoint's original failure in a new shape (rounds ledgered, average still uncomputable, or
# worse, silently understated by treating unmeasured rounds as free). Fail closed -- reject,
# write nothing -- so a missing cost is loud (rc 64) at the call site instead of a quiet gap in
# the average months later.
#
# Verbs:
#   redteam-gate.sh start <rid>
#       -> opens the timing bracket for one round (gate-ledger.sh outcome <rid> redteam start).
#          Call once per round, immediately before the adversarial pass begins.
#   redteam-gate.sh round <rid> <secure|findings|capped> cost=<dollars> [round=N]
#                    [in=N out=N cache_read=N cache_create=N] [reason=...]
#       -> closes the round: an OUTCOME end bracket (caught derived from verdict), a
#          TOKENS(phase=redteam) row carrying this round's cost, and the `redteam` GATE row
#          itself. verdict: secure (clean pass this round, caught=false), findings (this round
#          found issues, another round follows, caught=true), capped (the 3-round cap was hit
#          without ever reaching SECURE -- the fail-closed stop, caught=true).
#          NOTE: `in=`/`out=`/`cache_read=`/`cache_create=` are optional and, unlike `cost=`,
#          are NOT honest-NULL when omitted -- gate-ledger.sh's own `tokens()` zero-defaults
#          them, so a round recorded without token counts reads as `in=0 out=0` (a real value,
#          not "unknown"). Only `cost` gets the required+NULL-on-failure treatment this file
#          is built around; a future per-round token-count average would need the same
#          treatment token counts don't have yet.
#
# SCOPE: the redteam PROCEDURE itself (the SKILL.md blocks named above, cap-3 loop,
# VERDICT: SECURE judgment) lives in a sibling dotfiles repo, out of scope here. This script
# only gives that procedure a call worth making; it does not call itself. N stays 0 in
# `mega-durations`/`kit_gates` until the dotfiles-side procedure is edited to call `start`/
# `round` at its own round boundaries -- that wiring is a separate, tracked follow-up, not
# implied by this PR landing.
#
# Usage the calling procedure is expected to adopt (not yet wired anywhere as of this PR):
#   redteam-gate.sh start "$RID"
#   ... run the adversarial pass ...
#   redteam-gate.sh round "$RID" findings cost=0.42 round=1 reason="2 findings, fixed"
#   redteam-gate.sh start "$RID"
#   ... run round 2 ...
#   redteam-gate.sh round "$RID" secure cost=0.31 round=2

set -uo pipefail

RG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE_LEDGER="$RG_DIR/gate-ledger.sh"

usage() { sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# _oneline <text> -- collapse newlines the same way gate-ledger.sh's own oneline() does, so a
# multi-line reason can never split into a second physical ledger line before it ever reaches
# gate-ledger.sh (defense-in-depth; gate-ledger.sh's own record() re-applies this too).
_oneline() { printf '%s' "${*:-}" | tr '\n\r' '  '; }

cmd_start() {
  local rid="${1:-}"
  [ -n "$rid" ] || { echo "usage: redteam-gate.sh start <rid>" >&2; return 64; }
  bash "$GATE_LEDGER" outcome "$rid" redteam start
}

cmd_round() {
  local rid="${1:-}" verdict="${2:-}"
  shift 2 2>/dev/null || {
    echo "usage: redteam-gate.sh round <rid> <secure|findings|capped> cost=<dollars> [round=N] [in=N out=N cache_read=N cache_create=N] [reason=...]" >&2
    return 64
  }
  [ -n "$rid" ] || { echo "redteam-gate.sh round requires a rid" >&2; return 64; }
  case "$verdict" in
    secure|findings|capped) ;;
    *) echo "redteam-gate.sh round: verdict must be secure|findings|capped (got '${verdict:-<empty>}')" >&2; return 64 ;;
  esac

  local cost="" round_n="" intok="" outtok="" cread="" ccreate="" reason_parts=() kv k v
  for kv in "$@"; do
    k="${kv%%=*}"; v="${kv#*=}"
    case "$k" in
      cost)          cost="$v" ;;   # kept raw here; strictly validated below (this is a new
                                     # tool with no legacy callers, unlike gate-ledger.sh's own
                                     # lax `tr -cd '0-9.'` tokens() sanitizer, so a shape like
                                     # "1.2.3" or "abc" is rejected here instead of silently
                                     # landing malformed-but-accepted and NULL downstream)
      round)         round_n="$(printf '%s' "$v" | tr -cd '0-9')" ;;
      in)            intok="$v" ;;
      out)           outtok="$v" ;;
      cache_read)    cread="$v" ;;
      cache_create)  ccreate="$v" ;;
      reason)        reason_parts+=("$v") ;;
      *)             reason_parts+=("$kv") ;;   # unrecognized k=v (or bare text) folds into reason, never dropped silently
    esac
  done

  # cost is REQUIRED (see file header for the full rationale): this tool exists to make rung-4
  # cost measurable, so a round allowed to record itself without a cost would just relocate the
  # checkpoint's original gap rather than close it. Fail closed -- reject the call, write
  # NOTHING (no GATE row, no OUTCOME end, no TOKENS row) -- so the gap is loud (rc 64) at the
  # call site, not a silent hole in the average discovered later. One regex covers BOTH
  # "missing" and "malformed" (it requires >=1 digit, so an empty/unset $cost fails it too) --
  # no separate presence check needed.
  if ! [[ "$cost" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "redteam-gate.sh round: cost='$cost' is not a plain decimal (digits, optionally one '.', e.g. 0.42)" >&2
    return 64
  fi

  # caught derivation (mirrors gate-ledger.sh outcome()'s own convention: non-pass -> true,
  # clean pass -> false): a round that found issues, or the fail-closed cap, both COUNT as the
  # gate catching something; only a clean secure verdict is caught=false.
  local caught=false
  [ "$verdict" = secure ] || caught=true

  # 1) close the timing bracket this round's `start` opened.
  bash "$GATE_LEDGER" outcome "$rid" redteam end "caught=$caught" || return 1

  # 2) the round's cost, phase-scoped so lib/stats' read_kit_gates FIFO-pairs it onto this
  #    round's GATE row (the same convention SPEC-129 already uses for OUTCOME brackets).
  local tok_args=(cost="$cost" phase=redteam)
  [ -n "$intok" ]    && tok_args+=("in=$intok")
  [ -n "$outtok" ]   && tok_args+=("out=$outtok")
  [ -n "$cread" ]    && tok_args+=("cache_read=$cread")
  [ -n "$ccreate" ]  && tok_args+=("cache_create=$ccreate")
  bash "$GATE_LEDGER" tokens "$rid" "${tok_args[@]}" || return 1

  # 3) the GATE row itself -- always `ran` (the round DID execute; pass/fail lives in the
  #    reason text, matching the kit's existing convention of encoding a verdict in free text
  #    rather than overloading record()'s ran|skipped state, see e.g. lib/gate/mutation-smoke.sh).
  local reason
  reason="round=${round_n:-?} verdict=$verdict"
  if [ "${#reason_parts[@]}" -gt 0 ]; then
    reason="$reason $(_oneline "${reason_parts[*]}")"
  fi
  bash "$GATE_LEDGER" record "$rid" redteam ran "$reason"
}

main() {
  local sub="${1:-}"; shift 2>/dev/null || true
  case "$sub" in
    start) cmd_start "$@" ;;
    round) cmd_round "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "redteam-gate.sh: unknown subcommand '$sub'" >&2; usage >&2; exit 2 ;;
  esac
}

main "$@"
