#!/usr/bin/env bash
# surface.sh: build the one-line self-improvement-loop status surfaced at SessionStart.
# "N staged memory (cc-harvest) + M skill drafts + $X loop spend (7d)". Read-only; never writes.
HERE_SURFACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE_SURFACE/common.sh"

# cc-harvest's staging buffer (queued rows in the learned-ledger). Overridable for tests.
CC_SI_MEMORY_LEDGER="$(_expand "${CC_SI_MEMORY_LEDGER:-$HOME/workspace/tieubao/ops-toolkit/_meta/learned-ledger.md}")"

surface_counts() {  # echo "MEM DRAFTS SPEND" (space-separated)
  local mem=0 drafts=0 spend=0
  if [ -f "$CC_SI_MEMORY_LEDGER" ]; then
    mem="$(grep -cE '\|[[:space:]]*queued[[:space:]]*\|?[[:space:]]*$' "$CC_SI_MEMORY_LEDGER" 2>/dev/null || echo 0)"
  fi
  if [ -d "$CC_SI_PROPOSALS_DIR" ]; then
    drafts="$(find "$CC_SI_PROPOSALS_DIR" -mindepth 2 -maxdepth 2 -name SKILL.md 2>/dev/null \
              | grep -vE '/_(rejected|replaced|archive)/' | wc -l | tr -d ' ')"
  fi
  if [ -f "$CC_SI_LEDGER" ]; then
    local cut; cut="$(date -v-7d '+%Y-%m-%d' 2>/dev/null || date -d '7 days ago' '+%Y-%m-%d' 2>/dev/null || echo '0000-00-00')"
    spend="$(jq -rs --arg c "$cut" '[ .[] | select((.ts // "")>=$c) | .total_cost_usd // 0 ] | add // 0' "$CC_SI_LEDGER" 2>/dev/null || echo 0)"
  fi
  printf '%s %s %s' "${mem:-0}" "${drafts:-0}" "${spend:-0}"
}

surface_line() {
  local c; c="$(surface_counts)"; set -- $c
  printf 'cc-self-improve loop: %s staged memory (cc-harvest) · %s skill drafts · $%s spend (7d). /learned to flush · /skill-review to promote.' \
    "$1" "$2" "$3"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then surface_line; echo; fi
