# Verification -- nightly-lint-failures

Two master-red lint suites fixed: the mktemp template guard (R3) and the outcome-emit sweep (debug.md orphan).

## Green run
```
Command: bash tests/test-mktemp-template-guard.sh; bash tests/test-outcome-emit-sweep.sh
Exit: 0, 0
Output:
=== 11 passed, 0 failed ===
Passed: 51 / 51
All outcome-emit-sweep tests passed.
Verdict: PASS
```
Touched test files, each run alone: lib/session/tests/test-parse-transcript.sh (smoke: all 20 passed), tests/test-hook-log-dir.sh (24 passed, 0 failed), tests/test-install-compat.sh (PASS: install compat), tests/test-ship-gate-refs-block.sh (11 passed, 0 failed), tests/test-wrap-adopt.sh (all 207 passed). `bash -n` clean on all five.

## Negative control
```
Command: drop ` || return 1` from tests/test-hook-log-dir.sh:28, then bash tests/test-mktemp-template-guard.sh
Exit: non-zero
Output:
R3 tests/test-hook-log-dir.sh:28: new_home() { local h; h=$(mktemp -d "$T/h.XXXXXX"); ...
=== 10 passed, 1 failed ===
Verdict: RED as expected
Command: delete the `outcome <rid> debug end` line from commands/debug.md, then bash tests/test-outcome-emit-sweep.sh
Exit: non-zero
Output:
ORPHAN: debug.md (debug)
Passed: 50 / 51
Verdict: RED as expected
```
Both sites were restored after the run (working tree clean against the commit).

## Not proven
- The full suite (`run-all.sh --all`) was not run; only these two suites and the five touched files.
- The two commits also fix R3 hits in tests/test-ship-gate-refs-block.sh and tests/test-wrap-adopt.sh, which the guard flagged but the task list omitted.
