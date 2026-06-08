#!/usr/bin/env bash
# task-type-classify.sh -- deterministic task description -> work TYPE.
#
# The second axis of the verification gate (SPEC-044). lane-classify.sh answers
# "how risky" and proof-gate.sh answers "how rigorous" (the proof CLASS); this
# answers "what KIND of work", which decides the SHAPE of the proof of done and the
# skill that owns the methodology. The type -> {artifact, skill, default class}
# mapping is the declarative registry docs/verification/task-types.md.
#
# SUGGESTS a type; never blocks ("Detect, don't dictate"). A human overrides.
#
# Precedence (first match wins). eval/research win over doc because their
# deliverable IS a report (a doc) but the WORK is eval/research; doc (pure docs)
# wins over migration/data-tool because a doc about a tool is still a doc;
# migration wins over data-tool because a tool that deploys to production or touches
# live state warrants the stricter stateful proof regardless of artifact type (this
# mirrors proof-gate's stateful > behavioral rule; it errs strict, never permissive):
#   1. eval         -- benchmark / evaluate / compare tools -> a TEST-REPORT
#   2. research     -- investigate / survey / landscape      -> a cited report
#   3. doc          -- write docs / readme / changelog        -> doc-verifier match
#   4. migration    -- deploy / migrate / schema / rollout    -> dry-run + rollback
#   5. data-tool    -- a CLI / API client / scraper / puller  -> a recorded live run
#   6. spec-feature -- the default: implement a feature/fix   -> tests + acceptance
#
# Usage:
#   task-type-classify.sh classify "<task description>"  -> the type, exit 0
#   task-type-classify.sh types                           -> the 6 type names
set -euo pipefail

task_type_classify() {
  local desc lc
  desc="$*"
  lc="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  # 1. eval: measuring or comparing tools/options.
  if printf '%s' "$lc" | grep -qE 'benchmark|evaluat|\beval\b|compare .*(vs|versus|against)|which (tool|one|option)|is .* better|lab[ -]test|a/b test'; then
    echo eval; return 0
  fi

  # 2. research: investigation / survey / landscape (no measured comparison).
  if printf '%s' "$lc" | grep -qE 'research|investigat|survey|landscape|literature|state of the art|find out (how|whether|if)|cited report'; then
    echo research; return 0
  fi

  # 3. doc: documentation / readme / changelog / comments (a doc about anything is a doc).
  if printf '%s' "$lc" | grep -qE 'write (the )?(docs|documentation|readme|manual)|update (the )?(docs|documentation|readme|changelog|manual)|document the|\breadme\b|changelog|add (a )?comment|add comments|docstring|explainer|write[ -]?up'; then
    echo doc; return 0
  fi

  # 4. migration: deployment / data / persistent-state change.
  if printf '%s' "$lc" | grep -qE 'deploy|rollout|roll out|release to|ship to prod|production|migrat|schema|data[ -]model|database|backfill data|seed data|backup|restore'; then
    echo migration; return 0
  fi

  # 5. data-tool: a CLI / API client / scraper / data puller.
  if printf '%s' "$lc" | grep -qE '\bcli\b|command[ -]line|api client|api wrapper|wrap .* api|scraper|scrape|crawl|data pull|pull .* (data|from)|fetch .* (api|from)|integrate .* api|port .* (to a )?cli|connector'; then
    echo data-tool; return 0
  fi

  # 6. default: a feature / fix implemented against a spec.
  echo spec-feature
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify) task_type_classify "$@";;
    types)    printf 'eval\nresearch\ndoc\nmigration\ndata-tool\nspec-feature\n';;
    *) echo "usage: task-type-classify.sh {classify \"<description>\"|types}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
