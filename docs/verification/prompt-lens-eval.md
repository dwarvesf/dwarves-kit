# Proof of done: a repeatable treatment-vs-control eval for prompt-only lenses

2026-09-26. Spec: `docs/specs/SPEC-316-prompt-lens-eval.md`. Lane: full. Files: `lib/bench/lens-eval.sh`, `tests/test-lens-eval.sh`, `tests/fixtures/sustainability-lens/lens-eval.json`, `lib/bench/README.md`, `lib/bench/tool.toml`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), `docs/implementation-notes/prompt-lens-eval.md`, this file.

Acceptance: one command reruns the SPEC-314 hand eval. It prints a per-case, per-signal table and a verdict, keeps every raw report, and spends nothing without `--live`.

| Check | Command | Exit | Result |
|---|---|---|---|
| Offline suite | `bash tests/test-lens-eval.sh` | 0 | `Passed: 98 / 98`, `All lens-eval tests passed.` (62 / 62 before the review round) |
| Red before build | the suite before `lib/bench/lens-eval.sh` existed | 1 | `Passed: 8 / 59`, `Failed: 51` |
| Block-scoring regression | the suite against the line scorer | 1 | `Passed: 57 / 60`; the multi-line Reviewer 7 finding missed |
| Negative control | `negctl.sh` with a tie counted as a hit | 0 | `Verdict: PASS`; the tie rows went red |
| Changed suites | `bash tests/run-all.sh --changed` | 0 | `run-all: all 36 suites passed, 0 skipped for missing tooling` (same after the review round) |
| Self-review regressions | the suite against the script before the repeated-name and regex checks | 1 | `Passed: 59 / 62`; an invalid regex case file exited 0 |
| Dry run | `lens-eval.sh commands/spec-validate.md 118485af~1 tests/fixtures/sustainability-lens/lens-eval.json` | 3 | `plan: 2 cases, 1 samples per arm = 3 model calls (sonnet)` |
| Live run 1 | the same, `--live` | 1 | FAIL on `rotation-r7`: a scorer bug, fixed |
| Live run 2 | the same, `--live`, block scorer | 1 | FAIL on the quiet case: a lens finding, recorded below |
| Review round, red first | the new suite against the pre-review script and case file | 1 | `Passed: 60 / 98`, `Failed: 38` |
| Review round, negative control | `negctl.sh` deleting the Passed-section drop | 0 | `Verdict: PASS`; 11 checks went red |
| Live run 3 | `lens-eval.sh commands/spec-validate.md 118485af~1 tests/fixtures/sustainability-lens/lens-eval.json --samples 3 --live` | 0 | `verdict: PASS (8/8 signals)`, $0.464965, 403s, 9 calls |

## Green run

```
Command: bash tests/test-lens-eval.sh
Exit: 0
Output: Passed: 98 / 98 / All lens-eval tests passed.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: all 36 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Review round (current). With N odd, a tie cannot occur, so the tie mutation below is now vacuous. The current control deletes the line that drops a Passed section.

```
## Negative control (negctl)
Command: bash tests/test-lens-eval.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' '/skip { next }/d' lib/bench/lens-eval.sh
Changed: lib/bench/lens-eval.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/bench/lens-eval.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under the mutation the suite reads `Passed: 87 / 98`. The red checks include `pair row: a Passed bullet naming heartbeat is not a control hit`, `passed: a pass bullet is not a finding`, `passed: a pass bullet naming retry is not a finding`, `control 2/3 under treatment 3/3 passes`, and `hard control miss holds at 1/3`: the stub's Passed bullet names a heartbeat, so every control sample leaks once the drop is gone.

First round (historical, tie mutation):

```
## Negative control (negctl)
Command: bash tests/test-lens-eval.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/-gt "$samples"/-ge "$samples"/' lib/bench/lens-eval.sh
Changed: lib/bench/lens-eval.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/bench/lens-eval.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Under the mutation three checks fail: `control tie 1/2 counts as miss`, `control tie exit 0`, and `treatment tie 1/2 counts as miss`.

## Live runs (sonnet, N=1, base `118485af~1`, the six-reviewer command)

| Signal | Want | Run 1 (line scorer) | Run 2 (block scorer) |
|---|---|---|---|
| liveness-r7 | treatment hit | 1/1 PASS | 1/1 PASS |
| liveness-any | control miss | 0/1 PASS | 0/1 PASS |
| retirement-r7 | treatment hit | 1/1 PASS | 1/1 PASS |
| retirement-any | control miss | 0/1 PASS | 0/1 PASS |
| rotation-r7 | treatment hit | 0/1 FAIL | 1/1 PASS |
| rotation-any | control miss | 0/1 PASS | 0/1 PASS |
| cost-r7 | treatment hit | 1/1 PASS | 1/1 PASS |
| quiet-pass | treatment hit | 1/1 PASS | 1/1 PASS |
| quiet (see below) | treatment miss | 0/1 PASS | 1/1 FAIL |
| Cost, time | | $0.175706, 107s, 3 calls | $0.200645, 140s, 3 calls |

Run 1: the model tagged `12. **Dependency and credential lifespan.** Reviewer 7.` on the title line and wrote `There is no rotation path for the IMAP or Anthropic keys` on an indented line below. The line grep split them. Scoring now works on finding blocks, and the stub answers in that shape.

Run 2: Reviewer 7 printed `not long-lived` for the flag-rename fixture, then also raised a numbered finding tagged Reviewer 7: `2. The one-release alias has no removal trigger.` The lens contract gives a short-lived spec no findings, so this FAIL is real at N=1. The run used the keyword signal `quiet-no-upkeep`, which matched the pass line's word `alias-retirement`. The case file now uses `quiet-no-findings`, any numbered finding tagged Reviewer 7. Rescored offline on run 2's saved sample, it also fails, on the numbered finding.

The SPEC-314 hand eval recorded a clean quiet case on one sample. One more sample says the Reviewer 7 calibration can leak on a short-lived spec. Rerun with `--samples 3` before changing the lens.

## Live run 3 (sonnet, N=3, base `118485af~1`, after the review round)

```
base: 118485af~1 cd9745bf09bf2fdc7708cbe8585a76e125b2c332
text sha256: treatment 10b245b467cc control 11e7c55e91fc
cost: $0.464965 over 9 calls, 403s
verdict: PASS (8/8 signals)
```

| case | signal | treatment | control | result |
|---|---|---|---|---|
| long-lived | liveness-r7 | 3/3 want hit | - | PASS |
| long-lived | liveness-any | 3/3 want hit | 1/3 want fewer | PASS |
| long-lived | retirement-r7 | 3/3 want hit | - | PASS |
| long-lived | retirement-any | 3/3 want hit | 0/3 want fewer | PASS |
| long-lived | rotation-r7 | 3/3 want hit | - | PASS |
| long-lived | rotation-any | 3/3 want hit | 0/3 want fewer | PASS |
| long-lived | cost-r7 | 3/3 want hit | - | PASS |
| short-lived | quiet-no-findings | 1/3 want miss | - | PASS |

Control 2 raised liveness once, under Reviewer 2: `Suggested fix: add a dead-man signal, such as a failure ping to Discord or a heartbeat check.` This is the case the `fewer` expectation exists for. At N=1 with that sample, the old hard `miss` would have failed the eval on a gap the old lens noticed by chance.

Quiet case: in all three samples Reviewer 7 printed its `not long-lived` pass line under `## Passed`, which the scorer now drops. Sample 3 still raised a numbered finding tagged Reviewer 7, jointly with Reviewer 3: `1. The one-release alias has no removal trigger. ... Reviewer 3, Reviewer 7 (the alias is a deprecation shim that outlives this change, so this is a retirement gap).` Samples 1 and 2 raised no Reviewer 7 finding. So Reviewer 7 raised a numbered finding on the flag-rename fixture in 1 of 3 samples here, and in 1 of 1 in live run 2. That is 2 of 4 live samples so far. The majority rule passes the signal at N=3, but the calibration leak is real and recurs. The lens text, not this eval, is the place to fix it.

## Limits

N=1 per arm on live runs 1 and 2, N=3 on live run 3. The verdict shows what held on these samples, not a rate. One model plays every reviewer inline in a single context, so a PASS is evidence about the prompt text, not a production run of the command. The grep checks that a finding names a thing, not that the finding is right. A hung call has no timeout.
