# Sub-goal 00: ADR-0036, loops split by who changes

**Merge policy:** gated-final (Han accepts the ADR; nothing downstream starts before)
**Time budget:** 1 hour
**Proof:** `docs/decisions/0036-loops-split-by-who-changes.md` exists, Status `Proposed`, carries the axis table from ROADMAP.md verbatim, upholds ADR-0031 and names what it separates (gate from teacher), lists every surface with its kit and the seam that joins them, and `tests/test-meta.sh` is green (decision index regenerated).
**Depends on:** nothing.
Model: opus
Effort: high
**Branch:** docs/learning-axis

## Outcome

One ADR that answers the operator's question of 2026-09-10 with one axis: who changes when a loop runs. The system changes: Reflect, dwarves-kit. A human changes about work the system did: Understand, split into the gate (dwarves-kit records the debt) and the teacher (learning-kit pays it, through `understand.teach`). A human changes by expanding: Study, learning-kit. Knowledge lands in one tree: context-kit. The ADR names the concrete surfaces per row (from ROADMAP.md "Sub-goals" 01 to 04), the one seam, and the empty-seam behavior (`skipped: no teacher`, raw material handed over).

## Quality bar

Uphold ADR-0031 in the first paragraph: the significance classifier, the nudge, the debt model, and the gate's placement in the engine all stand; the ADR resolves the one thing 0031 left fused, the gate and the teacher. Name the failure that motivated it in one paragraph with the evidence path (`docs/verification/wrap-candidates-scan.md`, PR #554). State the `absorb` call explicitly (Reflect, stays) so the axis is seen deciding a hard case. No re-litigation of whether an understanding gate should exist.

## How to close the loop

Write the ADR, regenerate the decisions index, run `tests/test-meta.sh`, open the PR, stop. The PR is Han's click. Acceptance flips Status to Accepted in the same PR.

**Done =** PR open, ADR Proposed, index green, ROADMAP.md gate zero paragraph points at the file.

## Scope edges

**In:** the ADR, the index, the ROADMAP pointer.
**Out:** any code.
**Not:** re-opening ADR-0031's substance; moving the gate.
