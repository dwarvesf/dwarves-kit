# Proof of done: detach the harvest/backlog-stage LLM call from SessionEnd

VERDICT: PASS

## Acceptance criteria

1. `harvest.py`'s no-arg mode, `harvest.py --lab-log`, and `backlog-stage.py`'s `main()`
   each return control to the invoking hook almost immediately, REGARDLESS of how long
   their `claude -p` extractor call takes.
2. The actual work (extractor call, dedup, file write) still happens and still lands in
   the right file -- it is deferred to a detached child, not skipped.
3. `HARVEST_SYNC=1` / `BACKLOG_STAGE_SYNC=1` preserve the old inline behavior exactly
   (test-fixture determinism; existing pre-fix assertions still pass unmodified in spirit).
4. Existing behavior is unaffected: the full `tests/test-kit-foldin-hooks.sh` suite, plus
   the sibling suites that exercise these two hooks indirectly, stay green.

## Implementation

See `hooks/harvest.py` (`_spawn_detached`, `cmd_lab_log_run`, `cmd_harvest_run`,
`_dispatch`) and `hooks/backlog-stage.py` (`stage_from_text`, `_spawn_detached`,
`cmd_staged_run`, `main`). Full rationale in the module docstrings and the PR description
(dwarvesf/dwarves-kit#298).

## Confirmation run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Full kit-foldin hooks suite | `bash tests/test-kit-foldin-hooks.sh` | **68/68 PASS** |
| 2 | backlog-stage detach mechanism (instant fake extractor) | rows "3b" in the suite | PASS |
| 3 | harvest detach mechanism, both modes (instant fake extractor) | rows "4c"/"4d" | PASS |
| 4 | **The actual bug**: hook stays fast under a 2s-SLOW extractor (backlog-stage) | row "3c" | PASS -- hook returns in 37ms, candidate lands ~2s later |
| 5 | **The actual bug**: hook stays fast under a 2s-slow extractor (harvest no-arg) | row "4e" | PASS -- hook returns in 39ms, ledger entry lands ~2s later |
| 6 | **The actual bug**: hook stays fast under a 2s-slow extractor (harvest --lab-log) | row "4f" | PASS -- hook returns in 44ms, draft lands ~2s later |
| 7 | ID-202 concurrent-harvest dedup regression (unrelated invariant, must still hold) | row "4c" (concurrency block) | PASS -- 8 concurrent harvests stage the insight exactly once |
| 8 | Sibling suites that also exercise these hooks | `test-install-modules.sh`, `test-intake-sweep.sh`, `test-learn-drain.sh`, `test-adopt.sh` | all green (37, 28, 23, 21 passed respectively) |

Rows 4/5/6 are the load-bearing ones: they run the hook with an extractor that
`sleep 2`s before answering (approximating a real `claude -p --model haiku` call) and
assert the hook itself returns in under 1 second regardless, then poll (up to 5s) for the
real output to land afterward. The earlier rows (3b/4c/4d) only prove the detach
mechanism doesn't break the ledger/staging-file writing path; they use an instant fake
extractor and would pass even without this fix, since the hook is fast either way when the
extractor is fast. Rows 3c/4e/4f are the ones that actually distinguish before/after.

## NEGATIVE CONTROL (revert -> RED -> restore)

To prove rows 3c/4e/4f actually detect the bug (not just green-no-matter-what):

- **Revert:** `git checkout origin/master -- hooks/harvest.py hooks/backlog-stage.py`
  (restores the pre-fix, fully-synchronous implementation), keeping the new
  `tests/test-kit-foldin-hooks.sh` (with the slow-extractor rows) as-is.
- **RED:** `bash tests/test-kit-foldin-hooks.sh` -> `Passed: 65 / 68`, suite exit 1, with
  exactly the three timing assertions this fix targets flipping (the exit-0 and
  eventual-file-content assertions in the same rows still pass -- the old code was never
  incorrect, only slow/blocking):
  ```
  FAIL row 3c: hook took 2199ms (expected <1000ms) -- hook is blocking on the slow extractor again
  FAIL row 4e: no-arg hook took 2229ms (expected <1000ms) -- hook is blocking on the slow extractor again
  FAIL row 4f: --lab-log hook took 2262ms (expected <1000ms) -- hook is blocking on the slow extractor again
  ```
- **Restore:** `git checkout HEAD -- hooks/harvest.py hooks/backlog-stage.py` ->
  `bash tests/test-kit-foldin-hooks.sh` -> suite exit 0, `Passed: 68 / 68`.

This falsifies the "the hook is fast regardless of extractor latency" claim on demand:
put the synchronous code back and the suite goes RED on exactly the three rows that
measure it, nothing else.

## Reproduce

```
cd dwarves-kit   # this branch (fix/hook-detach-sessionend), or merged master
bash tests/test-kit-foldin-hooks.sh   # 68/68
```
