# Proof of done: backlog.sh guards a missing BACKLOG_FILE

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | a missing/unreadable BACKLOG_FILE exits 1, not awk's generic exit 2 | `test-board-file-guard.sh` cases 1-2 |
| AC2 | the stderr message names the BACKLOG_FILE variable and the path | `test-board-file-guard.sh` case 1 (`grep -q BACKLOG_FILE`, `grep -qF "$MISSING"`) |
| AC3 | the guard sits once, upstream of the verb dispatch, not duplicated per verb | `board` and `set` both refuse before touching the file (case 1, case 2) |
| AC4 | `states` still works with no BACKLOG_FILE on disk (it never reads the file) | `test-board-file-guard.sh` case 3 |
| AC5 | no regression to existing board/dedupe behavior | full suite green (below) |

## Recorded run

```
Command: bash tests/test-board-file-guard.sh
Exit: 0
PASS board on a missing BACKLOG_FILE exits 1 and names the variable
PASS set on a missing BACKLOG_FILE exits 1 and names the variable
PASS states does not need BACKLOG_FILE to exist
ALL PASS

Command: bash tests/run-all.sh
Exit: 0
run-all: all 145 suites passed, 1 skipped for missing tooling
```

`test-config-registry.sh` is flagged as load-flaky under concurrent sessions. It passed
inside the full run above and was also re-run standalone as a second confirmation:

```
Command: bash tests/test-config-registry.sh
Exit: 0
=== 50/50 passed ===
```

No flake observed in either run.

NEGATIVE CONTROL: replacing `lib/board/backlog.sh` with the pre-fix version (guard
removed) makes `test-board-file-guard.sh` fail red exactly as the reported bug: `board`
dies with `awk: can't open file <path>` at exit 2, and `set` fails on the same missing
file with a grep error instead of a clear message. Restoring the fixed file returns the
suite to green. Verdict: PASS.

```
Command: bash tests/test-board-file-guard.sh   (pre-fix backlog.sh)
Exit: 1
FAIL board on a missing BACKLOG_FILE: rc=2 out=[awk: can't open file .../does-not-exist.md
 source line number 7]
FAIL set on a missing BACKLOG_FILE: rc=1 out=[grep: .../does-not-exist.md: No such file or directory
no Active-queue row for ID-001]
PASS states does not need BACKLOG_FILE to exist
2 FAILED
```

## Rollback

Single-file change (`lib/board/backlog.sh`), no config or data migration. Revert the
commit to restore the prior behavior (a missing BACKLOG_FILE dies inside `_rows()` with
awk's exit 2). No cleanup needed; the guard never writes to BACKLOG_FILE, it only reads
it.

## Reproduce

```
bash tests/test-board-file-guard.sh   # ALL PASS
bash tests/run-all.sh                 # full suite, ~13 min
```
