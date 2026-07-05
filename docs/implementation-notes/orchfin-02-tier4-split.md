# Implementation notes: orchfin-02-tier4-split (ID-093)

Delta from the sub-goal contract only (`_meta/megagoals/orchestrator-finish/goals/02-tier4-split.md`).

## 2026-07-06 09:00 Verdict-line contract for cross-session aggregation

**Context:** the old `_tier4_close` dispatched ONE `claude -p` session whose single prompt asked it
to run all three checks (integration-verifier, review-team+security, advisor-both-modes) and report
one SHIP/HOLD-WITH-FINDINGS verdict. Splitting into 3 independent fresh-context sessions means the
sessions no longer share a prompt or a final verdict format by construction; the aggregator needs a
machine-parseable signal from each.

**Decision:** each of the 3 verifier prompts (`_build_verifier_prompt`) ends with an explicit
instruction to print exactly one line, the last line of output: `TIER4-VERDICT: PASS` or
`TIER4-VERDICT: DISSENT: <reason>`. `_aggregate_tier4_verdicts` greps the LAST matching
`TIER4-VERDICT:.*$` line from each captured session output (`tail -1` of the grep matches, so any
verdict-shaped text the session emits mid-report before its final line is not mistaken for the
verdict) and fails closed (aggregate DISSENT) unless all 3 are exactly `TIER4-VERDICT: PASS`.

**Why:** a majority-vote aggregation was considered (per the goal's "majority-refute or any-dissent"
option) and rejected: the existing convergence-gate semantics in this file are already fail-closed
everywhere else (a single BLOCKING orphan halts before any LLM session runs; a single nonzero
verifier session halts the old code). Any-dissent keeps that same posture, and is what the sub-goal's
own quality bar asks for ("a dissent from any of the three surfaces").

**Impact:** a session that exits nonzero (crash, timeout, etc.) is folded in as a synthetic
`TIER4-VERDICT: DISSENT: verifier N session exited nonzero (rc)` line appended to its own captured
output, rather than a special-cased early return -- so `_aggregate_tier4_verdicts` has one code path
for "this verifier did not pass clean," whether that's a genuine dissent or a session-level failure.
All 3 sessions still dispatch even if an earlier one dissented or errored (dispatch is NOT
short-circuited on a rc!=0 or a dissent), matching the sub-goal's negative-control requirement that a
dissent is not silently dropped -- dropping the remaining dispatches on the first bad signal would
make partial-N failure ambiguous with all-N-ran-and-2-dissented.

## 2026-07-06 09:05 PR base is `master`, not `main`

The sub-goal contract literally says `**PR base:** main`, but this repo's actual default branch is
`master` (per the operator's dispatch instructions and this worktree's own base). Opened the PR
against `master`; no functional impact, purely a target-branch correction.

No other deviations from the sub-goal contract.
