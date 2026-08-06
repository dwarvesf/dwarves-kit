# Proof of done: harvest.py dedup-on-append race fix (ID-202)

VERDICT: PASS

Filed originally in ops-toolkit as backlog row ID-202 before `cc-harvest` moved into the
kit as `hooks/harvest.sh`/`hooks/harvest.py` (kit PR #186). Symptom: re-runs stage the
same insight repeatedly (observed up to 6x duplicates in a live ledger).

## Acceptance criteria

1. Reproduce the duplicate-staging with a fixture (fake transcript/insight run against
   `harvest.py`) before touching any code, or stop and report if it does not reproduce.
2. Root-cause the dedup-on-append path and implement the minimal fix.
3. Add/extend a test proving a re-run (specifically, a CONCURRENT re-run) does not
   re-stage, matching the kit's existing bash test-suite shape for hooks.
4. `tests/test-kit-foldin-hooks.sh` passes; `shellcheck` on `hooks/harvest.sh` is clean.

## Root cause

`_harvest_payload()` in `hooks/harvest.py` computed `existing_slugs(ledger, glossaries)`
(a **read** of the ledger) and then, in a separate later step, called `append_rows(ledger,
fresh)` (a **write**) with no lock spanning the two. `harvest.sh` (no-arg / "ledger" mode)
fires on the `PreCompact` hook, and a single long session (or several parallel subagent
sessions sharing one repo, hence one ledger file) can trigger CONCURRENT `harvest.py`
processes against the same ledger. Two or more processes could each read the ledger
before any of them had appended, each independently decide the same slug was new, and
each append it, one unlocked "a"-mode write. This is exactly the "up to 6x duplicates"
symptom: N processes racing the same unlocked read-then-append window all land on the
same duplicate.

Sequential re-runs were never affected (each run's read reflects the prior run's
completed write), which is why the bug only shows up under real concurrency, not in a
simple "run it twice" check , the acceptance-criteria reproduction below has to force
that concurrency explicitly.

## Reproduction (before the fix)

A fixture extractor (`HARVEST_EXTRACTOR`) that always returns one fixed insight, fired by
N concurrent `python3 harvest.py` invocations against one throwaway ledger:

- Sequential runs (call twice, one after another): correctly deduped, 0 new on the
  second call , confirms the bug is concurrency-specific, not a plain dedup miss.
- 6-8 truly concurrent invocations (background `&` fan-out, a slow fixture extractor to
  widen the window): duplicate rows landed in the ledger on most runs (both the data row
  AND, on tighter timing, the table header), non-deterministically (30-90% failure rate
  run-to-run depending on system load) , confirming the race is real but not reliably
  assertable via wall-clock subprocess timing alone under a loaded dev box.
- A deterministic reproduction was then built directly against `_harvest_payload()`:
  Python threads (not subprocesses) sharing one process, with `threading.Barrier`
  forcing all N threads to finish extraction at the same instant and a small
  `time.sleep()` inserted inside `existing_slugs()` to stand in for "no other process
  has appended yet" (widening the window past any GIL scheduling quantum). Against the
  pre-fix code this reproduced 8 threads all deciding the slug was new and all
  appending it, 8/8 times (`dup_count=8`), every time.

This deterministic harness is what ships as the regression test (`tests/test-kit-foldin-hooks.sh`,
"row 4c").

## Fix

`hooks/harvest.py`: added `_ledger_lock_path(ledger)` (sibling `<ledger>.lock`, same
pattern as the existing `_archive_path()` helper) and wrapped the read-known-slugs +
filter + append_rows sequence in `_harvest_payload()` in a blocking exclusive
`fcntl.flock`. Concurrent invocations now serialize across that lock instead of racing:
whichever process gets the lock first appends and releases; the next one's
`existing_slugs()` call (now correctly happening AFTER acquiring the lock) sees the
just-appended row and skips it. Mirrors the existing `_run_harvest_locked()` pattern used
by `--stop-trigger`, but blocking rather than non-blocking , this harvest has real work
to do and should wait its turn, not skip (unlike the stop-trigger single-flight, which
intentionally skips a still-running harvest).

`tests/test-kit-foldin-hooks.sh`: added "row 4c" , the deterministic threading-barrier
race described above, embedded as a small `python3` heredoc script (matching existing
precedent for `python3` use in this test file), asserting exactly 1 occurrence of the
staged slug and exactly 1 ledger header after 8 concurrent `_harvest_payload()` calls.

## Confirmation run-table (2026-07-09)

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `python3 -m py_compile hooks/harvest.py` | 0 | compiles clean |
| 2 | `shellcheck hooks/harvest.sh tests/test-kit-foldin-hooks.sh` | 0 | no warnings |
| 3 | `bash tests/test-kit-foldin-hooks.sh` | 0 | `Passed: 51 / 51` (incl. new row 4c) |
| 4 | `bash tests/test-install-modules.sh` (adjacent suite, unaffected by this change) | 0 | `37 passed, 0 failed` |
| 5 | row 4c re-run x3 in isolation | 0 | `PASS` all 3 times, deterministic |

## NEGATIVE CONTROL

`git stash` the fix to `hooks/harvest.py` only (test file kept), re-run row 4c 3x:

| Run | dup_count (expect 1) | header_count (expect 1) |
|---|---|---|
| 1 | 8 (FAIL) | 1 |
| 2 | 8 (FAIL) | 1 |
| 3 | 8 (FAIL) | 2 (FAIL) |

`bash tests/test-kit-foldin-hooks.sh` output on the reverted code:
```
FAIL row 4c: 8 concurrent harvests of the same insight stage exactly once (ID-202) (expected '1', got '8')
```
`git stash pop` restores the fix; re-running immediately after gives `Passed: 51 / 51`
again. The test is falsifiable in both directions: it fails on the pre-fix code
deterministically and passes on the fixed code deterministically.

## Reproduce

```
cd <dwarves-kit>              # master or this branch
bash tests/test-kit-foldin-hooks.sh   # 51/51, incl. "row 4c" concurrent-dedup
shellcheck hooks/harvest.sh
```

To see the negative control directly:
```
git stash push -- hooks/harvest.py
bash tests/test-kit-foldin-hooks.sh 2>&1 | grep "row 4c"   # FAILs
git stash pop
bash tests/test-kit-foldin-hooks.sh 2>&1 | grep "row 4c"   # PASSes
```
