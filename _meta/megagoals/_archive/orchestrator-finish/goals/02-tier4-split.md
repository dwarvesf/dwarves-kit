# Sub-goal 02: tier4-split (ID-093)

**Merge policy:** auto
**Time budget:** 2-4 hours of loop work
**Proof:** run-table showing the TIER-4 close dispatching 3 verifier sessions + the aggregation, plus a negative control (one dissenting verifier is NOT silently dropped). Rung 2.
**Design:** obvious
**Depends on:** none; base main; 02 is the stack root for the orchestrate.sh chain (merge-hygiene stacking, not a logical dependency)
Model: sonnet
**Branch:** fix/orchfin-02-tier4-split
**PR base:** main

## Outcome

The TIER-4 convergence close runs THREE independent fresh-context verifiers and aggregates their verdicts, instead of one single-prompt verifier whose blind spot passes the whole assembled run. A single verifier missing a cross-sub-goal seam no longer green-lights the mega; a dissent from any of the three surfaces.

## Quality bar

Three fresh contexts, one honest aggregate. A convergence close that says PASS means three independent reads agreed, not that one prompt didn't notice.

## How to close the loop

- Find the current single-prompt TIER-4 verifier in the close path (`lib/queue/orchestrate.sh`, `TIER4_CLOSE`).
- Split it into 3 fresh-session verifier dispatches + an aggregator that fails-closed on any dissent (majority-refute or any-dissent, per the existing convergence-gate semantics; match whatever the mega close already uses).
- Test: simulate 3 verifier outputs incl. one dissent; assert the aggregate is NOT PASS. Assert 3 dispatches happen when `TIER4_CLOSE=1`.
- Capture the run-table (command + exit + the aggregation decision on the dissent case).

**Done =** the TIER-4 close dispatches 3 fresh verifiers + aggregates, AND the negative control (one dissenting verifier) makes the aggregate fail-closed, both in a captured run-table.

**Kit-adopted repo? Record the gates.** From dwarves-kit cwd: `lane-classify` → `normal`; record build+review gates via `gate-ledger.sh` before push.

## Handoff on completion

1. Flip ROADMAP box `[x]` + PR #. 2. Overwrite `HANDOFF.md` → sub-goal 03 + first action + pointers. 3. Append `DECISIONS.md`. 4. Report in records, EXIT.

## Scope edges

**In:** the `TIER4_CLOSE` verifier dispatch + aggregation in `orchestrate.sh`.
**Out:** the per-sub-goal V-model verifiers (task/integration), the review-team lenses.
**Not:** changing what a verifier checks, adding a 4th verifier, reworking the whole close path.

## Where to look

The mega close / convergence path in `lib/queue/orchestrate.sh` (the `TIER4_CLOSE` branch), the existing verifier-dispatch helpers.

## PR body

Splits the TIER-4 close single-prompt verifier into 3 fresh sessions + a fail-closed aggregator (ID-093), so one verifier's blind spot can't pass the assembled run. Verify: the 3-dispatch + dissent-aggregation run-table. Part of `orchestrator-finish`, see ROADMAP.md.

## Notes

- Deviation (small, reversible): the goal file's PR-base/Depends-on note says "main"; this repo's default branch is `master` (confirmed via `AGENTS.md`/repo state). PR opened against `master`.
- Design choice not pinned by the goal: each verifier prompt ends with a structured `TIER4-VERDICT: PASS` / `TIER4-VERDICT: DISSENT: <reason>` line so `_aggregate_tier4_verdicts` can parse all 3 outputs uniformly regardless of which check (integration-verifier / review-team / advisor) a session ran. A nonzero session exit is folded in as a synthetic DISSENT line (never an implicit PASS). See `docs/implementation-notes/orchfin-02-tier4-split.md`.
