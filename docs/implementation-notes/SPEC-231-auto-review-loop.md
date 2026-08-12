# Implementation notes: SPEC-231 auto review-fix loop

Delta from the spec. The wiring itself is recorded in the spec; this note holds only what the spec did not.

## 2026-08-12 Post-merge audit follow-up

Context: a fresh-context Opus verifier audited the merged wiring (PRs #397, #398) against SPEC-231's own claims. The auto-run held end to end (lenses plus advisor in one review-team pass, execute default-run, ship-gate backstop, bounded two-round loop, design-time over-suggest, model tiers intact). It found four gaps; this follow-up resolves three.

Decision: fixed a, b, c; left d.

- a. CHANGELOG had no entry for a user-facing behavior change. Added an `[Unreleased]` Added entry. `/kit:ship` normally writes this; the spec landed as a direct wiring PR, so the entry was missed.
- b. The V-model lane-matrix row header still read "Design critique (opt-in)" while the spec's after-state requires "default (full lane)". The cell value (measure-twice on the full column) was already correct, so this was a stale label the staleness sweep missed, not a behavioral bug. Corrected the header.
- c. SPEC-231 claimed the pattern doc and the brief cross-reference the spec, but neither carried a backref. Added a one-line SPEC-231 backref to both, which is cleaner than softening the spec's verification claim.

Open question left for the operator (gap d, not fixed): `docs/WORKFLOW.md` counts "3 bounded loops (the engines)". The new review-fix loop is a bounded in-session loop but is not an engine (the engines are goal, debug, execute). Leaving the count at three treats "engine" as the spine-loop sense, consistent with the pre-existing uncounted test-plan revise loop. Revisit only if "bounded loops" starts to mean every in-session loop.
