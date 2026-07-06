#!/usr/bin/env bash
# conform.sh -- classify one kit ledger-event line against the Tier A schema
# (tools/ledger-observatory/docs/ledger-event-schema.md). Grep/parse only, no engine.
#
# Usage:
#   conform.sh check "<line>"   -> prints "PASS <verb>" or "FAIL <reason>", exit 0/1
#   printf '%s' "<line>" | conform.sh check   -> same, reading stdin
set -euo pipefail

# The 6-verb enum, exactly as gate-ledger.sh emits it.
VERBS='START|START-AMEND|GATE|ACTION|TOKENS|DEBT'
TS_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

classify() {
  local line="$1"
  # Split on the FIRST two ' | ' delimiters only (edge case 1: GATE's payload has
  # further pipes). awk with a bounded split, not IFS='|' (which would over-split).
  local ts verb payload
  ts="$(printf '%s' "$line" | awk -F' \\| ' '{print $1}')"
  verb="$(printf '%s' "$line" | awk -F' \\| ' '{print $2}')"
  # Strip "<ts> | <verb> | " via sed (not an awk field-rebuild, which would use OFS and
  # silently swallow any further ' | ' delimiters still inside the payload -- GATE's
  # payload has exactly that shape).
  payload="$(printf '%s' "$line" | sed -E 's/^[^|]*\|[^|]*\| //')"

  if ! printf '%s' "$ts" | grep -qE "$TS_RE"; then
    echo "FAIL not an ISO8601 UTC timestamp: '${ts:-<empty>}'"
    return 1
  fi
  if ! printf '%s' "$verb" | grep -qE "^(${VERBS})\$"; then
    echo "FAIL unknown verb: '${verb:-<empty>}' (want one of ${VERBS})"
    return 1
  fi
  if [ -z "$payload" ]; then
    echo "FAIL empty payload for verb '$verb'"
    return 1
  fi

  case "$verb" in
    START|START-AMEND)
      for req in lane= classified= type=; do
        printf '%s' "$payload" | grep -qF -- "$req" || { echo "FAIL $verb payload missing required token '$req'"; return 1; }
      done
      ;;
    TOKENS)
      for req in in= out= cache_read= cache_create=; do
        printf '%s' "$payload" | grep -qF -- "$req" || { echo "FAIL TOKENS payload missing required token '$req'"; return 1; }
      done
      ;;
    DEBT)
      for req in significance= worthiness= verdict=; do
        printf '%s' "$payload" | grep -qF -- "$req" || { echo "FAIL DEBT payload missing required token '$req'"; return 1; }
      done
      ;;
    GATE)
      # payload itself is "<phase> | <ran|skipped|override> | <reason>"
      local phase state
      phase="$(printf '%s' "$payload" | awk -F' \\| ' '{print $1}')"
      state="$(printf '%s' "$payload" | awk -F' \\| ' '{print $2}')"
      [ -n "$phase" ] || { echo "FAIL GATE payload missing phase field"; return 1; }
      printf '%s' "$state" | grep -qE '^(ran|skipped|override)$' \
        || { echo "FAIL GATE payload's state field is not ran|skipped|override: '${state:-<empty>}'"; return 1; }
      ;;
    ACTION)
      : # freeform text; non-empty already checked above
      ;;
  esac

  echo "PASS $verb"
  return 0
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    check)
      local line="${1:-}"
      [ -n "$line" ] || line="$(cat)"
      classify "$line"
      ;;
    *)
      echo "usage: conform.sh check \"<line>\" | conform.sh check < line-on-stdin" >&2
      exit 64
      ;;
  esac
}

main "$@"
