# Implementation notes -- r7-quiet-calibration

Delta from `docs/specs/SPEC-319-r7-quiet-calibration.md` only.

- One deviation from a straight-line read of the contract: the spec's Test plan calls for
  revising the wording "once" if the quiet case is not 0/3. The first attempt at the wording
  ("No finding, and no co-tag on another reviewer's finding...") still leaked at 1/3 in the live
  run, because it named co-tagging but not a standalone Reviewer 7 finding raised on its own.
  The one allowed revision closed both shapes explicitly (solo and co-tagged, both destination
  sections). Recorded in `docs/verification/r7-quiet-calibration.md` as both live runs, not
  silently overwritten.
- `docs/FEATURES.md` needed regeneration after the edit (`lib/registry/feature-registry.sh
  generate`); `tests/test-meta.sh`'s freshness check caught this on the first run and passed
  after regeneration, confirming the check's own coverage rather than a defect in the fix.
- The `-any` family of signals in the case file (`liveness-any`, `retirement-any`,
  `rotation-any`) fails on both live runs and is expected to: this fix does not touch the
  long-lived branch (step 3) at all, so control and treatment prompts are byte-identical on
  that path and produce equal hit counts, failing the `fewer` comparison by construction. Not
  a regression; not in scope per the task's stated required signals.
- Reviewer 7's step 3 (the five-question long-lived path) is untouched; the fix is scoped
  entirely to step 2's not-long-lived branch, per the spec's Contract.
