# Proof of done: a repeatable treatment-vs-control eval for prompt-only lenses

2026-09-26. Spec: `docs/specs/SPEC-315-prompt-lens-eval.md`. Lane: full. Files: `lib/bench/lens-eval.sh`, `tests/test-lens-eval.sh`, `tests/fixtures/sustainability-lens/lens-eval.json`, `lib/bench/README.md`, `lib/bench/tool.toml`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), `docs/implementation-notes/prompt-lens-eval.md`, this file.

Acceptance: one command reruns the SPEC-314 hand eval. It prints a per-case, per-signal table and a verdict, keeps every raw report, and spends nothing without `--live`.

| Check | Command | Exit | Result |
|---|---|---|---|
| Offline suite | `bash tests/test-lens-eval.sh` | 0 | `Passed: 62 / 62`, `All lens-eval tests passed.` |
| Red before build | the suite before `lib/bench/lens-eval.sh` existed | 1 | `Passed: 8 / 59`, `Failed: 51` |
| Block-scoring regression | the suite against the line scorer | 1 | `Passed: 57 / 60`; the multi-line Reviewer 7 finding missed |
| Negative control | `negctl.sh` with a tie counted as a hit | 0 | `Verdict: PASS`; the tie rows went red |
| Changed suites | `bash tests/run-all.sh --changed` | 0 | `run-all: all 36 suites passed, 0 skipped for missing tooling` |
| Self-review regressions | the suite against the script before the repeated-name and regex checks | 1 | `Passed: 59 / 62`; an invalid regex case file exited 0 |
| Dry run | `lens-eval.sh commands/spec-validate.md 118485af~1 tests/fixtures/sustainability-lens/lens-eval.json` | 3 | `plan: 2 cases, 1 samples per arm = 3 model calls (sonnet)` |
| Live run 1 | the same, `--live` | 1 | FAIL on `rotation-r7`: a scorer bug, fixed |
| Live run 2 | the same, `--live`, block scorer | 1 | FAIL on the quiet case: a lens finding, recorded below |

## Green run

```
Command: bash tests/test-lens-eval.sh
Exit: 0
Output: Passed: 62 / 62 / All lens-eval tests passed.
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output: run-all: all 36 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

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

## Limits

N=1 per arm on both live runs. The verdict shows what held on these samples, not a rate. The grep checks that a finding names a thing, not that the finding is right. A hung call has no timeout.
