#!/usr/bin/env bash
# proof-gate.sh -- deterministic task -> proof-of-done requirement classifier.
#
# Decides how strong a "proof of done" a task warrants, so the verify flow asks for the
# right thing instead of either skipping verification or imposing a ritual on a typo.
# Three proof classes:
#
#   stateful    -- deployment, migration, or anything touching data / persistent state.
#                  Proof = exercise the REAL flow on a copy or dry-run, record it, and
#                  note rollback / reversibility. Never "done" without a recorded run +
#                  a rollback path.
#   behavioral  -- implementation that changes behavior (a feature, a fix to logic).
#                  Proof = run the REAL primary flow end-to-end, record it, and include a
#                  negative control (revert -> it breaks -> restore).
#   inert       -- docs, comments, cosmetic, pure text. No run can meaningfully fail.
#                  Proof = an explicit exempt marker: [PROOF OF DONE: exempt -- <reason>].
#
# Built ON TOP of lane-classify.sh (single-sources the WORKFLOW lane keyword rules):
# tiny / backfill lanes -> inert. A stateful keyword pass runs before the behavioral
# default. SUGGESTS, never blocks ("Detect, don't dictate"); a human can override.
#
# Precedence (first match wins), mirroring lane-classify's cosmetic-first rule:
#   1. inert     -- the lane classifier calls it tiny or backfill (a typo in a migration
#                   file is still a typo; cosmetic wins over subject matter)
#   2. stateful  -- deploy / migration / data / persistent-state keywords
#   3. behavioral-- the default for anything that changes behavior
#
# Usage:
#   proof-gate.sh class "<task description>"        -> stateful | behavioral | inert
#   proof-gate.sh requirement "<task description>"  -> the one-line proof requirement
#   proof-gate.sh classes                            -> the three class names

set -euo pipefail

PROOF_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

proof_class() {
  local desc lc lane
  desc="$*"
  lc="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  # 1. inert: defer to the lane classifier's cosmetic/doc detection.
  lane="$(bash "$PROOF_GATE_DIR/lane-classify.sh" classify "$desc" 2>/dev/null || echo normal)"
  if [ "$lane" = "tiny" ] || [ "$lane" = "backfill" ]; then
    echo inert; return 0
  fi

  # 2. stateful: deployment, migration, or data / persistent-state surfaces.
  if printf '%s' "$lc" | grep -qE 'deploy|rollout|release to|ship to prod|production|migrat|schema|data[ -]model|database|\bdb\b|backfill data|seed|backup|restore|persistent|stateful|drop[s]? .*(table|column)|alter table|data loss|delete[s]? .*data'; then
    echo stateful; return 0
  fi

  # 3. behavioral: the default -- it changes behavior.
  echo behavioral
}

proof_requirement() {
  case "$(proof_class "$@")" in
    stateful)
      echo "stateful: exercise the REAL flow on a copy or dry-run, record the run (command + output + verdict) in docs/verification/<spec-slug>.md, and note rollback/reversibility. No 'done' without a recorded run AND a rollback path." ;;
    behavioral)
      echo "behavioral: run the REAL primary flow end-to-end (not a proxy test), record the run in docs/verification/<spec-slug>.md, and include a negative control (revert -> RED -> restore)." ;;
    inert)
      echo "inert: exempt. Record [PROOF OF DONE: exempt -- <reason>] in the log or the task line. No run required." ;;
  esac
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    class)       proof_class "$@";;
    requirement) proof_requirement "$@";;
    classes)     printf 'stateful\nbehavioral\ninert\n';;
    *) echo "usage: proof-gate.sh {class \"<desc>\"|requirement \"<desc>\"|classes}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
