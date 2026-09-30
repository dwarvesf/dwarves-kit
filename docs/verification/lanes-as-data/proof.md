# Proof of done: lanes as data, light default, diff floor at ship

Spec: `docs/specs/SPEC-368-lanes-as-data.md`. Branch `feat/lanes-as-data`. Every run below happened in the worktree with temp repos and a temp `DWARVES_KIT_LOG_DIR`; no test touched a real repo or the real ledger.

## Green runs

| Command | Exit | Result | Covers |
|---|---|---|---|
| `bash tests/test-lanes-data.sh` | 0 | 54 cases, all `PASS <name>` (`floor-timing-30k`: 1.9 s idle, 4.0 s under load, limit 5 s) | AC2, AC4 to AC9, AC11 to AC20, AC23, AC24, review fixes |
| `bash lib/config/kit-config.sh selftest` | 0 | `PASS kit-config selftest`, includes `ok   last-dot split: lane.normal.phases` | AC10 |
| `bash tests/test-hooks.sh` | 0 | `Passed: 725 / 725` | AC22 |
| `bash tests/test-meta.sh` | 0 | `Passed: 887 / 887` | AC22 |
| `bash tests/test-lane-classify.sh` | 0 | `38/38 passed, 0 failed` | AC22 |
| `bash tests/test-lane-escalation.sh` | 0 | `24/24 passed, 0 failed` | AC22 |
| `bash tests/test-lane-deescalate.sh` | 0 | `22/22 passed, 0 failed` | AC22 |
| `bash tests/test-gate-ledger-plan-record.sh` | 0 | `41/41 passed` | AC22 |
| `bash tests/test-ship-gate-fail-closed.sh` | 0 | `PASS=7 FAIL=0` | AC22 |
| `bash tests/test-significance-classify.sh` | 0 | `25/25 passed, 0 failed` | review fix |
| `bash tests/test-harvest-sweep.sh` | 0 | `Passed: 598 / 598` | review fix |
| `bash tests/test-ledger-durability.sh` | 0 | `37/37 passed, 0 failed` | review fix |
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

### Review-round controls

Same procedure. The floor timing case runs 1000 changed paths with 20000 added lines and the hard path last: about 0.3 s with the single-pass floor, 25 to 70 s with per-path matching.

| Control | Broken file | Broken run | Restored run |
|---|---|---|---|
| per-path matching restored | `lib/classify/lane-classify.sh` | `FAIL floor-timing: elapsed=25325ms (limit 2000ms)` | `PASS floor-timing (176ms for 1000 paths)` |
| ship-gate hook timeout back to 5s | `hooks/hooks.json` | `FAIL hook-timeout: ship-gate timeout under 30s` | `PASS hook-timeout` |
| quotePath default (octal names) | `lib/classify/lane-classify.sh` | `FAIL floor-non-ascii: [DROP TABLE in migré.py => 'full data-loss: app/migr\303\251.py']` | `PASS floor-non-ascii` |
| quoted `+++` header not unquoted | `lib/classify/lane-classify.sh` | `FAIL floor-non-ascii: [... quote => 'full data-loss: "b/app/q\"x.py"']` | `PASS floor-non-ascii` |
| auth narrowed, .github narrowed, gitlink dropped, one-space SQL, WHERE 1=1, quoted TRUNCATE, infra kind | `lib/classify/lane-classify.sh` | `FAIL floor-paths` / `floor-data-loss` / `floor-submodule` naming each missed case | each `PASS` |
| empty-phases guard removed | `lib/gate/lane-data.sh` | `FAIL override-empty-phases: required full = ''` | `PASS override-empty-phases` |
| kit mode reads the operator overlay | `lib/gate/lane-data.sh` | `FAIL ship-operator-hollow-full: rc=0` | `PASS ship-operator-hollow-full` |
| any lane name accepted | `lib/gate/lane-data.sh` | `FAIL override-unknown-lane-name` | `PASS override-unknown-lane-name` |
| target = any main or master word again | `hooks/ship-gate.sh` | `FAIL ship-push-forms: [want 2 got 0: gh pr create --base master --fill] ...` | `PASS ship-push-forms` |
| `--force` matched as a substring | `hooks/ship-gate.sh` | `FAIL ship-push-forms: [want 2 got 0: git push --force-with-lease ...]` | `PASS ship-push-forms` |
| `git -C dir` ignored | `hooks/ship-gate.sh` | `FAIL ship-push-forms: [git -C <dir> push from elsewhere: rc=0]` | `PASS ship-push-forms` |
| spec-less push no longer blocks | `hooks/ship-gate.sh` | `FAIL ship-no-spec-blocks: no-spec rc=0` | `PASS ship-no-spec-blocks` |
| base = local branch | `hooks/ship-gate.sh` | `FAIL ship-base-is-origin-head: rc=0` | `PASS ship-base-is-origin-head` |
| diff HEAD, not the pushed ref | `hooks/ship-gate.sh` | `FAIL ship-checks-pushed-ref: rc=0` | `PASS ship-checks-pushed-ref` |
| slug unquoted in the hint | `hooks/ship-gate.sh` | `FAIL ship-slug-quoted` | `PASS ship-slug-quoted` |
| `risk` drops the suggestion | `lib/classify/lane-classify.sh` | `FAIL risk-verb: [add jwt authentication => normal, want full]` | `PASS risk-verb` |
| significance back on classify | `lib/classify/significance-classify.sh` | `FAIL significance-uses-risk: not-significant` | `PASS significance-uses-risk` |
| RETURN trap reintroduced | `lib/classify/lane-classify.sh` | `FAIL floor-no-leaks: RETURN trap left set` | `PASS floor-no-leaks` |
| tracked-clean helper always true | `lib/config/kit-config.sh` | `FAIL override-uncommitted` | `PASS override-uncommitted` |
| show_at reads the working tree | `lib/config/kit-config.sh` | `FAIL ship-flip-gate-in-pr: rc=0` | `PASS ship-flip-gate-in-pr` |
| backslash back in `.kit.toml` | `.kit.toml` | `FAIL toml-valid: Unescaped '\' in a string` | `PASS toml-valid` |
| merge-base recomputed in the floor | `hooks/ship-gate.sh` | `FAIL ship-merge-base-once: [merge-base ran 2 times, want 1]` | `PASS ship-merge-base-once` |
| diff scan before the switch check | `hooks/ship-gate.sh` | `FAIL ship-merge-base-once: [switch off but the diff scan ran 1 times]` | `PASS ship-merge-base-once` |
| operator over project order swapped | `lib/gate/lane-data.sh` | `FAIL override-operator-precedence` | `PASS override-operator-precedence` |
| project `[lanes] default` ignored, invalid default not validated | `lib/gate/lane-data.sh` | `FAIL default-lane-layers` (both) | `PASS default-lane-layers` |
| dropped-phase dedupe removed | `lib/gate/gate-ledger.sh` | `FAIL start-no-duplicate-skips: appears 2 times` | `PASS start-no-duplicate-skips` |

### Second review round controls

Where two defenses guard one behavior, the control breaks both, so the case cannot pass on the spare.

| Control | Broken file | Broken run | Restored run |
|---|---|---|---|
| second push segment dropped from the count | `lib/gate/push-refs.sh` | `FAIL ship-fail-closed-refs: [want 2 got 0: git push origin feat/evil && git push origin feat/x]` | `PASS ship-fail-closed-refs` |
| several branches allowed | `hooks/ship-gate.sh` | `FAIL ship-fail-closed-refs: [want 2 got 0: git push origin feat/x feat/evil]` | `PASS ship-fail-closed-refs` |
| gh `--head` ignored | `lib/gate/push-refs.sh` | `FAIL ship-fail-closed-refs: [want 2 got 0: gh pr create --head feat/evil --fill]` | `PASS ship-fail-closed-refs` |
| `--all` and unknown options accepted | `lib/gate/push-refs.sh` | `FAIL ... [want 2 got 0: git push --all origin]` | `PASS` |
| unresolvable source accepted, no-answer guard off | `hooks/ship-gate.sh`, `lib/gate/push-refs.sh` | `FAIL ... [want 2 got 0: git push origin nothere]` | `PASS` |
| wrapper accepted, guard off | same two files | `FAIL ... [want 2 got 0: xargs git push origin]` | `PASS` |
| `--git-dir path` space form accepted, guard off | same two files | `FAIL ... [want 2 got 0: git --git-dir .git push origin feat/x]` | `PASS` |
| variables accepted, resolve and guard off | same two files | `FAIL ... [want 2 got 0: git push origin $BRANCH]` | `PASS` |
| scan without `--text` | `lib/classify/lane-classify.sh` | `FAIL floor-diff-hardening: [attrs => '']` | `PASS floor-diff-hardening` |
| repo prefix config trusted | `lib/classify/lane-classify.sh` | `FAIL floor-diff-hardening: [dstprefix => '']` | `PASS floor-diff-hardening` |
| external diff trusted | `lib/classify/lane-classify.sh` | `FAIL floor-diff-hardening: [external => '']` | `PASS floor-diff-hardening` |
| color not disabled | `lib/classify/lane-classify.sh` | `FAIL floor-diff-hardening: [color => '']` | `PASS floor-diff-hardening` |
| `+++` always read as a header | `lib/classify/lane-classify.sh` | `FAIL floor-plus-line: got ''` | `PASS floor-plus-line` |
| where matched in the whole record | `lib/classify/lane-classify.sh` | `FAIL floor-where-boundary: [DELETE FROM users in app/nowhere.py => '']` | `PASS floor-where-boundary` |
| tiny accepted as default | `lib/gate/lane-data.sh` | `FAIL default-rejects-tiny: classify => 'tiny'` | `PASS default-rejects-tiny` |

The 30000-file case (`floor-timing-30k`) measures about 2 s against a 5 s limit. It has no negative control of its own: the per-path slow-path control on `floor-timing` (1000 paths) covers the same mechanism, and a 30000-path slow run takes many minutes.

### Final round controls

| Control | Broken file | Broken run | Restored run |
|---|---|---|---|
| combined short flags not blocked | `hooks/safety-gate.sh` | `FAIL safety-push-forms: [want 2 got 0: git push -fu origin feat/x] [... -uf ...]` | `PASS safety-push-forms` |
| destination not normalized | `hooks/safety-gate.sh` | `FAIL safety-push-forms: [want 2 got 0: git push origin feat/x:refs/heads/main] ...` | `PASS safety-push-forms` |
| continuation join removed (safety-gate) | `hooks/safety-gate.sh` | `FAIL safety-push-forms: [line continuation before -f: rc=0]` | `PASS safety-push-forms` |
| substring marker match | `hooks/ship-gate.sh` | `FAIL ship-marker-collisions: [want 2 got 0: git push origin feat/DEFAULT-x] ...` | `PASS ship-marker-collisions` |
| continuation join removed (ship-gate) | `hooks/ship-gate.sh` | `FAIL ship-continuation-and-heredoc: [line continuation: rc=0]` | `PASS ship-continuation-and-heredoc` |
| shell heredoc not refused | `hooks/ship-gate.sh` | `FAIL ship-continuation-and-heredoc: [bash -s heredoc: rc=0] [sh here-string: rc=0]` | `PASS ship-continuation-and-heredoc` |
| marker read from the working tree | `hooks/ship-gate.sh` | `FAIL ship-marker-at-base: marker removed from the tree switched the rule off: rc=0` | `PASS ship-marker-at-base` |

## Reproducible

Run `bash tests/test-lanes-data.sh` from a clean checkout of the branch. It builds its own temp repos and ledger dirs, so the run is repeatable and leaves nothing behind. Cases `parity` and `baseline` are the only ones not in the default run: `parity` holds only at the refactor commit, and `baseline` rewrites the captured baseline file.

## Not covered

Headless change, no visible surface. The proof gate's `stateful` over-fire is out of scope. Stale "take the heavier one" text remains in `docs/workflow-map.md`, `docs/guides/lanes.md`, and `examples/hello-spec/WORKFLOW.md`, which are outside the spec's Touches.
