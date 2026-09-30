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

## Review fixes (gate bypass, counter, WORKFLOW prose)

A review of the finished branch found three gaps. Each fix went test-first: the new assertions were run red, then the fix made them green.

| Finding | Fix | Tests |
|---|---|---|
| HIGH: `validate` is light on the normal lane, so a large normal-lane spec could ship unvalidated | `hooks/ship-gate.sh` blocks a normal-lane ship when `spec.sh depth size` exits 1 and the last `validate` GATE line is not `ran` or `override`. Exit 2 from `spec.sh` or a missing `spec.sh` fails open. | `tests/test-hooks.sh`: large with no validate blocked (exit 2, rule named, override hint printed), large with validate ran passes, large with override passes, small with no validate passes, large whose last validate is `skipped` blocked. 820 of 824 red before, 824 of 824 after. |
| MEDIUM: `count_tasks` missed real task shapes, so most specs read large | Counts `### TASK-N` headings, `- [ ] **TASK-N**`, indented `- [ ] TASK-N`, and the kit's own `T1` / `T2a` labels (`\| T1: x \|` rows, `- [ ] T1a: x`). `~~~` fences track like backtick fences and a backtick fence inside `~~~` does not close it. An odd fence-line count means one is unclosed, so fence state is ignored. CR is stripped. | `tests/test-spec-depth.sh size`: one assertion per format, unclosed fence, tilde, nested fence, CRLF, two mixed-format specs. 6 red before, 122 of 122 after. |
| MEDIUM: `docs/WORKFLOW.md` Depth paragraph said the validator runs at every depth | Reworded to the size rule. | `tests/test-meta.sh`: no stale phrase, size-rule phrase present. Both red before. |

Two collateral repairs. `hooks/codex-hooks.json` was already stale for all five pinned hooks on this branch base; `lib/codex/repin.sh` rewrote the pins, which also covers the `ship-gate.sh` change. `tests/test-codex-hooks.sh` "complete feature push is allowed" used a zero-task spec (now reads large) and a ledger with no `review` line; it now uses a one-task spec and records `review`. `docs/FEATURES.md` regenerated (`/kit:review` test-count drift).

### Corpus split, `spec.sh depth size` over `docs/specs/SPEC-3*.md`

| State | Small | Large | Tasks counted as 0 |
|---|---|---|---|
| Before the counter fix | 3 | 55 | 40 |
| After the counter fix | 4 | 54 | 13 |

The one new small spec is SPEC-353. Most formerly zero-task specs are full-lane or carry a deeper Depth and stay large; 13 have no task list at all and read large by design.

### Run table

| Command | Result |
|---|---|
| `bash tests/test-spec-depth.sh` | 122 passed, 0 failed |
| `bash tests/test-hooks.sh` | 824 of 824 |
| `bash tests/test-lanes-data.sh` | exit 0, 0 FAIL |
| `bash tests/test-codex-hooks.sh` | 94 passed, 0 failed |
| `bash tests/test-meta.sh` | 902 of 902 |
| `bash tests/test-gate-opt-out.sh` | 3 FAIL, identical with the original `hooks/ship-gate.sh`, so pre-existing |

### Negative controls (review fixes)

Each mutation was applied to a saved copy, the pinning suite run, and the file restored by copying the saved file back.

| Mutation | Suite | Result |
|---|---|---|
| `ignore = (nf % 2 == 1)` to `ignore = 0` | `test-spec-depth.sh size` | red: unclosed fence |
| `###` heading alternative removed | `test-spec-depth.sh size` | red: headings, mixed |
| `(\*\*)?` removed from the checkbox pattern | `test-spec-depth.sh size` | red: bold, mixed |
| `~~~` dropped from the fence pattern | `test-spec-depth.sh size` | red: tilde |
| `T[0-9]+` label alternative removed from the checkbox pattern | `test-spec-depth.sh size` | red: `- [ ] T1a:` |
| `"$SIZE_RC" -eq 1` to `-eq 9` in `hooks/ship-gate.sh` | `test-hooks.sh` | red: large-spec block, rule name, override hint, last-skipped |
| WORKFLOW size-rule sentence reverted | `test-meta.sh` | red: both new pins |
