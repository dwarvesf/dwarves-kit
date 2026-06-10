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

# pwd -P (physical): when invoked through a symlinked install dir (~/.claude/dwarves-kit/lib),
# resolve to the real repo so ../docs/verification/task-types.md still loads (SPEC-045).
PROOF_GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

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
  if printf '%s' "$lc" | grep -qE 'deploy|rollout|release to|ship to prod|production|migrat|schema|data[ -]model|database|\bdb\b|backfill data|seed|backup|restore|persistent|stateful|drop[s]? .*(table|column)|alter table|data loss|delete[s]? .*data|\bincident\b|\binc-[0-9]+|triage'; then
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

# SPEC-044: compose the proof CLASS (rigor) with the task TYPE (artifact shape +
# owning skill). The type comes from task-type-classify.sh; the artifact + skill come
# from the registry docs/verification/task-types.md. Class still wins on rigor.
TASK_TYPE_REGISTRY="$PROOF_GATE_DIR/../docs/verification/task-types.md"

_registry_field() {
  # $1 = task type, $2 = column index (3=artifact, 4=skill, 5=default class)
  awk -F'|' -v t="$1" -v c="$2" '
    /^\|/ {
      f2=$2; gsub(/^[ \t]+|[ \t]+$/, "", f2)
      if (f2 == "task-type" || f2 ~ /^-+$/) next   # skip the header + separator rows
      if (f2 == t) { v=$c; gsub(/^[ \t]+|[ \t]+$/, "", v); print v; exit }
    }' "$TASK_TYPE_REGISTRY" 2>/dev/null
}

proof_contract() {
  local desc class type artifact skill
  desc="$*"
  [ -n "$desc" ] || { echo "usage: proof-gate.sh contract \"<task description>\"" >&2; return 64; }
  class="$(proof_class "$desc")"
  type="$(bash "$PROOF_GATE_DIR/task-type-classify.sh" classify "$desc" 2>/dev/null || echo spec-feature)"
  artifact="$(_registry_field "$type" 3)"
  skill="$(_registry_field "$type" 4)"
  [ -n "$artifact" ] || artifact="(no registry row for type '$type'; default: run the real primary flow + a negative control)"
  [ -n "$skill" ] || skill="(none)"
  echo "type=$type class=$class"
  echo "proof: $artifact"
  echo "owner: $skill"
  echo "rigor: $(proof_requirement "$desc")"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    class)       proof_class "$@";;
    requirement) proof_requirement "$@";;
    contract)    proof_contract "$@";;
    classes)     printf 'stateful\nbehavioral\ninert\n';;
    *) echo "usage: proof-gate.sh {class \"<desc>\"|requirement \"<desc>\"|contract \"<desc>\"|classes}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
