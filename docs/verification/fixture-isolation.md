# Proof of done: fixture-isolation (SPEC-103 / ID-087)

The test suite no longer writes to the operator's real `completeness.log`.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Running the full suite leaves the real `completeness.log` byte-unchanged (shasum before == after) | PASS |
| 2 | Negative control: the un-isolated `check` DOES write a LANE-CHECK line (isolation matters) | PASS |
| 3 | `tests/test-lane-escalation.sh` still passes (22/22) | PASS |

## Implementation

`tests/test-lane-escalation.sh`: file-wide `export DWARVES_KIT_LOG_DIR="$(mktemp -d ...)"` added
after the path setup, so the AC2 downgrade-guard `check` (line 67) writes to a throwaway dir. Sole
un-isolated writer; every other test `check` was verified isolated.

## Confirmation run-table

| Check | Command | Expected | Observed |
|---|---|---|---|
| shasum unchanged | shasum real log, run `tests/test-*.sh`, shasum again | equal | `d63f704…` == `d63f704…` -> CLEAN |
| escalation suite green | `bash tests/test-lane-escalation.sh` | 22/22 | 22/22 passed |
| negative control | `DWARVES_KIT_LOG_DIR=$tmp bash lib/lane-classify.sh check tiny "add user authentication with jwt sessions"` | writes a LANE-CHECK line to $tmp | `… | LANE-CHECK | downgrade | chosen=tiny suggested=full | add user authentication with jwt sessions` |

## Run detail (captured 2026-07-02)

```
real completeness.log BEFORE: d63f704b3bdfa6ff67d6f4229f288f6ffdf7441e  (14 lines)
run: for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1; done
real completeness.log AFTER:  d63f704b3bdfa6ff67d6f4229f288f6ffdf7441e
RESULT: CLEAN (byte-unchanged)

negative control (un-isolated check, isolated to a temp "real" dir):
2026-07-02T14:50:01Z | LANE-CHECK | downgrade | chosen=tiny suggested=full | add user authentication with jwt sessions
```

## Reproduce

```bash
cd dwarves-kit
L=~/.local/state/dwarves-kit/logs/completeness.log; a=$(shasum "$L")
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1; done
b=$(shasum "$L"); [ "$a" = "$b" ] && echo CLEAN || echo POLLUTED
```

Note: the 12 already-leaked `LANE-CHECK ... "jwt sessions"` lines are NOT cleaned by this fix (a
one-off operator action, out of scope). Going forward the suite adds none.
