# Sub-goal 06: docs + wiring (the understanding axis, honestly)

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table: WORKFLOW.md + AGENTS.md declare the understanding axis, claiming ONLY what actually dispatches (the no-orphan check over every artifact this wave added: Design block, significance-classify, /kit:explain, quiz gate, batch flow) · README notes `/kit:explain` · a WORKFLOW claim with no dispatch path = a caught finding (negative control, mirrors kit-hardening c6fbd99).
**Depends on:** ALL (01-05; docs-last, reflect the final wired state , the kit-face lesson).
Model: sonnet
Effort: medium
**Branch:** feat/ug-06-docs
**PR base:** master

## Outcome

The kit's contract docs describe the new UNDERSTANDING axis truthfully: WORKFLOW.md gains the design-record (before) + explainer/quiz (after) beats and where each fires; AGENTS.md notes the axis in the operate-contract; the README commands table adds `/kit:explain`. Every claim is backed by a live dispatch path , the no-orphan check (kit-hardening's c6fbd99 bug class) runs over the Design block, significance-classify, /kit:explain, the quiz gate, and the batch flow; a documented-but-unwired artifact or an over-claim is a blocking finding.

## Quality bar

Honesty over completeness (the c6fbd99 lesson): claim only what dispatches. Docs LAST so they reflect the final wired state, not a mid-wave snapshot. The understanding axis is described as ADVISORY (it never joins the hard verification blocks).

## How to close the loop

`/spec` + `/spec-validate` first. Then `bash tests/test-meta.sh` (roster/doc pins) + the no-orphan sweep over the wave's artifacts + the over-claim NC. Assumptions: ROADMAP 06.

**Done =** WORKFLOW.md + AGENTS.md + README describe the understanding axis with every claim dispatch-backed (no-orphan sweep clean), the over-claim NC caught, test-meta green.

## Scope edges

**In:** WORKFLOW.md, AGENTS.md, README.md commands table, the no-orphan verification.
**Out:** the machinery (01-05); the ADR (0031, already written).
**Not:** claiming an artifact operational that nothing dispatches; a fourth doc surface.

## Where to look

WORKFLOW.md (the phase table + lane rows), AGENTS.md (the operate-contract), README.md (commands table), the kit-hardening c6fbd99 fix (the no-orphan precedent), all of 01-05's shipped artifacts (what actually dispatches).

## PR body

Docs + wiring: WORKFLOW.md/AGENTS.md/README declare the understanding axis, claiming only what dispatches (no-orphan sweep over the Design block, significance-classify, /kit:explain, quiz gate, batch flow). Verify: test-meta + no-orphan sweep + over-claim NC. Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
