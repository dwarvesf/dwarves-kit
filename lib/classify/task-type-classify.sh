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
#   1. incident     -- alert / outage / triage / postmortem  -> INC record + verified recovery
#   2. learning     -- course / workbook / study material     -> workbook + scored self-check
#   3. planning     -- weekly/sprint priorities / re-rank     -> plan digest + enqueued rows
#   4. operate      -- recurring procedure run (payroll...)   -> append-only run ledger
#   5. eval         -- benchmark / evaluate / compare tools -> a TEST-REPORT
#   6. research     -- investigate / survey / landscape      -> a cited report
#   7. doc          -- write docs / readme / changelog        -> doc-verifier match
#   8. migration    -- deploy / migrate / schema / rollout    -> dry-run + rollback
#   9. reconcile    -- drift / cleanup / records-vs-reality   -> inventory + verdicts
#  10. data-tool    -- a CLI / API client / scraper / puller  -> a recorded live run
#  11. spec-feature -- the default: implement a feature/fix   -> tests + acceptance
#
# SPEC-060 recall tuning: the rules below carry anchors mined from REAL session phrasing
# (an 8-ask live probe found 7/8 falling to the spec-feature default). A 4b absorb guard
# sits above eval: absorb-into-kit work is implementation, not measurement.
#
# New-type precedence rationale (SPEC-057): incident first (alert language must never fall
# through to research/doc); learning/planning/operate are schedule/material-anchored so they
# cannot steal build phrases; reconcile sits AFTER migration (review F6: explicit migratory
# phrasing like "migrate stale records" wins) but its drift/cleanup anchors are estate-scoped
# so routine code cleanup falls through to spec-feature.
#
# Usage:
#   task-type-classify.sh classify "<task description>"  -> the type, exit 0
#   task-type-classify.sh types                           -> the 11 type names
set -euo pipefail

task_type_classify() {
  local desc lc
  desc="$*"
  lc="$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')"

  # 1. incident: reactive triage of a fired signal (SPEC-057).
  if printf '%s' "$lc" | grep -qE 'incident|\binc-[0-9]+|triage|(respond to|investigate|silence|ack(nowledge)?) (the )?.{0,20}alert|alert (fired|firing|triggered|storm)|(respond|triage|investigat|recover|mitigat)[a-z]* .{0,20}outage|outage (response|triage|recovery|report)|post-?mortem|\bsev-?(0|1|crit)\b|false positive|on-?call (response|triage|incident|page)'; then
    echo incident; return 0
  fi

  # 2. learning: study material -> workbook/self-check (SPEC-057).
  if printf '%s' "$lc" | grep -qE 'learn(ing)? (track|course|day|path)|process day[- ]?[0-9]|course (material|track|day|module|transcript)|(study|learning|practice|math|quant) workbook|workbook (for|on) |study (session|track|plan)|lesson (plan|module|series|[0-9])|flashcard|anki|self-?check'; then
    echo learning; return 0
  fi

  # 3. planning: schedule-anchored prioritization (SPEC-057). Tight anchors so
  # "plan the schema migration" still lands on migration.
  if printf '%s' "$lc" | grep -qE 'plan(ning)? (for )?(the )?(next |this )?(week|sprint|month|quarter)|weekly (plan|priorit|digest)|priorit(ize|ies|y) (the )?(backlog|queue|board|work)|re-?rank|groom (the )?backlog|mega-?goal|scaffold .{0,25}roadmap|(draft|write) (the )?roadmap'; then
    echo planning; return 0
  fi

  # 4. operate: a recurring, defined procedure run (SPEC-057).
  if printf '%s' "$lc" | grep -qE 'payroll|run (the )?monthly|monthly close|month-?end (close|run)|quarterly (close|run)|run the .*(procedure|playbook|runbook|radar|sweep)|recurring (run|task|job)|scheduled run|babysit|routine (run|check)|merge (the )?.{0,25}(stack|merge train|pr queue)|wrap.?up .{0,25}session|wrap.?up,? (and )?(commit|push|merge)|session (close|wrap)|lab.?log entry'; then
    echo operate; return 0
  fi

  # 4b. absorb guard (SPEC-060): absorbing external skill/command mechanics into the kit
  # is implementation work (spec-feature), NOT an eval; "evaluate X and absorb into the
  # kit" must not impose eval's metrics+seeds dialect. The evaluation prologue lives in
  # /kit:absorb (proposal-only) + PHILOSOPHY's "Skill routing" rule. Requires kit/skill/
  # command co-occurrence so "absorb the loss" / domain phrasings fall through untouched.
  if printf '%s' "$lc" | grep -qE 'absor(b|ption)' && printf '%s' "$lc" | grep -qE '\bkit\b|\bskill|\bcommand\b|operator estate'; then
    echo spec-feature; return 0
  fi

  # NOTE: the `run .* experiment` arm relies on operate (rule 4) being checked FIRST
  # to catch procedure-run phrasings; reorder with care (SPEC-075 review F3).
  # 5. eval: measuring or comparing tools/options.
  if printf '%s' "$lc" | grep -qE 'benchmark|evaluat|\beval\b|compare .*(vs|versus|against)|which (tool|one|option)|is .* better|lab[ -]test|a/b test|(spin up|run|do) .{0,12}(quick )?experiment|experiment to (test|see|check)|trial .{0,16}(library|tool|service|framework)|throwaway (code|prototype|script)'; then
    echo eval; return 0
  fi

  # 6. research: investigation / survey / landscape (no measured comparison).
  if printf '%s' "$lc" | grep -qE 'research|investigat|survey|landscape|literature|state of the art|find out (how|whether|if)|cited report|deep[ -]dive .{0,60}(snapshot|write[ -]up|note)|(snapshot|write up) (how|what|the way)'; then
    echo research; return 0
  fi

  # 6b. review (SPEC-079 / ID-074): standalone review of a CODE artifact. Acting on
  # feedback is build work (spec-feature); plan/paper review belongs to its subject.
  # Known precedence consequences (documented, accepted): incident (rule 1) and
  # research (rule 6) pre-empt , "review the incident triage report" is incident
  # work, and "review the research methodology in the diff" routes research.
  if printf '%s' "$lc" | grep -qE '(review|audit) .{0,24}(\bpr\b|diff|branch|changes|commit|codebase|\bcode\b)|(adversarial|multi-lens|code|security) review\b|review .{0,16}adversari' \
     && ! printf '%s' "$lc" | grep -qE 'review feedback|(address|respond to|act on|incorporate) .{0,20}review|\bself-review\b|review and (merge|push|ship|close)'; then
    echo review; return 0
  fi

  # 8. doc: documentation / readme / changelog / comments (a doc about anything is a doc).
  if printf '%s' "$lc" | grep -qE 'write (the )?(docs|documentation|readme|manual)|update (the )?(docs|documentation|readme|changelog|manual)|document the|\breadme\b|changelog|add (a )?comment|add comments|docstring|explainer|write[ -]?up'; then
    echo doc; return 0
  fi

  # 9. migration: deployment / data / persistent-state change.
  if printf '%s' "$lc" | grep -qE 'deploy|rollout|roll out|release to|ship to prod|production|migrat|schema|data[ -]model|database|backfill data|seed data|backup|restore|launchd|\bdaemon\b|provision'; then
    echo migration; return 0
  fi

  # 9b. reconcile (after migration, so explicit migratory phrasing wins; SPEC-057 review F6): records-vs-reality drift, cleanup, hygiene sweeps (SPEC-057).
  if printf '%s' "$lc" | grep -qE 'reconcil|(config|state|schema|status|record|convention) drift|drift (audit|check|sweep|report)|clean ?up .{0,30}(estate|backlog|branch|reference|record|status|stash|worktree)|stale (branch|status|row|record|reference)|parity (check|audit)|hygiene|deadwood|prune .{0,20}(stale|branch|deadwood)|audit .* against|sweep (the )?(estate|repo|backlog|branches)|untangle .{0,30}(branch|pr|backlog|estate|stack)|stranded .{0,25}(branch|pr|spec)|orphan(ed)? .{0,20}(branch|pr|worktree)'; then
    echo reconcile; return 0
  fi

  # 10. data-tool: a CLI / API client / scraper / data puller.
  if printf '%s' "$lc" | grep -qE '(build|write|create|wrap|ship) .{0,24}\bcli\b|command[ -]line (tool|client|utility|interface)|api client|api wrapper|wrap .* api|scraper|scrape|crawl|data pull|pull .* (data|from)|fetch .* (api|from)|integrate .* api|port .* (to a )?cli|connector'; then
    echo data-tool; return 0
  fi

  # 11. default: a feature / fix implemented against a spec.
  echo spec-feature
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    classify) task_type_classify "$@";;
    types)    printf 'incident\nlearning\nplanning\noperate\neval\nresearch\nreview\ndoc\nmigration\nreconcile\ndata-tool\nspec-feature\n';;
    *) echo "usage: task-type-classify.sh {classify \"<description>\"|types}" >&2; return 64;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
