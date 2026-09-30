# Proof of done: lanes as data, light default, diff floor at ship

Spec: `docs/specs/SPEC-368-lanes-as-data.md`. Branch `feat/lanes-as-data`. Every run below happened in the worktree with temp repos and a temp `DWARVES_KIT_LOG_DIR`; no test touched a real repo or the real ledger.

## Green runs

| Command | Exit | Result | Covers |
|---|---|---|---|
| `bash tests/test-lanes-data.sh` | 0 | 29 cases, all `PASS <name>` | AC2, AC4 to AC9, AC11 to AC20, AC23, AC24 |
| `bash lib/config/kit-config.sh selftest` | 0 | `PASS kit-config selftest`, includes `ok   last-dot split: lane.normal.phases` | AC10 |
| `bash tests/test-hooks.sh` | 0 | `Passed: 723 / 723` | AC22 |
| `bash tests/test-meta.sh` | 0 | `Passed: 886 / 886` | AC22 |
| `bash tests/test-lane-classify.sh` | 0 | `38/38 passed, 0 failed` | AC22 |
| `bash tests/test-lane-escalation.sh` | 0 | `24/24 passed, 0 failed` | AC22 |
| `bash tests/test-lane-deescalate.sh` | 0 | `22/22 passed, 0 failed` | AC22 |
| `bash tests/test-gate-ledger-plan-record.sh` | 0 | `41/41 passed` | AC22 |
| `bash tests/test-ship-gate-fail-closed.sh` | 0 | `PASS=7 FAIL=0` | AC22 |
| `bash tests/test-config.sh` | 0 | `PASS kit-config selftest` | AC22 |
| `bash lib/gate/doc-projection-check.sh .` | 0 | no output | AC (TASK-9) |
| `bash lib/registry/feature-registry.sh check docs/FEATURES.md` | 0 | fresh | AC (TASK-9) |

`bash tests/test-config-registry.sh` is red on `master` too: the drift lint lists `HARVEST_STATE_DIR`, `HARVEST_SWEEP_CHILD`, `KIT_WRAP_CI_GRACE_SECS` as unregistered, and the planted-orphan count follows. This change adds no orphan: its new `kit.toml` rows are registered and its new variables avoid the `KIT` seed prefix.

## Spec acceptance commands

| AC | Command | Output |
|---|---|---|
| AC1 | `bash tests/test-lanes-data.sh parity` at commit 486ee697 (extracted with `git archive`) | `PASS parity` |
| AC2 | `bash lib/gate/gate-ledger.sh required normal \| tr '\n' ' '` | `spec validate build review ship ` |
| AC2 | `bash tests/test-lanes-data.sh parity-after-flip` | `PASS parity-after-flip` (only normal `validate` and `review` lines differ) |
| AC3 | `grep -cE 'matrix_for_lane\|GATE_LEDGER_WORKFLOW' lib/gate/gate-ledger.sh` | `0` |
| AC9 | `KIT_CONFIG_ROOT=/tmp/evil DWARVES_KIT=/tmp/evil bash lib/gate/gate-ledger.sh required normal` | `spec validate build review ship` |
| AC11 | the four false-hit texts through `classify 2>&1 \| sort -u` | `normal` |
| AC13 | `classify --files "db/migrations/0001_users.sql" "add a users table migration" 2>/dev/null` | `full` |
| AC21 | `grep -c 'take the heavier one'` over the four files | `0` for each |

## Negative controls (run and observed)

Each row: the change was committed first, one file was broken, the named case ran RED, the file was restored with `git checkout -- <file>`, and the same case ran GREEN. The first column names the mutation.

| Control | Broken file | Broken run | Restored run |
|---|---|---|---|
| floor block removed from the hook | `hooks/ship-gate.sh` | `FAIL ship-migration-blocks: blocked rc=0` | `PASS ship-migration-blocks` |
| floor reads the head switch, not the merge base | `lib/gate/gate-policy.sh` | `FAIL ship-flip-gate-in-pr: rc=0` | `PASS ship-flip-gate-in-pr` |
| `check` ignores `--kit-lanes` | `lib/gate/gate-ledger.sh` | `FAIL ship-hollow-full-override: rc=0` | `PASS ship-hollow-full-override` |
| reader applies a dirty project file | `lib/gate/lane-data.sh` | `FAIL override-uncommitted: plan='grill spec build ship '` | `PASS override-uncommitted` |
| reader accepts an unknown phase | `lib/gate/lane-data.sh` | `FAIL override-typo: plans differ or stderr misses the phase` | `PASS override-typo` |
| kit root follows the environment | `lib/gate/lane-data.sh` | `FAIL pinned-root: required normal = 'spec build '` | `PASS pinned-root` |
| `token` regex widened back | `lib/classify/lane-classify.sh` | `FAIL four-false-hits: [add token count column => LANE-SUGGEST ...]` | `PASS four-false-hits` |
| `truncate` matches as a bare word | `lib/classify/lane-classify.sh` | `FAIL floor-data-loss: [# truncate long names ... should not hit]` | `PASS floor-data-loss` |
| WORKFLOW view drifts from the data | `docs/WORKFLOW.md` | `FAIL workflow-view: [normal: view=...]` | `PASS workflow-view` |
| last-dot split reverted to first-dot | `lib/config/kit-config.sh` | `FAIL last-dot split: lane.normal.phases: got []` and `SELFTEST FAILED` | `PASS kit-config selftest` |
| parity, tiny lane gains `docs` in the extracted refactor commit | `kit.toml` in the `git archive` copy | `FAIL parity: reader output differs from the baseline` | `PASS parity` on the untouched archive |

## Reproducible

Run `bash tests/test-lanes-data.sh` from a clean checkout of the branch. It builds its own temp repos and ledger dirs, so the run is repeatable and leaves nothing behind. Cases `parity` and `baseline` are the only ones not in the default run: `parity` holds only at the refactor commit, and `baseline` rewrites the captured baseline file.

## Not covered

Headless change, no visible surface. The proof gate's `stateful` over-fire is out of scope. Stale "take the heavier one" text remains in `docs/workflow-map.md`, `docs/guides/lanes.md`, and `examples/hello-spec/WORKFLOW.md`, which are outside the spec's Touches.
