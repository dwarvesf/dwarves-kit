#!/usr/bin/env bash
# lane-classify.sh -- deterministic task-type -> risk-lane classifier.
#
# Turns a one-line task description into one of the WORKFLOW.md risk lanes
# (tiny | normal | full | bug | backfill) so the intake path (/kit:assign) and the
# dispatch path (/kit:dispatch) can auto-choose the lane instead of relying on ad-hoc
# judgment. The rules are the WORKFLOW.md "Size the work first" lane triggers, encoded
# once. Pure bash + grep; no binary.
#
# This SUGGESTS a lane; it never blocks ("Detect, don't dictate"). A human or the LLM
# can override. The "when in doubt, take the heavier lane" rule is baked into the
# precedence order below.
#
# Precedence (first match wins):
#   1. backfill  -- explicit operating-layer doc work on an existing codebase
#                   (checked first so a "billing" keyword inside a doc task does not
#                    pull it into the full lane)
#   2. tiny      -- pure cosmetic edits, subject-independent (a typo about auth is
#                   still a typo)
#   3. full      -- touches a high-risk surface (auth, data model, migration, secrets,
#                   external provider/API contract, hooks, validation, payments)
#   4. bug       -- a defect / regression / crash / failing test (not a new feature)
#   5. normal    -- the default: one bounded feature or fix
#
# Usage:
#   lane-classify.sh classify "<task description>"   -> prints the lane, exit 0
#   lane-classify.sh lanes                            -> prints the 5 lane names

set -euo pipefail

lane_classify() {
  local desc lc
  desc="$*"
  lc="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  # 1. backfill: brownfield operating-layer documentation.
  if printf '%s' "$lc" | grep -qE 'backfill|operating[ -]layer|brownfield|document the existing|write (agents|claude)\.md'; then
    echo backfill; return 0
  fi

  # 2. tiny: pure cosmetic, regardless of subject matter.
  if printf '%s' "$lc" | grep -qE 'typo|whitespace|re-?word|copy[ -]?edit|comment|rename|formatting|one[ -]liner?|wording|doc(s)? fix|fix .*(typo|wording|comment)'; then
    echo tiny; return 0
  fi

  # 3. full: high-risk surfaces (WORKFLOW full-lane trigger list).
  if printf '%s' "$lc" | grep -qE 'auth[a-z]*|login|password|secret|token|security|migrat|schema|data[ -]model|data loss|delete[s]? .*data|external (api|provider)|api contract|payment|billing|crypto|encrypt|\bhook(s)?\b|validation|permission'; then
    echo full; return 0
  fi

  # 4. bug: a defect, not a new feature.
  if printf '%s' "$lc" | grep -qE '\bbug\b|regression|failing test|broken|crash|defect|hotfix|stack ?trace|exception|fix the|fix a |repro'; then
    echo bug; return 0
  fi

  # 5. default.
  echo normal
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify) lane_classify "$@";;
    lanes)    printf 'tiny\nnormal\nfull\nbug\nbackfill\n';;
    *) echo "usage: lane-classify.sh {classify \"<description>\"|lanes}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
