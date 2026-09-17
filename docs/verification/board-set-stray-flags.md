# Proof of done: backlog.sh set refuses a stray flag in the note

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | `set` refuses any argument after the note position, exit 64, writes nothing | `test-board-set-note.sh` case 15 |
| AC2 | `set` refuses a note argument that starts with `--`, exit 64, writes nothing | `test-board-set-note.sh` case 15 |
| AC3 | a legitimately multi-word QUOTED note still works unchanged | `test-board-set-note.sh` case 16 |
| AC4 | `bin/board set <ID> <state> [note] --backlog-file <path>` still works (board.sh strips the flag before backlog.sh sees argv) | `test-board.sh` AC5 (trailing-flag case) |
| AC5 | no regression to existing `set`/`dedupe` note-stacking or duplicate-id behavior | `test-board-set-note.sh` full suite green |

## Root cause

`lib/board/backlog.sh:91-92` (pre-fix): `set_state()` collected the note as
`local note="${*:-}"`, joining every remaining positional argument with spaces. A
consumer's root `board` wrapper forwards straight to `backlog.sh` and does not parse
`--backlog-file`; when an agent ran `board set CL-056 shipped "<note>" --backlog-file
<path>` against that wrapper, the literal text `--backlog-file <path>` was silently
folded into the note and written to the row (the 2026-09-17 console-labs CL-056
incident, repaired in console-labs#233).

## Fix

`lib/board/backlog.sh` `set_state()` now walks the remaining args before building the
note: any arg starting with `--`, or any arg beyond the single note position, returns 64
with a stderr message naming the stray argument, and writes nothing. `bin/board set`
(the kit's own entrypoint) is unaffected: `lib/board/board.sh`'s `_parse_flags` strips
`--backlog-file` out of argv before calling `backlog.sh`, regardless of where the flag
sits in the command line.

## Recorded run

RED (test written first, before the fix):
```
Command: bash tests/test-board-set-note.sh
FAIL set with a trailing --backlog-file should exit nonzero, got 0
FAIL set with a stray flag should not touch the file
2 FAILED
```

GREEN (after the fix):
```
Command: bash tests/test-board-set-note.sh
... (14 pre-existing PASS lines unchanged)
PASS set refuses the stray flag: backlog.sh set: stray argument after the note:
  '--backlog-file' (set takes <ID-NNN> <state> [note] only)
PASS set with a stray flag wrote nothing
PASS quoted multi-word note still works: shipped [fixed in console-labs #233]
ALL PASS
```

`bin/board set ... --backlog-file <path>` regression coverage:
```
Command: bash tests/test-board.sh
PASS single set flips DF-001 to claimed
PASS trailing --backlog-file flips DF-001 to shipped
PASS trailing --backlog-file leaves no stray flag text in the row
...
TOTAL: 51   PASS: 50   FAIL: 0   SKIP: 1   (SKIP: NC-e, ops-toolkit path absent, expected outside that checkout)
```

NEGATIVE CONTROL (`lib/gate/negctl.sh`, mutation = revert `lib/board/backlog.sh` to the
pre-fix commit):
```
Command: bash tests/test-board-set-note.sh && bash tests/test-board.sh
Exit: 0 (green before mutation)
Mutation: revert lib/board/backlog.sh to HEAD~1
Changed: lib/board/backlog.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/board/backlog.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Rollback

Single-file behavioral change (`lib/board/backlog.sh`), plus test-only additions to
`tests/test-board-set-note.sh` and `tests/test-board.sh`. Revert the commit to restore
the prior (bug-carrying) note-joining behavior; no config or data migration involved.
