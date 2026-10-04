# Verification: test-suite-affected

Change: `[test] suite` knob (`full` default, `affected`), read by `commands/execute.md`, `commands/verify.md`, `commands/ship.md`.

## Green run

| Field | Value |
|---|---|
| Command | `bash tests/test-suite-knob.sh` |
| Exit | 0 |
| Output (excerpt) | `=== 7/7 passed, 0 failed ===` |
| Verdict | PASS |

## Affected-test run

| Field | Value |
|---|---|
| Command | `bin/test-affected --no-cache` |
| Exit | 1 (2 of 44 fail; both fail identically on the base without this change) |
| Output (excerpt) | `test-affected: 44 selected, 42 pass, 0 cached, 2 fail, 0 uncovered` |
| Failing | `tests/test-adopt.sh` (PASS=54 FAIL=1), `tests/test-gate-opt-out.sh` (hard-path ship-gate and a hook-reads-config lint on `hooks/harvest.sh`, `hooks/harvest_sweep.py`) |
| Verdict | PASS for this change (failures pre-exist on base, confirmed by stashing the change and re-running both) |

## NEGATIVE CONTROL

| Field | Value |
|---|---|
| Command | `git show HEAD~1:commands/verify.md > commands/verify.md; bash tests/test-suite-knob.sh` |
| Exit | 1 |
| Output (excerpt) | `FAIL verify.md skips system-verifier under affected` then `=== 6/7 passed, 1 failed ===` |
| Restore | `git checkout -- commands/verify.md`, re-run: `=== 7/7 passed, 0 failed ===`, exit 0 |
| Verdict | RED-as-expected |
