# Proof of done: validate by size

## What changed

The 7-reviewer spec validation now runs only for LARGE specs. A spec is SMALL when its lane is `normal`, its `Depth:` is `standard` or absent, and it has 1 to 3 tasks. `bash lib/spec/spec.sh depth size <spec>` decides. A small spec records a Validate override and relies on the post-build review. `kit.toml` makes `validate` light on the normal lane. The battery review leg runs on Sonnet on the normal lane.

## Gate table

| Claim | Evidence |
|---|---|
| `size` prints small or large per rule S1 and exits 0 or 1 | `tests/test-spec-depth.sh` section `size`, 14 asserts |
| `/kit:spec` step 5 and the execute preflight name the size check and the override line | `tests/test-meta.sh`, 2 pins |
| the normal lane no longer requires `validate`; full, bug, backfill, tiny unchanged | `tests/test-lanes-data.sh` `plan-flip`, `pinned-root`, `parity-after-flip`, `workflow-view` |
| battery leg 2 is Sonnet on normal, Opus on full | `tests/test-meta.sh`, 1 pin |
| WORKFLOW prose says validation runs on large specs only | `tests/test-meta.sh`, 1 pin |
| the two hook pins on normal-lane validate follow the lane data | `tests/test-hooks.sh` 817 of 817 |

## Run table

| Command | Result |
|---|---|
| `bash tests/test-spec-depth.sh` | 106 passed, 0 failed |
| `bash tests/test-lanes-data.sh` | 58 PASS, 0 FAIL |
| `bash tests/test-meta.sh` | 900 of 900 |
| `bash tests/test-hooks.sh` | 817 of 817 |
| `bin/test-affected --base origin/master` | 3 suites fail, all three fail the same on a clean origin/master export: `test-gate-opt-out` (4 FAIL), `test-install-contract` (2), `test-research-arch-contract` (1) |

## Negative controls

Each mutation was applied to a saved copy, the pinning suite run, and the file restored by copying the saved file back. The worktree was clean after every control.

| Rule | Mutation | Suite | Result |
|---|---|---|---|
| S1 | task ceiling `-le 3` to `-le 9` | `test-spec-depth.sh size` | red: `4 tasks is large`, `checkbox plus table tasks add up` |
| S1 | zero-task guard `-ge 1` to `-ge 0` | `test-spec-depth.sh size` | red: `no countable task is large` |
| S1 | lane check removed | `test-spec-depth.sh size` | red: `full lane is large`, `bug lane is large` |
| S1 | depth check removed | `test-spec-depth.sh size` | red: `deeper Depth is large` |
| S2 | override line removed from `commands/spec.md` | the four new `test-meta.sh` pins | red: `spec.md step 5` pin |
| S2 | override line removed from `commands/execute.md` | the four new `test-meta.sh` pins | red: `execute.md preflight` pin |
| S2 | WORKFLOW "large specs only" text reverted (both lines) | the four new `test-meta.sh` pins | red: `WORKFLOW.md` pin |
| S3 | `validate` dropped from `[lane.normal] light` | `test-lanes-data.sh` | red: `plan-flip`, `workflow-view` |
| S3 | WORKFLOW Validate / normal cell back to `measure-twice` | `test-lanes-data.sh workflow-view` | red |
| S4 | battery leg 2 tier reverted to Opus | the four new `test-meta.sh` pins | red: `battery.md leg 2` pin |

Reverting only one of the two "large specs only" lines in `docs/WORKFLOW.md` leaves the WORKFLOW pin green, because the phrase appears on several lines. The control reverts every occurrence.

## Reproduce

```bash
bash tests/test-spec-depth.sh size
bash tests/test-lanes-data.sh plan-flip workflow-view pinned-root parity-after-flip
bash tests/test-meta.sh
bin/test-affected --base origin/master
```
