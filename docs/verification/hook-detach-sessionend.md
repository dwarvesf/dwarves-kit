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

## Round 2: /kit:review-team findings, fixed

A 4-lens review (security, architecture, test-coverage, advisor) ran against this PR and
returned 12 findings (0 CRITICAL, 3 HIGH, 4 MEDIUM, 5 LOW). Six were fixed here; the rest
are advisory/low-priority and logged, not blocking:

| # | Finding | Fix |
|---|---|---|
| 1 | Corroborated 3x (security, test-coverage, advisor): a corrupt/truncated payload handoff file, or a `Popen` failure right after the file was written, leaked the payload file forever -- the `finally` cleanup only ran on the SECOND of two nested `try`s. | `harvest.py`: extracted `_read_and_run(pf, work)` wrapping the read + work in ONE outer `finally`, used by `cmd_stop_harvest`/`cmd_lab_log_run`/`cmd_harvest_run`. `backlog-stage.py`'s `cmd_staged_run` gets the same shape inline (only one such caller there). Both `_spawn_detached` variants also now remove the just-written payload file if `Popen` itself fails. |
| 2 | (advisor) The fix's actual SessionEnd-specific claim -- the detached child survives via `start_new_session=True` -- was never tested; every row only measured wall-clock elapsed + polled for eventual content. | New rows (`3e`, `4i`): verify via `ps -o pgid=` that the detached child's process group differs from the invoker's, proving real OS-level isolation (chosen over a kill/signal race, which would be flaky to time against process spawn). |
| 5 | (architecture) `_spawn_detached` had the same name in both files with a different arity (3-arg in harvest.py vs 2-arg in backlog-stage.py), silently breaking the house convention that duplicated helpers share identical signatures. | Renamed backlog-stage.py's copy to `_spawn_staged_detached`; updated its docstring and every call site/comment. |
| 6 | (test-coverage) `HARVEST_SYNC`/`BACKLOG_STAGE_SYNC` was proven to produce the same output, never proven to actually run INLINE -- a regression silently turning it into a no-op would still pass. | New rows (`3d`, `4g`, `4h`): SYNC + the slow extractor, assert elapsed >= ~1.8s (genuinely blocked). |
| 7 | (test-coverage) `stage_from_text()`, a newly-extracted pure function built to be independently testable, was only exercised indirectly, happy-path only. | New row (`3g`): direct unit test via `importlib.util` (mirrors the ID-202 race harness's own pattern), covering the dedup-skip and empty-candidates branches. |
| 9 | (advisor) Both `HARVEST_STATE_DIR`/`BACKLOG_STAGE_STATE_DIR` docstrings still described their old sole purpose (lock/throttle dir), not the new payload-handoff use this PR adds. | Updated both docstrings. |

Not fixed here (advisory/low-priority, logged for follow-up): `--stop-trigger` has zero
test coverage before or after this refactor (pre-existing gap, not introduced by this
PR); `backlog-stage.py`'s dedup+append has no lock equivalent to harvest.py's
`harvest.lock` (mitigated by the 1h `BACKLOG_STAGE_MIN_INTERVAL` throttle); detached
children fully silence stderr (by design, unchanged from the pre-existing
`--stop-trigger` posture); predictable payload filename + non-`O_EXCL` write (requires
attacker at the local user's own trust level to matter); small intra-file duplication in
`_dispatch`'s branches (below the rule-of-three).

### Round 2 run-table

| # | Check | Result |
|---|---|---|
| 1 | Full suite after all 6 fixes | **91/91 PASS** (was 68; +23 new rows: 3d/3e/3f/3g, 4g/4h/4i, 4j-4l x3) |
| 2 | Targeted negative control: revert JUST the `_read_and_run`/`cmd_staged_run` outer-`finally` fix (finding #1), keep everything else | rows `3f`/`4j-l` (all 4 detached entry points) go RED -- `exits 0` still PASS, `corrupt payload file was removed` FAILs on every one; restored, back to 91/91 |
| 3 | Process-group isolation (finding #2) | rows `3e`/`4i` PASS: detached child's pgid differs from the invoker's in both files |
| 4 | SYNC-seam genuinely blocks (finding #6) | rows `3d`/`4g`/`4h` PASS: elapsed >=1.8s under the 2s-slow extractor with SYNC=1 set |
| 5 | `stage_from_text` unit test (finding #7) | row `3g` PASS: dedup-skip and empty-candidates branches both covered |

## Reproduce

```
cd dwarves-kit   # this branch (fix/hook-detach-sessionend), or merged master
bash tests/test-kit-foldin-hooks.sh   # 91/91
```
