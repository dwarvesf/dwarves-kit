# Implementation notes: SPEC-314 sustainability lens

Delta from `docs/specs/SPEC-314-sustainability-lens.md`. The spec's own decisions are not repeated here.

## Deviations and decisions

- Eval fixtures live at `tests/fixtures/sustainability-lens/`. The spec named the fixture content but not a path.
- The negative control ran master's six-lens command on `long-lived-gaps.md` with a Sonnet reviewer. It raised seven warnings, and none named run cost, owner or liveness, retirement, or handover. Reviewer 2 came closest: it flagged the fixed 24-hour window as silent data loss, which is an incident-recovery finding, not liveness. Run 2 changed the picture on cost; see below.
- The spec validation pass raised seven warnings. All were folded into the spec before build (see its Decision Log). The biggest change narrowed the long-lived trigger: an edit to an in-repo hook or ledger covered by tests does not count. Without that, most kit specs would trip the lens.
- The Exception sentence under Output format now reads "the advisory reviewers' outcome", not "Reviewers 1-5 and 7's outcome". It says the same thing and reads better.
- The second negative-control run named per-email API cost under Reviewer 5. The spec's own criterion calls that a failed control, so `docs/verification/sustainability-lens.md` records it as a partial fail. The bar was not moved. The lens's clear value is liveness, retirement, and credential rotation (0 of 2 control runs), plus a cost question that is asked every time instead of by chance.

## Open questions

- Handover was not raised in the catch run. Watch whether real specs get it; if not, make the handover question more concrete (name a runbook or rebuild command).
- The spec's rejected `## Upkeep` template section: revisit if Reviewer 7 warns on most long-lived specs in practice.
