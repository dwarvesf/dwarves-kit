# Verification -- board-backward-notice

`backlog.sh set` prints `board set: <ID> moves back from '<from>' to '<to>'` on stderr when both states are `active` and the target sits earlier in `states.tsv`. It still writes; stdout and exit codes are unchanged. Hermes writeback now keeps that stderr text in its report and its commit body.

| Check | Command | Result |
|---|---|---|
| Declared-states suite | `bash tests/test-board-states.sh` | 32 PASS, 0 FAIL |
| Writeback suite | `bash tests/test-board-writeback.sh` | 74 PASS, 0 FAIL, 1 SKIP |
| Caller suites | set-note, board, file-guard, atomic-mint, hooks, operator-pin, config-registry | all green |
| Negative control | restore the base `backlog.sh` and `board-writeback.sh` | 2 FAIL in states, 2 FAIL in writeback; restored |

## Green runs

```
Command: bash tests/test-board-states.sh
Exit: 0
Output:
  PASS states --class bogus exits 64
  PASS native-map.tsv rows are well-formed and name declared states
  PASS board-mirror _target_native = native-map.tsv
  PASS board-mirror-cleanup ACTIVE_TARGET = native-map.tsv
  PASS an added map row reaches bash and python with no other edit
  PASS no code file hardcodes the row-to-card map
  PASS map copy detector catches a planted copy
  All board-states tests passed.
Verdict: PASS
```

```
Command: bash tests/test-board-writeback.sh
Exit: 0
Output:
    PASS BK: the commit body records the backward notice
  
  === Static security audit: argv-safety, no eval/sh-c, no direct DB access ===
    PASS board-writeback.sh never eval/sh-c's a parsed variable
    PASS board-writeback.sh never references a .db/sqlite path in code
    PASS board-writeback.sh calls gh pr create with discrete argv (--title/--body-file), never a composed string
  
  === Coverage delta ===
    PASS coverage delta: board-writeback checks went from 0 to 74 in this suite
  
    ---------------------------------------------
    TOTAL: 75   PASS: 74   FAIL: 0   SKIP: 1
Verdict: PASS
```

```
Command: bash tests/test-board-set-note.sh
Exit: 0
Output:
  PASS quoted multi-word note still works: shipped [fixed in console-labs #233]
  PASS dedupe on an absent id reports: no Active-queue row for ID-999
  PASS dedupe on an absent id wrote nothing
  ALL PASS
Verdict: PASS
```

```
Command: bash tests/test-board.sh
Exit: 0
Output:
  
    ---------------------------------------------
    TOTAL: 63   PASS: 62   FAIL: 0   SKIP: 1
Verdict: PASS
```

```
Command: bash tests/test-board-file-guard.sh
Exit: 0
Output:
  PASS set on a missing BACKLOG_FILE exits 1 and names the variable
  PASS states does not need BACKLOG_FILE to exist
  ALL PASS
Verdict: PASS
```

```
Command: bash tests/test-board-atomic-mint.sh
Exit: 0
Output:
    PASS the set still landed (ID-1 flipped)
  
  atomic-mint: 14/14 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-hooks.sh
Exit: 0
Output:
  
  === Results ===
  Passed: 830 / 830
  All tests passed.
Verdict: PASS
```

```
Command: bash tests/test-operator-pin.sh
Exit: 0
Output:
    PASS  bin/test-affected pins KIT_CONFIG_OPERATOR for the suites it starts
  
  operator-pin: 4 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-config-registry.sh
Exit: 0
Output:
    PASS config explain precedent.registry never reports source: project .kit.toml
  
  === 60/60 passed ===
Verdict: PASS
```

## Negative control

Base `lib/board/backlog.sh` and `lib/board/board-writeback.sh` restored over the branch (`git show <merge-base>:<file>`), then both new-test suites run. Restored with `git checkout -- <file>`; both suites green again.

```
Command: bash tests/test-board-states.sh   (base scripts in place)
Exit: 1
Output:
  FAIL backward notice: 
  FAIL swapped table notice: 
  2 board-states test(s) failed.
Verdict: PASS (the control went red)
```

```
Command: bash tests/test-board-writeback.sh   (base scripts in place)
Exit: 1
Output:
    FAIL BK: the stderr report carries the backward notice for ID-601
    FAIL BK: the commit body records the backward notice
    TOTAL: 75   PASS: 72   FAIL: 2   SKIP: 1
Verdict: PASS (the control went red)
```
