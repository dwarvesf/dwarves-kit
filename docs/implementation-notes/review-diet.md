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
