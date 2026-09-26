# Proof of done: Reviewer 7 stays silent on a not-long-lived spec

2026-09-26. Spec: `docs/specs/SPEC-319-r7-quiet-calibration.md`. Lane: normal. Files:
`commands/spec-validate.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated),
`docs/implementation-notes/r7-quiet-calibration.md`, this file.

Acceptance: on the quiet fixture, Reviewer 7 raises no finding, solo or co-tagged, in 3 of 3
live samples, and the four long-lived Reviewer 7 signals stay 3/3.

| Check | Command | Exit | Result |
|---|---|---|---|
| Structural | `bash tests/test-meta.sh` | 0 | `Passed: 862 / 862`, `All meta tests passed.` |
| Structural | `bash tests/test-design-record.sh` | 0 | `Passed: 36 / 36`, `All design-record tests passed.` |
| Live, first wording | `lens-eval.sh commands/spec-validate.md origin/master tests/fixtures/sustainability-lens/lens-eval.json --samples 3 --live --model sonnet` | 1 | `quiet-no-findings` 1/3 want miss (leaked once); four R7 long-lived signals 3/3; revised the wording, reran |
| Live, revised wording | same command, after the revision below | 1 | `quiet-no-findings` 0/3 want miss (PASS); four R7 long-lived signals 3/3; overall FAIL only on the unrelated `-any` signals (see Limits) |

## Green run

```
Command: bash tests/test-meta.sh
Exit: 0
Output: Passed: 862 / 862 / All meta tests passed.
```

```
Command: bash tests/test-design-record.sh
Exit: 0
Output: Passed: 36 / 36 / All design-record tests passed.
```

## The wording change

Before (measured leak, `docs/verification/prompt-lens-eval.md` live run 3 and run 2):

```
2. **If NOT long-lived:** one line, `not long-lived: <why>`, and no findings.
```

After:

```
2. **If NOT long-lived:** one line, `not long-lived: <why>`, filed under `## Passed`, and
   nothing else from this reviewer anywhere in Critical Issues or Warnings, solo or co-tagged
   onto another reviewer's finding, even about retirement, rotation, or lifespan.
```

The first revision ("No finding, and no co-tag on another reviewer's finding...") still let
Reviewer 7 raise its own standalone numbered finding on the alias-removal gap (`quiet-no-findings`
1/3). The wording above closes that: it names both failure shapes (solo and co-tagged) and both
destination sections (Critical Issues, Warnings), not just "no findings."

## Live run, revised wording (sonnet, N=3, base `origin/master` `a4e906085807c6ba33dd0912ad333a0e501152fe`)

Control = the base-ref text (current, unfixed Reviewer 7 step 2). Treatment = the working-tree
text (this fix). Command:

```
bash lib/bench/lens-eval.sh commands/spec-validate.md origin/master \
  tests/fixtures/sustainability-lens/lens-eval.json --samples 3 --live --model sonnet
```

| case | signal | treatment | control | result |
|---|---|---|---|---|
| long-lived | liveness-r7 | 3/3 want hit | - | PASS |
| long-lived | liveness-any | 3/3 want hit | 3/3 want fewer | FAIL |
| long-lived | retirement-r7 | 3/3 want hit | - | PASS |
| long-lived | retirement-any | 3/3 want hit | 3/3 want fewer | FAIL |
| long-lived | rotation-r7 | 3/3 want hit | - | PASS |
| long-lived | rotation-any | 3/3 want hit | 3/3 want fewer | FAIL |
| long-lived | cost-r7 | 3/3 want hit | - | PASS |
| short-lived | quiet-no-findings | 0/3 want miss | - | PASS |

```
text sha256: treatment 68763a74b416 control 10b245b467cc
cost: $0.423153 over 9 calls, 360s
script verdict: FAIL (3/8 signals failed: liveness-any, retirement-any, rotation-any)
```

**Required signals for this task, both met:** `quiet-no-findings` 0/3 (Reviewer 7 raises no
finding on the quiet fixture, in any of 3 samples), and the four Reviewer 7 long-lived signals
(`liveness-r7`, `retirement-r7`, `rotation-r7`, `cost-r7`) all 3/3.

## First live run, before the revision (for the record)

Same command, base and case file, before the wording revision above:

| case | signal | treatment | control | result |
|---|---|---|---|---|
| short-lived | quiet-no-findings | 1/3 want miss | - | PASS (majority), but not 0/3 |

Sample 2 (`short-lived.treatment.2.md`): Reviewer 7 filed its `not long-lived` pass line under
`## Passed`, then separately raised warning item 2, tagged solely `— Reviewer 7 —`: "The notice
text `--verbose is renamed --debug` doesn't name the removal release. ... the alias can linger
indefinitely." That is a standalone finding, not a co-tag, so the first wording's "no co-tag on
another reviewer's finding" language did not cover it. Cost $0.361555, 292s, 9 calls; treatment
sha256 `8325f0708134`, control sha256 `10b245b467cc` (same base commit as the revised run).

## Negative control

The first live run above is the negative control for this fix: same fixture, same command file
before the revised wording, with the pre-revision text still allowing a solo Reviewer 7 finding
on the quiet case (1/3, not 0/3). The revised wording brings it to 0/3 on the identical fixture
and sample size, with no other change to the command file.

## Limits

The `-any` family (`liveness-any`, `retirement-any`, `rotation-any`) FAILs on both live runs
because it expects the control arm to raise fewer of these signals than the treatment arm across
ALL reviewers, on the long-lived case. This fix only edits Reviewer 7's not-long-lived branch
(step 2), which the long-lived fixture never reaches, so control and treatment prompts are
functionally identical there and produce the same hit counts. These three signals are not part
of this task's required bar and were not expected to move; they are unrelated pre-existing
eval characteristics of the `-any` family, not a regression from this change. N=3 per arm; a
PASS is evidence about the prompt text on these samples, not a production rate. One model plays
all 7 reviewers inline in a single context, per the eval's own stated limits
(`docs/verification/prompt-lens-eval.md`).
