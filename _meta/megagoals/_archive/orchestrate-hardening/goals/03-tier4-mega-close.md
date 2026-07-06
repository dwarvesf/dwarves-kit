# Sub-goal 03: a first-class mega-level TIER-4 close

**Merge policy:** auto
**Time budget:** 4-6 hours (design-bearing , the close contract + wiring it into the run).
**Proof:** run-table with COVERAGE DELTA: after all sub-goal boxes are checked, the TIER-4 close RUNS integration-verifier against the mega-goal objective · it runs `/kit:review-team` (incl. the security-reviewer lens) · it runs the advisor in BOTH modes (critique + over-suggest) · a NO-ORPHAN CHECK sweeps every artifact the wave added (defined-but-never-dispatched = a blocking finding) · only AFTER those pass does it HOLD the final human gate (it does not auto-merge past the gate) · negative control: a seeded orphan (a defined-but-never-dispatched flag/step) is CAUGHT by the no-orphan check (not silently passed). Today `orchestrate.sh` just prints "done" and returns , the NC vs today's behavior is the delta. A COVERAGE-DELTA row names covered + uncovered.
**Depends on:** 02.
Model: opus
Effort: high
**Branch:** feat/oh-03-tier4-close
**PR base:** feat/oh-02-token-capture

## Outcome

A first-class mega-level TIER-4 close in `orchestrate.sh` (or as a final auto sub-goal , open-fork 1, /spec picks): after every sub-goal box is checked, run integration-verifier against the mega-goal OBJECTIVE + `/kit:review-team` (with the security-reviewer lens) + the advisor in BOTH modes (critique + over-suggest) + a NO-ORPHAN CHECK over the whole wave, THEN hold the final human gate. Today `orchestrate.sh` just prints "done" and returns (ADR-0032 section 5 names this as a gap) , the mega-level verification is pushed to the operator. This sub-goal makes it a real close step, so the assembled result is verified as a WHOLE (cross-sub-goal wiring, no orphans, security) before Han's final click.

## Quality bar

The close VERIFIES the assembled whole, not each sub-goal again (the per-sub-goal V-model already fired). The no-orphan check is load-bearing (kit-hardening c6fbd99 class: an artifact defined + gated + documented but never DISPATCHED is a blocking finding). The close HOLDS the human gate , it never auto-merges past it (gated-final). If it lands as a final auto sub-goal (open-fork 1), it REUSES the existing lifecycle + gate ledger, not a bespoke close engine (prefer reuse).

## How to close the loop

`/spec` + `/spec-validate` first (design-bearing , write a `## Design` block: the close contract , integration-verifier + review-team + advisor + no-orphan , and open-fork 1: step inside `run` vs final auto sub-goal). Then `/kit:test-plan` + `bash tests/test-tier4-close.sh`: after all boxes checked the close RUNS the verifiers before the gate (not "done"-and-return), the seeded-orphan NC is caught, and the final gate is HELD (not auto-merged). Capture the COVERAGE-DELTA row. Assumptions: ROADMAP 03 + open-fork 1.

**Done =** the TIER-4 close runs integration-verifier + review-team (security lens) + advisor (both modes) + the no-orphan check over the assembled wave and HOLDS the human gate, the seeded-orphan NC is caught, the close replaces today's "done"-and-return, the COVERAGE-DELTA row is recorded, tests green.

## Scope edges

**In:** the TIER-4 close step (or final auto sub-goal), the integration-verifier + review-team + advisor + no-orphan wiring, the hold-the-gate behavior, tests + coverage-delta.
**Out:** the model routing (01); the token capture (02); the panes (04); the docs (05).
**Not:** re-running each sub-goal's per-task V-model (the close verifies the WHOLE); auto-merging past the human gate (gated-final , HOLD it); a bespoke close engine when the existing lifecycle + gate ledger can be reused (open-fork 1 prefers reuse).

## Where to look

`lib/orchestrate.sh` (where "done" is printed today , the close replaces it), the kit's integration-verifier + `/kit:review-team` + advisor agents (the pieces the close composes), the kit-hardening `c6fbd99` fix (the no-orphan precedent), kit-face SG-03 / kit-hardening TIER-4 (the wave-level no-orphan sweep shape), ADR-0032 section 5 (the gap this closes), the plan-for-mega-goal TIER-4 convention.

## PR body

TIER-4 mega-close: after all sub-goal boxes are checked, `orchestrate.sh` runs integration-verifier + `/kit:review-team` (security lens) + the advisor (both modes) + a no-orphan check over the assembled wave, then HOLDS the final human gate , replacing today's "done"-and-return. Executes ADR-0032 section 5. Stacked on #<02's PR>; review after it. Verify: `bash tests/test-tier4-close.sh` (verifiers-run-before-gate + seeded-orphan NC + gate-held) + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/orchestrate-hardening/ROADMAP.md`.

## Notes

<empty>
