# Implementation notes: SPEC-314 sustainability lens

Delta from `docs/specs/SPEC-314-sustainability-lens.md`. The spec's own decisions are not repeated here.

## Deviations and decisions

- Eval fixtures live at `tests/fixtures/sustainability-lens/`. The spec named the fixture content but not a path.
- The negative control ran master's six-lens command on `long-lived-gaps.md` with a Sonnet reviewer. It raised seven warnings, and none named run cost, owner or liveness, retirement, or handover. Reviewer 2 came closest: it flagged the fixed 24-hour window as silent data loss, which is an incident-recovery finding, not liveness. The gap claim holds.
