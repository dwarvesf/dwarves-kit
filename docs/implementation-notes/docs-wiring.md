# Implementation notes: docs-wiring (SPEC-127, SG-06)

The DELTA from SPEC-127. Decisions the spec did not pin down, deviations, and constraints found
while building. Not a mirror of the spec.

## 2026-07-04 The main deliverable turned out to be a real over-claim, not a hypothetical

Context: SPEC-127's own contract framed the significance-classify wiring question as an example
("e.g. significance-classify is defined but nothing actually calls it at ship"). A live sweep of
the merged SG-01..05 state confirmed this is not hypothetical: `WORKFLOW.md`'s pre-existing
"Understanding-debt marker" bullet read "at Ship, run `bash lib/significance-classify.sh record
<rid> ...`" as if this were a step `/kit:ship` executes, but `commands/ship.md` (the file
`/kit:ship` actually runs) never mentions `significance-classify` at all -- confirmed by
`docs/implementation-notes/significance-classify.md`'s own 2026-07-03 entry ("no command ...
actually invokes `significance-classify.sh record` yet ... wiring the call site is SG-04's
problem"). Tracing `lib/quiz-gate.sh`'s `cmd_tap` (SG-04's own machinery) shows it calls
`significance-classify.sh classify` (transient, computes a verdict, writes nothing) -- never
`record` (the verb that actually appends the `| DEBT |` ledger marker via `gate-ledger.sh debt`).
So SG-04 did not close the gap SG-02 deliberately left open; it is still open today.
Decision: documented this honestly in `WORKFLOW.md`'s new "## The understanding axis" section
(a "Known wiring gap, stated honestly" bullet) rather than silently continuing the over-claim, and
did NOT edit `commands/ship.md` to add the missing call -- that file is SG-02/04 machinery, out
of scope for this docs-last sub-goal per its own "Out:" list.
Why: the contract is explicit -- "claim only what dispatches" and "never paper over" -- and
fixing machinery from a closed sub-goal inside a docs-only PR would blur the scope boundary the
mega-goal draws between sub-goals.
Alternatives considered: (a) silently leave the over-claiming wording as-is (rejected -- exactly
the c6fbd99 bug class this sub-goal exists to catch); (b) add the missing call to
`commands/ship.md` myself (rejected -- out of scope; a one-line fix to shipped machinery deserves
its own reviewed change, not a drive-by inside a docs PR).
Impact: `WORKFLOW.md` now states plainly that only `significance-classify.sh classify` is live
(via `quiz-gate.sh tap`), and that `record` (the raw verdict-persisting marker, independent of the
tap decision) has no caller -- meaning a significant-but-low-worthiness or not-significant change
that never reaches a `gate`/gated-final PR is not logged to the debt ledger at all today. Flagged
to the conductor in the final report as a candidate follow-up (add a call in `commands/ship.md`
Step 8, before the quiz-gate tap line), not blocking this PR.

## 2026-07-04 Consolidated three scattered bullets into one `## The understanding axis` section

Context: SG-01/02/04 each landed WORKFLOW.md edits piecemeal as their PRs merged: a "Design
record" row in the lane x phase depth matrix, two bullets under "## Gate ledger and ship
enforcement" (Understanding-debt marker, Understanding-gate nudge). Nothing mentioned
weekend-batch (SG-05) at all, and the two gate-ledger bullets lived under an ADR-0024 section
heading despite being an ADR-0031 concept.
Decision: added one `## The understanding axis (ADR-0031)` section (BEFORE beat / AFTER beat /
debt-budget model / weekend-batch / the honest gap, in that order) and replaced the two gate-
ledger bullets with a one-line pointer to it, rather than leaving both copies live.
Why: a single source of truth for the axis' story avoids the drift the doc-compaction discipline
elsewhere in this repo already guards against, and it is the only way the no-orphan sweep test
can assert something coherent ("the axis is declared") instead of grepping three unrelated
fragments.
Alternatives: leave the scattered bullets and just patch the one over-claim in place -- rejected,
does not satisfy the contract's "declare... WHERE each fires" as one coherent story, and keeps two
homes for the same fact (the exact shape that produced the over-claim in the first place: nobody
updates one bullet when quiz-gate.sh changes what it actually calls).
Impact: `docs/architecture.md`'s per-artifact rows (added by SG-03/SG-04) were left untouched --
they are accurate, artifact-level entries in a different doc (the component inventory), not a
duplicate of WORKFLOW's narrative section.

## 2026-07-04 Found + fixed a second orphan class: 4 shipped test files never wired into CI

Context: while writing the no-orphan sweep's assertion machinery, a check of
`.github/workflows/test.yml` against the actual `tests/test-*.sh` file list (40 files) found only
20 referenced as explicit CI steps. `test-design-record.sh` (SG-01), `test-explain.sh` (SG-03),
`test-quiz-gate.sh` (SG-04), and `test-weekend-batch.sh` (SG-05) all exist, all pass locally, and
none of them run in CI -- meaning a regression in any of the five understanding-gate artifacts
would go undetected by the CI gate. Only `test-significance-classify.sh` (SG-02) was wired.
Decision: added CI steps for all four missing test files, plus a fifth for this sub-goal's own
`tests/test-understanding-wiring.sh`, after confirming all five pass standalone first (design-
record 26/26, explain 14/14, quiz-gate 29/29, weekend-batch 22/22, understanding-wiring 17/17).
Why: this is the exact same bug class the whole sub-goal exists to catch (a proof artifact exists
but nothing invokes it) -- discovering it while building the no-orphan check and not fixing it
would be the sub-goal failing its own standard. `.github/workflows/test.yml` is not on the frozen-
surfaces list, and the fix is mechanical (one line per missing test, no logic change).
Alternatives: leave it for a separate follow-up PR -- rejected, the fix is low-risk, directly
in the spirit of "no-orphan," and I had already verified all four pass locally before wiring them.
Impact: CI now runs 25 test files instead of 20 (still not all 40 -- a broader "every test file
must have a CI step" sweep across the whole repo, not just the understanding-gate wave, is a
separate, larger follow-up left for the conductor to scope).

## 2026-07-04 No deviations on the Design block for this spec

SPEC-127's own `## Design` block collapses to `obvious: <why>` per SG-01's own contract (docs +
one grep-based test script, no new component/schema/integration/irreversible choice, exactly one
viable approach for the sweep script's shape). Recorded here for completeness, not because it
required a decision.
