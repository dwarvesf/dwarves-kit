# Spec: advisory decision-capture nudge at /kit:retro

Status: DRAFT
Lane: normal

## Problem

repository-harness captures decisions as a routine terminal-lane step (their `docs/decisions/`
flow). dwarves-kit already has the pieces (a `docs/decisions/` ADR set, the `/kit:retro` reflect
gate, a Build-decisions translation check), but nothing at retro explicitly prompts the operator
to spin a non-obvious decision that fell OUTSIDE a SPEC Decision Log into an ADR. So those
decisions are captured only when the operator remembers to.

A4 originally proposed making the reflect gate EMIT a structured decision file as a required step.
That is rejected: it duplicates the existing ADR flow and PHILOSOPHY explicitly "rejects
hard-gating process completeness." This spec is the lite version: an advisory nudge, not a gate.

## Solution

Add **Step 1c** to `commands/retro.md`, next to the existing completeness sweep (Step 1b). It asks
once whether the cycle made a non-obvious, reversible-with-cost decision not already in a SPEC
Decision Log or an existing ADR; if so, it suggests drafting `docs/decisions/NNNN-<slug>.md` in the
style of the existing ADRs (there is no template file). It is advisory: on decline it logs one line
to `completeness.log` (mirroring Step 1b), never blocks.

### Boundaries
- In: one advisory step in `commands/retro.md` + a meta assertion that it exists and is framed
  advisory.
- Out: any hard gate; a new lib script; an ADR template file; changing the ADR numbering or the
  retro document shape.

## Task Breakdown
- [ ] TASK-001: add Step 1c (advisory decision-capture nudge) to `commands/retro.md`.
- [ ] TASK-002: `test-meta.sh` assertion that retro.md carries the nudge AND the word "advisory"
  near it (so a future edit cannot quietly turn it into a hard gate without failing the test).

## After state
- [ ] `commands/retro.md` has a "Decision-capture nudge (advisory)" step pointing at `docs/decisions/`.
  (Today: retro mentions docs/decisions only in Step 5 feed-forward, with no decision-capture prompt.)
- [ ] The step is explicitly advisory + logs-on-decline, never a block.

## Acceptance Criteria
- [ ] `bash tests/test-meta.sh` passes with the new assertion.
- [ ] No hook or lib change (advisory text only).

## Verification
`bash tests/test-meta.sh` + a grep showing the advisory framing, recorded in
`docs/verification/retro-decision-nudge.md`.

## Out of Scope
- Forcing/emitting a decision file (the rejected A4-full); the ADR numbering scheme.

## Decision Log
- DEC-001: advisory nudge, not a required emission. Reason: the ADR flow already exists and
  PHILOSOPHY rejects hard-gating process completeness. Builds on the Step 1b "report as signal,
  not a block" precedent.
- DEC-002: placed at Step 1c (beside the completeness sweep), not Step 5, so the prompt happens
  during the sweep where the operator is already reviewing what this cycle did or did not capture.
