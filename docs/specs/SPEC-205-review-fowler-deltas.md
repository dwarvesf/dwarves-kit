# SPEC-205: absorb code-review deltas into the review surface

Status: Draft · 2026-07-31 · Owner: Han
Lane: normal
Relates-to: docs/research/2026-07-31-mattpocock-trio-adoption.md §2+§4 (the adoption
design; board row ID-449), SPEC-081 (findings schema, which bounds the no-rerank
absorb), SPEC-059 (deep-module vocabulary in the same architecture lens)

## Problem

The 2026-07-31 adoption pass (ID-449) found three mechanisms in
mattpocock/skills code-review (MIT) that the kit's review surface lacks:

1. No smell vocabulary. The architecture lens speaks deep-module (SPEC-059)
   but has no named baseline for classic structural smells, so findings like
   duplicated shapes or data clumps surface ad hoc or not at all.
2. No fail-fast in `/kit:review-team`. A bad ref or empty diff fails inside
   the parallel subagents, wasting four dispatches.
3. The final summary can crown a single worst finding across lenses, which
   lets one lens mask another. Upstream's rule: report per axis, never pick a
   cross-axis winner.

## Solution shape

1. **Fowler 12-smell baseline** (Refactoring ch.3, adapted from
   mattpocock/skills code-review, MIT) lands in the architecture-lens section
   of `agents/code-reviewer.md`. The agent is loaded at dispatch, so the
   baseline reaches the subagent without pasting it into every dispatch
   prompt. `commands/review.md` (solo review, no subagent) gets the same
   baseline inline. Three binding rules travel with the list verbatim in
   spirit: a documented repo standard overrides the baseline; every smell is a
   labelled judgement call ("possible Feature Envy"), never a hard violation;
   skip anything tooling already enforces.
2. **Fail-fast** in `commands/review-team.md` Step 1: `git rev-parse` the
   fixed point and require a non-empty diff BEFORE any Agent dispatch.
3. **Per-lens summary rule** in `commands/review-team.md`: the report summary
   states totals and the worst issue PER LENS and never names a single
   cross-lens winner. The SPEC-081 merge machinery (fingerprint dedup,
   corroboration promotion, severity sort) is deliberately unchanged;
   cross-lens agreement as evidence is a kit strength the upstream rule must
   not break.

## Out of scope

A new two-axis command (the lens architecture is a superset); any change to
`lib/` or `hooks/`; changes to the SPEC-081 confidence/route schema.

## Verification

- `grep -c` finds all 12 smell names in both `agents/code-reviewer.md` and
  `commands/review.md` (12 each).
- `grep` finds the fail-fast `git rev-parse` line in `commands/review-team.md`
  Step 1 before the Step 2 dispatch section.
- `grep` finds the per-lens summary rule in `commands/review-team.md`.
- `bash tests/test-docs-wiring.sh` passes (no orphaned references).

## After state

A review-team run on a bad ref dies in Step 1 with one line instead of four
subagent dispatches. Architecture-lens findings may carry named smells as
labelled judgement calls. The merged report's summary reads per lens.
