# Spec: review diet (fewer validation rounds, a real critical bar, Sonnet reviewers)

Generated: 2026-09-30
Status: DRAFT
Lane: normal (commands/ and docs/ only; no hard path per .kit.toml extra_hard_paths; operator assigned)
Depth: standard (six prose rules in command docs, each pinned by a grep assert in the suite that already pins spec-validate wording)
References: `commands/spec.md` step 5 (the parallel round and its ceiling), `commands/spec-validate.md` (Output format, Single-reviewer mode), `commands/review-team.md` (the cheap-tier dispatch pattern C5 copies)
Source: `docs/retro/RETRO-2026-09-30-kit-follow-through.md` action items 1 to 3; the "SPEC C" and "Root cause" sections of the ops-toolkit research note `2026-09-30-kit-ship-loop-speedup.md`

## Problem

Validation and review ceremony cost more than the changes they guard. The last cycle ran 13 rounds of 7 reviewers, about 91 reviewer runs, for 2 shipped changes of 400 to 500 lines each. Three habits drove it:

| Habit | Effect | Retro evidence |
|---|---|---|
| Full lane chosen by habit for internal tooling | Full ceiling (3 rounds) and Opus tier on every reviewer | 91 runs for 2 ships |
| Any lens can call a finding critical | Round 4 of one spec blocked on findings the build's tests would catch | "The critical bar" moved it to real gaps |
| Every fold re-runs all 7 reviewers, and every warning is folded into the spec | Folds created the next round's critical; specs grew 204 to 641, 330 to 471, 206 to 338 lines | "Folds created the next round's critical" |

One fix worked in practice: a single reviewer reading only a fold's diff caught a critical three full rounds had missed.

## Rules

Each rule is prose in a command or workflow doc. No code under `lib/gate`, `lib/classify` or `hooks/` changes.

| # | Rule | Lands in |
|---|---|---|
| L | A kit spec copies its `Lane:` from `lib/classify/lane-classify.sh`. It takes `full` only when the floor hits a hard path or a WORKFLOW full-lane trigger applies. Choosing `full` by habit is a misroute. | `docs/WORKFLOW.md`, "Size the work first" |
| C1 | Round cap. The normal lane gets 1 validation round. A second round runs only when round 1 raised a critical that the fold must fix. The full lane keeps its ceiling of 3. | `commands/spec.md` step 5 |
| C2 | Critical bar. A finding is CRITICAL only if the spec's own tests would miss it. Anything the build's tests would catch is a warning. Reviewer 6's design-record block is the one existing exception. | `commands/spec-validate.md` |
| C3 | Fold-diff check. After a fold, one reviewer reads only the fold diff, not a full new round, before the build or the next round. This is the default re-check. | `commands/spec.md` step 5 |
| C4 | Warnings. A folded warning that tests would catch goes to `docs/implementation-notes/<slug>.md` for the builder, not into the spec. The spec grows only by what a critical requires. | `commands/spec.md`, `commands/spec-validate.md`, `commands/execute.md` |
| C5 | Model tier. Validation Reviewers 1 to 5 and 7 dispatch on Sonnet on every lane. Reviewer 6, the only one that can block, stays on the session's top model (Opus). | `commands/spec.md`, `commands/execute.md`, `docs/MANUAL.md` |

Boundaries:

- Rule L defers to the classifier and to the diff floor at push. It adds no new trigger and no new block.
- C1 reuses the existing "second round" slot. `operator_directed_build: true` still opens the extra round on the normal lane, as today.
- C3 replaces "re-run every reviewer" as the default re-check on the normal lane. The full lane keeps re-running every reviewer, and may add the fold-diff check before it.
- C5 does not touch the single-pass fallback validator: it stays on Opus so Reviewer 6's tier holds when the fan-out could not be issued.
- Out of scope: the retro's master-red fix, the `test-meta.sh` split and the `shipping pr=` record.

## Tasks

| ID | Task | Files | Done when |
|---|---|---|---|
| T1 | Add rule L to the lane section | `docs/WORKFLOW.md` | The "Size the work first" text says a kit spec copies its lane from `lane-classify.sh` and that `full` by habit is a misroute |
| T2 | Add C1, C3 and the C4 fold wording to step 5, and switch the validator tier lines to C5 | `commands/spec.md` | Step 5 states 1 round on normal, the fold-diff default, warnings to implementation notes, and Sonnet for all but Reviewer 6 |
| T3 | Add the C2 critical bar and the C4 warning routing | `commands/spec-validate.md` | A "Critical bar" paragraph sits before Output format; the NEEDS REVISION fold line routes warnings to notes |
| T4 | Align every other doc that states the old tier or the old warning fold | `commands/execute.md`, `commands/wrap.md`, `docs/MANUAL.md` | no live line in `commands/` or `docs/MANUAL.md` still ties the reviewer tier to the lane |
| T5 | Update the one assert that pins the old tier and add asserts for the new rules | `tests/test-meta.sh` | Asserts for C1, C2 and C5 wording pass; each fails when its doc line is reverted |
| T6 | Record notes, proof, changelog | `docs/implementation-notes/review-diet.md`, `docs/verification/review-diet.md`, `docs/CHANGELOG.md` | Each file exists and names the negative control |

## Verification

```bash
bash tests/test-meta.sh                                   # the suite that pins spec-validate wording
bin/test-affected --base origin/master                    # every suite that names a touched file
grep -rnE "Opus on (the )?full|Sonnet on (the )?normal" commands docs/MANUAL.md   # only the stale execute.md duplicate (see notes)
grep -nP '\x{2013}|\x{2014}' docs/specs/SPEC-377-review-diet.md docs/implementation-notes/review-diet.md docs/verification/review-diet.md   # no dashes: no output
```

Negative control: revert the C1, C2 and C5 doc lines one at a time; the matching new assert goes red each time, and the two pre-existing `test-wrap` wording FAILs on master stay the only other failures.

## After state

- A normal-lane kit spec runs one validation round, then one fold-diff read, then the build.
- Six of the seven validation reviewers run on Sonnet. One Opus call per round remains, for Reviewer 6.
- A reviewer raises CRITICAL only for a gap the spec's own tests would miss. Build-catchable findings are warnings, and the builder reads them in the implementation notes.
- The full lane keeps its ceiling of 3 rounds and its hard-path gates, and the diff floor at push is unchanged.
- The spec-side cost of a fold is bounded by what a critical requires.

## Design

obvious: six sentence-level edits to command docs and one test file; no new component, control flow, schema, integration or irreversible choice.

## Decision Log

- 2026-09-30, operator approved the six rules in session. The validation round is skipped on that approval, recorded as `override Validate` in the gate ledger.
- 2026-09-30, C5 covers the full lane as well as normal and backfill, because Reviewer 6 is the only reviewer that can block.
