# Verification: a `complete` on a gone or terminal card records done

Change: `lib/board/board-mirror.sh` `cmd_apply_plan`, plus test NC8 in `tests/test-board-mirror.sh`.
Source incident: ops-toolkit ID-727, every hourly `board-sync-all` mirror tick on the Mini ended
`applied 0 create, 0 change, 0 complete, 58 error(s)`, all `cannot complete t_... (unknown id or
terminal state)` for shipped rows whose snapshot card id no longer exists in the pinned personal
Hermes store.

## Green run

Command: `bash tests/test-board-mirror.sh` (worktree at commit d2e4899).

```
=== NC8: a 'complete' op failing with 'unknown id or terminal state' records ok/done, not error ===
  PASS NC8: a dead-card complete is reported status:ok
  PASS NC8: a dead-card complete is reported hermes_status:done
  PASS NC8: a dead-card complete preserves the origin
  PASS NC8: any OTHER complete failure still reports status:error
  TOTAL: 76   PASS: 76   FAIL: 0   SKIP: 0
```

Sibling suites, same tree: `tests/test-board.sh` 36 PASS 0 FAIL 1 SKIP (pre-existing skip),
`tests/test-board-writeback.sh` 53 PASS 0 FAIL 1 SKIP (pre-existing skip).

Verdict: PASS

## NEGATIVE CONTROL

The same suite with `lib/board/board-mirror.sh` reverted to `origin/master` (fix removed, test kept):

```
  FAIL NC8: a dead-card complete is reported status:ok
  FAIL NC8: a dead-card complete is reported hermes_status:done
  PASS NC8: a dead-card complete preserves the origin
  PASS NC8: any OTHER complete failure still reports status:error
  TOTAL: 76   PASS: 74   FAIL: 2   SKIP: 0
```

The two assertions that encode the fix fail without it; the other-failure assertion passes on both
trees, which shows the error path is untouched.

## Reproducible

`bash tests/test-board-mirror.sh` from the repo root. The live confirmation is the next
`board-sync-all` tick on the Mini after the kit checkout there fast-forwards: the mirror line must
read `0 error(s)` and the snapshot must no longer carry the shipped rows' origins.

## Rollback

Revert the commit. The snapshot lines already dropped by the fix stay dropped; the rows they named
are shipped, and shipped rows are never re-created by the mirror (`status 'shipped' not bridged`),
so nothing regresses on revert.
