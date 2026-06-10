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
