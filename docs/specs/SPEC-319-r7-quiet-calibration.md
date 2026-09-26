# SPEC-319: Reviewer 7 stays silent on a not-long-lived spec

**Status:** VALIDATED
Lane: normal
Type: spec-feature
**Proof:** `docs/verification/r7-quiet-calibration.md`

## Problem

`commands/spec-validate.md` "### Reviewer 7: Sustainability Critic" step 2 says a spec that is
not long-lived gets one line and no findings. `lib/bench/lens-eval.sh` (SPEC-316) replayed this
lens live against `tests/fixtures/sustainability-lens/short-lived.md`, a flag-rename spec with a
one-release alias. Reviewer 7 still raised a numbered finding co-tagged onto another reviewer's
line, e.g. `1. The one-release alias has no removal trigger. ... Reviewer 3, Reviewer 7`, in 1 of
3 samples in the SPEC-316 live run 3 and in the SPEC-314 live run 2 sample, 2 of 4 live samples
overall (`docs/verification/prompt-lens-eval.md`). The step 2 wording forbids Reviewer 7 raising
its own finding but never forbids co-tagging itself onto a finding another reviewer raises, and
the alias's retirement angle is squarely Reviewer 7's usual territory, so it keeps reaching for it.

## Contract

- `commands/spec-validate.md` "### Reviewer 7: Sustainability Critic" step 2 gains: the
  not-long-lived line is filed under `## Passed`, and Reviewer 7 raises no finding and does not
  co-tag or co-sign another reviewer's finding, even one about retirement, rotation, or lifespan.
- The change stays inside step 2, at most two sentences; step 1, step 3, and the calibration
  note below it are untouched.
- Reviewer 7 stays advisory: no `BLOCKING` appears anywhere in its section.
- The word `references` does not appear anywhere in `commands/spec-validate.md`
  (`tests/test-design-record.sh` pins this).

## Design

obvious: a wording-only tightening of an existing advisory lens's quiet-case instruction, no new
code path, no schema change, no new tool. The gap is a live-measured prompt-calibration leak, not
a missing mechanism.

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Structural | `bash tests/test-meta.sh` | exits 0 |
| Structural | `bash tests/test-design-record.sh` | exits 0, no `references` hit |
| Behavioral, quiet case | `lib/bench/lens-eval.sh commands/spec-validate.md origin/master tests/fixtures/sustainability-lens/lens-eval.json --samples 3 --live --model sonnet` | treatment `quiet-no-findings` 0/3 (Reviewer 7 raises or co-tags no finding) |
| Behavioral, long-lived case (regression) | same run | all four Reviewer 7 signals (`liveness-r7`, `retirement-r7`, `rotation-r7`, `cost-r7`) stay 3/3 treatment hit |
| Negative control | the control arm of the same live run (current Reviewer 7 text, unbuilt case) | recorded as the pre-fix baseline showing the leak |

## Verification

`bash tests/test-meta.sh` and `bash tests/test-design-record.sh` exit 0. The live
`lens-eval.sh` run above records quiet-case 0/3 in treatment and the four long-lived signals
still 3/3, per `docs/verification/r7-quiet-calibration.md`.

## After state

Reviewer 7, run against a spec it decides is not long-lived, files one pass line under
`## Passed` and never appears in the Critical/Warnings sections, alone or co-tagged, even when
another reviewer's finding touches retirement, rotation, or lifespan. Not covered: Reviewer 7's
behavior on genuinely long-lived specs (the five-question path), which the eval also reruns as a
regression check but does not change.

## Decision Log

- Lane: normal, per dispatch instruction; grill and think skipped as operator-wave (the defect
  was already measured live in-session via SPEC-314/SPEC-316, no fresh discovery needed).
- Fix scoped to step 2's own wording rather than adding a new step or a post-hoc filter, because
  the leak is the model reaching for its own domain on someone else's finding, not a missing rule
  about its own findings (that rule already existed and held for genuinely quiet cases).
- Spec numbered 319: `spec-next.sh reserve` returned 315-318, which were already taken by specs
  landing on another branch; 319 avoids the collision.
