# Proof of done: one writer for the board and the staging buffer

Verdict: PASS

Lane: normal. Fixes drift rows 27, 28, 29, 32, 34 and the two ranked risks "the board has no single writer" and "staging has two lock domains". Choices the brief left open are in `docs/implementation-notes/board-one-writer.md`.

## What was proven

| Claim | Evidence |
|---|---|
| Eight concurrent `backlog.sh add` calls mint eight unique ids and lose no row | `tests/test-board-add.sh` AC1; negative control below |
| A row takes the target table's own column count (4 and 6), and `lint` judges each table against its own header | `tests/test-board-add.sh` AC2, AC3; negative control below |
| `capture` and `promote` write through the same verb | `tests/test-board-add.sh` AC6, `tests/test-board-atomic-mint.sh` (14/14) |
| While one process holds the staging lock, `append`, `drain` and `promote` all wait | `tests/test-staging-one-writer.sh` AC1b (deterministic); negative control below |
| Promote racing 25 appenders loses no appended block, three rounds | `tests/test-staging-one-writer.sh` AC2 |
| A block that changed after it was listed is skipped, not minted | `tests/test-staging-one-writer.sh` AC4 |
| The bash hooks reach the locked path; without python3 they still stage | AC5, AC6, AC7 of the same suite; both parity suites below |
| No new raw python append to the buffer appears | `KNOWN_RAW` guard in AC5 (three named files outside this slice) |

## Green runs

Command: `bash tests/test-board-add.sh`
Exit: 0
Output: `== 40 run, 40 passed, 0 failed ==`

Command: `bash tests/test-staging-one-writer.sh`
Exit: 0
Output: `== 28 run, 28 passed, 0 failed ==`

Command: `bash tests/test-board-promote.sh; bash tests/test-board-atomic-mint.sh; bash tests/test-board-lint.sh; bash tests/test-staging-stage.sh; bash tests/test-reflect-drain.sh; bash tests/test-staging-format-jq.sh`
Exit: 0
Output:

```
test-board-promote:      == 34 run, 34 passed, 0 failed ==
test-board-atomic-mint:  atomic-mint: 14/14 passed, 0 failed
test-board-lint:         all lint tests passed
test-staging-stage:      == 33 run, 33 passed, 0 failed ==
test-reflect-drain:      TOTAL: 23   PASS: 23   FAIL: 0
test-staging-format-jq:  staging-format-jq: 5 passed, 0 failed
```

Command: `bash tests/run-all.sh --changed --time` (65 suites; host load average above 150 while it ran)
Exit: 1, one red and one timeout, both re-run alone below
Output (tail):

```
test-intake-sweep-parity                       ok (90s)
test-kit-contract                              ok (14s)
test-meta-docs-registry                        FAIL (rc=1) (38s)
      !   FAIL docs/FEATURES.md is fresh (check verb, SPEC-219)
test-reflect-drain                             ok (2s)
test-staging-one-writer                        ok (20s)
test-web-drift-refusal-guard                   ok (0s)
run-all: FAILED -> test-meta-docs-registry
run-all: TIMED OUT at 300s -> test-config-registry(164s)
run-all: 65 suites run, 0 skipped for missing tooling
```

`test-meta-docs-registry` failed because the generated `docs/FEATURES.md` counts the new suites. After `feature-registry.sh check --fix docs/FEATURES.md` (the regenerated file is its own commit):

Command: `bash tests/test-meta-docs-registry.sh; RUN_ALL_TIMEOUT_SECS=900 bash tests/run-all.sh --only test-config-registry`
Exit: 0
Output:

```
Passed: 120 / 120
All meta tests passed.
test-config-registry                           ok
run-all: all 1 suites passed, 0 skipped for missing tooling
```

The `test-backlog-stage-parity` suite reports `backlog-stage parity: 204 passed, 0 failed`, and `test-intake-sweep-parity` reports `intake-sweep parity: 160 passed, 0 failed`. One line in the first suite, `2 MB transcript, inline`, hit its 60 s alarm under the load above in two of three runs. Run by hand with a 170 s alarm it took 72 s wall at 2 percent CPU and staged the candidate, so it measures the host, not this change.

The first parity run failed 114 and 85 cases for a real reason: the first draft kept `<staging>.lock` beside the buffer, and every hook run left a stray lock file in the consumer checkout, which the parity goldens list. The lock moved to the tmpdir (same scheme as the board lock) and both suites went green.

## Negative controls

Each mutation was committed-clean first, run RED, restored, and shown green again (`lib/gate/negctl.sh`).

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-staging-one-writer.sh" "sed -i '' 's/fcntl.flock(lockf, fcntl.LOCK_EX)/pass/' lib/reflect/staging-format.py"`
Exit: 1 (under mutation, RED expected)
Output:

```
Mutation: sed -i '' 's/fcntl.flock(lockf, fcntl.LOCK_EX)/pass/' lib/reflect/staging-format.py
Changed: lib/reflect/staging-format.py
Exit: 1 (under mutation, RED expected)
  == 28 run, 27 passed, 1 failed ==
Restore: git checkout HEAD -- lib/reflect/staging-format.py
Exit: 0 (green after restore)
Verdict: PASS
```

The same mutation applied by hand, to name the red lines (then restored with `git checkout HEAD --`):

```
  FAIL buffer untouched while the lock is held (append, drain and promote all waited)
  FAIL after release: drain expired the old block
  == 28 run, 26 passed, 2 failed ==
```

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-add.sh" "sed -i '' 's/    ncols = column_count(lines\[table\[0\]\])/    ncols = 4/' lib/board/board_add.py"`
Exit: 1 (under mutation, RED expected)
Output:

```
Mutation: sed -i '' 's/    ncols = column_count(lines\[table\[0\]\])/    ncols = 4/' lib/board/board_add.py
Changed: lib/board/board_add.py
    FAIL promote: its row has 6 cells
    FAIL promote: lint clean on the board after both writers
  == 40 run, 31 passed, 9 failed ==
Restore: git checkout HEAD -- lib/board/board_add.py
Exit: 0 (green after restore)
```

(the two FAIL lines above are the last two of the nine)

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-board-add.sh" "sed -i '' 's/    with board_lock(path):/    if True:/' lib/board/board_add.py"`
Exit: 1 (under mutation, RED expected)
Output:

```
Mutation: sed -i '' 's/    with board_lock(path):/    if True:/' lib/board/board_add.py
Changed: lib/board/board_add.py
  == 40 run, 38 passed, 2 failed ==
Restore: git checkout HEAD -- lib/board/board_add.py
Exit: 0 (green after restore)
```

The race test AC2 (promote against appenders) is probabilistic: with the lock removed it lost 3 appended blocks in one run and none in another. AC1b is the deterministic proof, and AC2 is kept as the end-to-end shape of the original bug.

## Not proven

- The three proposers outside this slice's file fence (`reflect propose --retro`, `session audit`, `session intel`) still append without the lock; the guard names them.
- `sync intake` still mints in `sync_core`, under the same board lock; it was not routed through `add`.
- Two stage hooks that dedupe against a snapshot and then append can still both stage one title; only the append is atomic.
- The kit's own `_meta/BACKLOG.md` carries 259 four-cell rows under its six-column Active queue header. `lint` now reports them; they were not rewritten.
- Hosts where two writers run with different `TMPDIR` values hold different lock files, the same limit the board lock has.

## Rollback

`git revert` the three commits on `fix/board-one-writer`. No data migration: the verb and the lock change who writes, not the file formats.
