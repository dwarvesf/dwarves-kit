# Retro: kit-emit-sweep (SPEC-139, kit-run-integrity sub-goal 05)

Date: 2026-07-04
Sprint: single-session sub-goal, dispatched as ID-256's fifth of six sub-goals

## Metrics
- Tasks planned: 3 (wire 9 dark commands, exemption table, no-orphan sweep test), completed: 3, deferred: 0
- Commits: 1 (planned, at ship)
- Files changed: 13 (9 commands, WORKFLOW.md, CI workflow, spec, new test file)
- Time span: one continuous session, spec through ship

## What worked
- **The 3 prior no-orphan-sweep siblings (`test-understanding-wiring.sh`, `test-kri-wiring.sh`,
  `test-docs-wiring.sh`) made this fast to design correctly.** Reusing their exact shape
  (PASS/FAIL counters, a load-bearing negative control, WORKFLOW.md as the parsed single
  source of truth) meant the only genuinely new design work was the generic per-file sweep
  loop itself, not the whole test harness.
- **Dogfooding the newly-wired commands against this very sub-goal's own SPEC/ship caught real
  bugs before they shipped.** Writing SPEC-139's own `## Design`/`## Test plan` sections and
  running `spec-validate`'s adversarial pass live (not just describing it) is what surfaced the
  design decisions now in the Decision Log.

## What hurt
- **The first sweep-check regex was too strict and produced a false negative.** A first draft
  keyed on the literal invocation shape `` `bash lib/gate-ledger\.sh <verb>` `` and would have
  wrongly flagged `commands/quiz-gate.md` an orphan, because that file's real emit is phrased
  as `` `gate-ledger.sh debt-response` `` (no `bash lib/` prefix in the same backtick span).
  Caught only by actually running the check against the real repo before trusting it.
- **The exemption-table parser initially over-matched.** `exemption_list()`'s first version
  grepped for ANY backtick-wrapped `.md` mention anywhere in the new WORKFLOW.md section,
  which picked up self-referential mentions inside the table's own rationale prose (e.g. the
  `mega.md` row explaining itself twice) and prose from the paragraph ABOVE the table (e.g.
  "the same convention `test-plan.md` / `review.md` already use"). Fixed by anchoring the
  parser to the table's FIRST COLUMN only (`^\| *`name.md`...`), not any backtick mention in
  the section.
- **A negative-control fixture almost defeated itself.** The first fixture command's own
  description text said "no gate-ledger mention" -- which itself matched the sweep's
  `grep -qi gate-ledger` check, making the fixture accidentally pass as "wired." A classic
  self-referential test-fixture trap; fixed by rephrasing the fixture to avoid the substring
  entirely (and noting the trap explicitly in the Test plan's case 8).

## Action items
- [ ] None owed back to the kit itself from this pass; the pre-existing `Build`/design-record
      gap (no command records either phase) is named honestly in WORKFLOW.md and left as a
      backlog candidate for a future sub-goal, not fixed here (out of this sub-goal's scope).

## Kit feedback
The no-orphan-sweep pattern (this is now the fourth instance in this repo) is mature enough
that a future generalization -- a single reusable `lib/no-orphan-sweep.sh` shared by all four
callers instead of four independently-written `_wired`/`sweep_check` functions -- might be
worth a future sub-goal's time. Not done here (surgical-change discipline; each of the four
existing files works and touching the other three is out of this sub-goal's scope).
