# Implementation notes: review diet

Delta from `docs/specs/SPEC-377-review-diet.md` only: decisions the spec did not make, deviations, and tradeoffs.

## Before the edits

- The spec skips the validation round. The operator approved the design in session, so the gate ledger carries `override Validate` with that reason. The spec is the fast path's own first customer.
- `lane-classify.sh classify` on the task text prints `LANE-SUGGEST: full (kit-machinery)`, because the words "spec validation" and "gate" match. The diff touches only `commands/`, `docs/` and `tests/`, none a hard path, so the operator-assigned `normal` stands. Rule L exists to stop this exact word-match habit.
- `commands/execute.md` on master carries three stale `||||||| parent of edc8990c` conflict-base lines, each followed by a duplicate of the live paragraph or bullet. Cleaning them is out of scope. The edits below touch the live paragraphs only. Follow-up for the maintainer: delete those stale blocks.

## Decisions

- C5 changes the tier on every lane, not only normal and backfill. Reviewers 1-5 and 7 run on Sonnet on the full lane too. Reviewer 6 stays on Opus everywhere, and the single-pass fallback validator stays on Opus so Reviewer 6's invariant holds.
- The full lane keeps its current round ceiling (3). Only the model tier and the critical bar change for it.
- `docs/MANUAL.md` states the old tier in one sentence and gets the same edit, so the docs agree.
- C2 carve-out. Checks that name their own critical keep it: Reviewer 4's atomicity check and depth line, and Reviewer 6's design record. The mechanical depth check is a spec-structure rule the spec's tests never cover, so "tests would miss it" cannot apply to it.
- C1 and C3 fit together as: fold, fold-diff check, then a second full round only when round 1 raised a critical the fold must fix. The fold-diff check picks the lens the fold touched (Reviewer 6 for `## Design`), runs outside `validate-round`, and writes no ledger round. A critical from it goes to the operator.
- C4 also reaches `commands/wrap.md` (the step-10 APPROVED bullet) and `commands/execute.md` (the preflight APPROVED bullet), because both said "fold the warnings".
- `commands/wrap.md` step 10 keeps its full-lane re-validation flow unchanged: a NEEDS REVISION worker fold and re-run is a full-lane ceiling path.
- Five suites fail on master the same way as on this branch: `test-gate-opt-out`, `test-install-contract`, `test-research-arch-contract` (row 7), `test-wrap-deploy`, `test-wrap-report-lint`. Not touched here.
- `docs/FEATURES.md` was regenerated with `feature-registry.sh check --fix`, because new spec references change its per-command counts.
- Fold-diff step names no model. Under C5 a Sonnet reviewer covers Reviewers 1 to 5 and 7 and Opus covers Reviewer 6, so the tier follows the lens.
