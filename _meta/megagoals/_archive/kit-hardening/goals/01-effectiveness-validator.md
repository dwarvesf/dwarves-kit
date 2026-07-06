# Sub-goal 01: agent-effectiveness validator

**Merge policy:** auto , machine-verifiable Done (a test suite over fixtures), no human-judgment step.
**Time budget:** 2-4 hours of loop work.
**Proof:** run-table (ADR-0026 table-first) with four asserted rows: planted-bad flagged with file:line · existing roster clean (no false positives) · read-only-tools assertion · fail-safe leaves `unvalidated`. Plus the AC5 diff-keyed row.
**Depends on:** none (this is the foundation 03 + 04 build on).
Model: opus
Effort: high
**Branch:** feat/kit-harden-01-eff-val
**PR base:** mega/kit-hardening

## Outcome

The kit can validate an agent definition's EFFECTIVENESS , not just its structure. A new `agent-effectiveness` reviewer inspects an agent `.md` on four lenses (tools minimal-yet-sufficient · description triggers on the right cases and not the wrong ones · instructions produce a good result · model tier fits) and flags specific defects with `file:line`. It is read-only, advisory, fail-safe, and diff-keyed: it runs on NEW or CHANGED agent definitions only, never blocks mid-flight, and an infra failure leaves the agent `unvalidated` (never a silent pass). This is what lets us TRUST agents the meta-agent generates in 03 and 04.

## Quality bar

Catches a planted-bad agent every time AND passes the hand-authored roster with zero false positives , the two failure modes (miss a bad one / cry wolf on a good one) are both fatal. Mirrors the shipped read-only verifier pattern (ADR-0005) and finding-validator fail-safe posture (SPEC-082); it must read like a sibling of `integration-checker` / `doc-verifier`, not a new species.

## How to close the loop

Implement per `dwarves-kit/docs/specs/SPEC-088-agent-effectiveness-validator.md` (tasks T1-T4). Verify with the SPEC's own command:

```
cd dwarves-kit && bash tests/test-agent-effectiveness.sh
```

Captured evidence: paste the run into the co-located proof-of-done as a run-table , one row per AC (AC1 planted-bad flagged · AC2 roster clean · AC3 read-only · AC4 fail-safe · AC5 gated), each with the literal assertion + PASS. Land it at `dwarves-kit/docs/verification/agent-effectiveness.md` (or the SPEC-016 co-located proof path the kit uses).

**Done =** `bash tests/test-agent-effectiveness.sh` exits 0 with all five AC rows green in the committed run-table, AND `agents/agent-effectiveness.md` asserts read-only tools only (no Edit/Write/bare-Bash).

**Kit-adopted repo? Record the gates (REQUIRED, or the ship-gate blocks the push).** dwarves-kit is adopted.

- Run the lane, NOT `/kit:*` (cross-repo): `bash lib/lane-classify.sh classify "agent-effectiveness validator: new read-only validator surface + tests"` (expect `full`), then build + verify per Done above.
- Record each phase before the PR push:
  ```bash
  rid=$(bash lib/gate-ledger.sh rid)
  bash lib/gate-ledger.sh record "$rid" build  ran "agents/agent-effectiveness.md + fixtures + test-agent-effectiveness.sh"
  bash lib/gate-ledger.sh record "$rid" review ran "docs/verification/agent-effectiveness.md run-table"
  # one per phase `bash lib/gate-ledger.sh plan full` lists
  ```

## Handoff on completion

1. Flip 01's ROADMAP.md box to `[x]` and record PR # + merge SHA.
2. Overwrite HOT `HANDOFF.md`: next sub-goal is 02-review-naming, first action = classify the rename lane against ADR-0029's rename map; read-pointers `dwarves-kit/docs/decisions/0029-review-function-naming-and-form.md` (The rename map section).
3. Append to WARM `DECISIONS.md`: the effectiveness validator is now the gate 03/04 pass through; its four-lens refuter framing is the contract those sub-goals' generated agents must survive.
4. Report IN the records, then EXIT.

## Scope edges

**In:** `agents/agent-effectiveness.md`, its diff-keyed wiring at the agent-author phase, fixtures (one good + one planted-bad per lens), `tests/test-agent-effectiveness.sh`.
**Out:** validating agent OUTPUT (task-verifier / integration-checker already do that); generating or fixing agents (that is the meta-agent + sub-goals 03/04).
**Not:** a hard pre-use gate on agents (stays advisory + ship-visible, like its sibling validators); a batch-validation framework (one-at-a-time, like finding-validators).

## Where to look

The agents/ dir (existing read-only validators for the pattern), `lib/` for the diff-keyed hook wiring (ADR-0025 proof-gate is the diff-keying precedent), `tests/` for the test-meta harness shape, SPEC-088 for the exact ACs.

## PR body

Adds the `agent-effectiveness` read-only validator (SPEC-088, kit-hardening SG-01): four-lens effectiveness check on new/changed agent defs, diff-keyed, advisory, fail-safe. Foundation for the meta-agent-scaffolded reviewers in SG-03/04.

Verify: `bash tests/test-agent-effectiveness.sh` (AC1-AC5 green). Proof: `docs/verification/agent-effectiveness.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. Targets the `mega/kit-hardening` integration branch.

## Notes

<empty>
