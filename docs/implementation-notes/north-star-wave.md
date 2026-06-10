# Implementation notes: kit-north-star wave (sub-goals 02-05)

Decisions made during the 2026-06-10 mega-goal run that the specs did not pin down.
Roadmap: ops-toolkit `_meta/megagoals/kit-north-star/`. Specs: SPEC-054/055/056 + ID-047.

## 2026-06-10 SPEC-054: loop column lives in WORKFLOW, not the registry
- Context: the sub-goal sketch put both `loop` and `agent` columns in task-types.md.
- Decision: WORKFLOW.md owns the loops (it already owns lane paths); the registry owns the
  executor (`agent` column). One source per fact.
- Why: a loop column in the registry would duplicate WORKFLOW's cycle territory and drift.
- Impact: the meta pin checks WORKFLOW for loop rows and the registry for agent entries.

## 2026-06-10 SPEC-054: agent column appended as column 6
- Context: proof-gate.sh reads registry columns 3/4/5 BY INDEX.
- Decision: append after `default class`; verified `proof-gate.sh contract` output
  byte-identical before/after. Also fixed the data-tool artifact example that still taught
  the generator-clobbers-canonical anti-pattern (#30's rule).

## 2026-06-10 SPEC-055: reuse SPEC-005 status vocabulary, add only `claimed`
- Context: the sub-goal sketch invented queued/claimed/in-progress/in-review/done.
- Decision: the BACKLOG already had queued/speccing/validated/executing/shipped (+parked/
  dropped); added only `claimed`. in-progress = speccing/validated/executing; done = shipped.
- Why: two vocabularies for one file is the drift machine the one-source rule forbids.

## 2026-06-10 SPEC-055: the flip preserves annotation prose
- Context: status cells carry long operator annotations ("queued [re-eval 2026-05-23 ...]").
- Decision: `backlog.sh` rewrites only the leading keyword of the cell; optional note
  prepends. Tested (fixture "note kept" assertion).
- Why: nuking operator prose on a mechanical flip would destroy the queue's memory.

## 2026-06-10 ID-047 dogfood: priority = file order, dogfood row entered at the head
- Context: `next` picks the first queued row; ID-033/036 sat above.
- Decision: inserted ID-047 at the queue head (the active initiative outranks two stale
  re-eval items). No priority field added (YAGNI).

## 2026-06-10 ID-047: lifecycle skipped speccing/validated
- Context: research tasks produce a report, not a spec; the vocabulary is code-cycle-flavored.
- Decision: claimed -> shipped directly (states are checkpoints, not mandatory stops).
  A future wave may want per-type state subsets; observation only, not built.

## 2026-06-10 ship-gate cross-repo misfire (found by the dogfood)
- Context: the PreToolUse ship-gate evaluates the SESSION cwd, not the command's cd prefix;
  an ops-toolkit-session push to dwarves-kit ran the gate against ops-toolkit state and
  misresolved an unrelated slug. It also engages by pattern-matching the command STRING, so
  push-like phrases inside heredoc prose re-trigger it.
- Decision: audited proof-ledger override (the branch carries its own gate-green proof);
  bug + suggested fix filed in the mega-goal FEEDBACK.md. Candidate for a follow-up kit fix.

## 2026-06-10 SPEC-057: taxonomy expansion decisions
- Context: LAB_LOG evidence sweep (Explore agent over all entries + skills) found 8 misfit
  kinds; only 5 earned rows.
- Decision: folds > rows where the loop shape already exists (deployment=migration shape;
  agent-org config=spec-feature lanes; discovery splits research/reconcile by intent).
  Planning keywords are schedule-anchored so "plan the schema migration rollout" stays
  migration (pinned as the anchor-edge test).
- Tradeoff: `operate` vs `reconcile` keyword overlap ("recon run" finance vs "reconcile X
  against Y"); resolved by anchoring operate on procedure words (payroll/monthly/runbook)
  and reconcile on drift words.
- Note: proof-gate contract prints class from the DESCRIPTION (behavioral for "triage the
  alert") while the registry row carries the stateful DEFAULT; the registry doc already says
  the column is a default the gate may override. Left as designed.

## 2026-06-10 SPEC-057 SDD-audit pass (maintainer: "apply SDD back on PR 36")
- Context: post-ship audit found the review gate had never run, the lane said normal while the
  spec declared full, and a stale "six work types" line sat in PHILOSOPHY.
- Decisions: (a) the lane mismatch was itself a classifier bug, the kit-machinery hard flag
  enumerated lib files by name and missed task-type-classify/backlog/goal-registry/dispatch-gate;
  fixed + pinned, and the floor-check now fires LANE-DOWNGRADE on this very work. (b) Dispatched
  a real adversarial kit:reviewer on the diff: FIX-FIRST 4/10, 3 CRITICAL regex over-matches
  proven by live probes. All fixed; reconcile moved after migration; 12 negative pins added so
  the exact false positives are RED-guards. (c) proof-gate stateful set gains incident signals
  (the registry default and the gate now agree for incident phrasing). (d) Full-lane gates
  recorded honestly incl. two skipped-with-reason (design-critique, reflect).
- Lesson: happy-path truth tables pass CI while broad regexes rot classification; the review's
  live adversarial probing is what caught it. Negative pins are now part of the classifier's
  definition of done.

## 2026-06-10 operating-layer sync (maintainer follow-up on the SDD audit)
- Context: AGENTS.md (the contract /kit:adopt ships into consumer repos) had ZERO mentions of
  the board, type routing, or done-first; WORKFLOW lacked a "where work comes from" section.
- Decision: Task-loop gains step 0 (take work from the board) and a rewritten step 1
  (type-first, then lane, phase-0 done scenario); "Done means" anchors against the phase-0
  Done=; WORKFLOW gains the board section. Pinned (operating-layer parity meta pin).
- Why it mattered: adopted consumer repos would have received the OLD code-only contract while
  the kit itself routed by type, drift at the exact file whose job is preventing drift.
