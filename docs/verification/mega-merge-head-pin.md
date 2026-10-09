# Proof of done: mega-merge head pin

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | The merge is pinned to the head read first | `head-pin-passed` in `tests/test-mega-merge.sh`: fake `gh` records `pr merge 1 --squash --delete-branch --match-head-commit <sha>`; the DRY-RUN and per-pr-review lines print the same command | PASS |
| AC2 [NC] | An unreadable head refuses | `head-unreadable-refused`: exit 1, empty output, a short value, two valid-SHA lines, a trailing `\r`, uppercase hex; each returns nonzero, names `cannot read PR #1 head commit`, records no `pr merge` | PASS |
| AC3 [NC] | The head is read before the guards | `head-read-first`: shared call log across the head, state and files stubs lists `head` first | PASS |
| AC4 [NC] | A moved head fails the merge | `head-moved-fails`: fake `gh` refuses a `--match-head-commit` that differs from its current-head file; `merge --execute` returns nonzero and no branch delete is recorded | PASS |
| AC5 | Docs match | `module-registry.md` row, `SECURITY.md` sentence and CHANGELOG line present; `test-meta.sh` and `doc-projection-check.sh` pass | PASS |

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-mega-merge.sh` | 0 | 54/54 passed |
| `bash tests/test-mega-reconcile.sh` | 0 | 35/35 passed |
| `bash tests/test-meta.sh` | 0 | 902/902 passed |
| `bash lib/gate/doc-projection-check.sh .` | 0 | no drift |
| `bash tests/test-ledger-durability.sh` | 0 | 37/37 passed |
| `bash tests/test-goal-dispatch.sh` | 0 | 20/20 passed |
| `bash tests/test-mega-gate-parity.sh` | 0 | PASS=12 FAIL=0 |
| `bash tests/test-orchestrate-gate-dispatch.sh` | 0 | ALL PASS |
| `bash tests/test-lane-classify.sh` | 0 | 38/38 passed |
| `bash tests/test-tier4-close.sh` | 0 | ALL PASS |

## Negative controls

The new cases were committed first and run against the old code: 12 of the 54 cases went RED (every `head-*` case except the "returns 0 when the head still matches" leg), then GREEN after the fix.

One control through `lib/gate/negctl.sh`: the mutation moves the `_pr_head` read to after `_merge_config_guard`.

```
Command: bash tests/test-mega-merge.sh
Exit: 0 (green before mutation)
  === 54/54 passed, 0 failed ===

Mutation: python3 mut.py   (moves the head read below the guards)
Changed: lib/goal/mega-merge.sh
Exit: 1 (under mutation, RED expected)
  FAIL head-read-first: the head is read before the state and the file list
  === 53/54 passed, 1 failed ===

Restore: git checkout HEAD -- lib/goal/mega-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

Server-side enforcement. The tests prove the pin is passed to `gh pr merge` and that a refusal propagates as a nonzero return. That GitHub refuses a merge whose head moved rests on the documented `--match-head-commit` behavior; no test pushes to a real PR. The gate's diff rules still read the orchestrator checkout's local `HEAD` (out of scope, SPEC-402).

## Reproduce

```
bash tests/test-mega-merge.sh && bash tests/test-mega-reconcile.sh
```
