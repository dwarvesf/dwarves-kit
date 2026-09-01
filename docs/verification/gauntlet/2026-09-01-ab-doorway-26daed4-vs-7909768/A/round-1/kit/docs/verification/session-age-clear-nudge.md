# Proof of done: session-age cache-hygiene nudge (context-hints)
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | When session elapsed time is under 6h, `context-hints.sh` prints the existing temporal line and no nudge line | PASS | R1 |
| 2 | When session elapsed time exceeds 6h, `context-hints.sh` prints one extra line: `consider /clear or a handoff split (cache-hygiene rule)` | PASS | R1 |
| 3 | No new hook, no new state file, no new data collection: the nudge reuses `temporal_line`'s existing elapsed computation | PASS | R1 (code inspection: `hooks/context-hints.py` diff touches only `temporal_line`) |
| 4 | Existing `tests/test-kit-foldin-hooks.sh` suite stays green | PASS | R1 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `hooks/context-hints.py`'s `temporal_line()` gained a `NUDGE_THRESHOLD_SECONDS = 6 * 3600` module constant and a conditional append: when `elapsed > NUDGE_THRESHOLD_SECONDS`, the returned line grows a second line, `consider /clear or a handoff split (cache-hygiene rule)`. |
| Where | `hooks/context-hints.py` only. `hooks/context-hints.sh` is an unmodified thin exec shim (`exec python3 context-hints.py "$@"`); the UserPromptSubmit logic lives entirely in the `.py`, so no `.sh` edit was needed. |
| How it runs | Invoked by the UserPromptSubmit hook on every prompt; `temporal_line` already ran per prompt to print "Session time: ... elapsed", so the nudge check is free (no new I/O, no new state file, reuses the already-computed `elapsed` local). |
| Compaction-count leg | Not implemented. The source row asked for elapsed>6h OR compaction-count>=2. `context-hints.py`'s only inputs are the UserPromptSubmit stdin payload (`prompt`, `session_id`) and its own per-session `{start,last}` state file; neither carries a compaction counter. The repo's only compaction signal, `hooks/pre-compact-backup.sh`'s per-repo numbered backup-file count, is not session-keyed and reading it from `context-hints.py` would be new cross-hook data collection, which the row explicitly ruled out ("do not add new data collection"). Elapsed-time threshold only, as the row's fallback instruction allows. |
| Reversibility | `git revert` the commit; no persistent state schema changed (same `{start, last}` JSON shape as before). |

## 3. Confirmation (runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-08-11 | `bash tests/test-kit-foldin-hooks.sh` | 0 | PASS (94/94, incl. 3 new rows 5a/5b/5c) |
| R2 | 2026-08-11 | `git checkout HEAD~1 -- hooks/context-hints.py && bash tests/test-kit-foldin-hooks.sh` (then `git checkout HEAD -- hooks/context-hints.py` to restore) | 1 | RED-as-expected |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-kit-foldin-hooks.sh`
- Exit: 0
- Output (excerpt):
  ```
  === context-hints.sh (UserPromptSubmit) ===
    PASS row 1: skill hint fires on keyword match (exit 0)
    PASS row 1: hint names the mapped skill
    PASS NC: empty stdin exits 0 (exit 0)
    PASS NC: malformed JSON exits 0 (exit 0)
    PASS row 5a: far under threshold (100s elapsed), no nudge (negative control)
    PASS row 5b: 5s under threshold, no nudge
    PASS row 5c: 5s over threshold, nudge fires
  ...
  === Results ===
  Passed: 94 / 94
  All kit-foldin hooks tests passed.
  ```
- Verdict: PASS
- Note: covers AC1-AC4. Row 5a is a far-under-threshold negative control, 5b/5c straddle the 21600s boundary by 5s each side.

### R2 NEGATIVE CONTROL
- Command: `git checkout HEAD~1 -- hooks/context-hints.py` (reverts only the fix, keeps the new tests), then `bash tests/test-kit-foldin-hooks.sh`, then `git checkout HEAD -- hooks/context-hints.py` to restore.
- Exit: 1
- Output (excerpt):
  ```
    PASS row 5a: far under threshold (100s elapsed), no nudge (negative control)
    PASS row 5b: 5s under threshold, no nudge
    FAIL row 5c: 5s over threshold, nudge fires (missing 'consider /clear or a handoff split (cache-hygiene rule)')
  ...
  === Results ===
  Passed: 93 / 94
  1 test(s) failed.
  ```
- Verdict: RED-as-expected
- Note: rows 5a/5b still pass under the reverted code because "no nudge under threshold" trivially holds when the feature does not exist at all; row 5c is the one row that actually exercises the fix, and it fails without it, confirming the test is load-bearing. Restore verified byte-identical via `git diff --stat HEAD` (empty output) after `git checkout HEAD -- hooks/context-hints.py`.

## 5. Reproduce

```
bash tests/test-kit-foldin-hooks.sh
```

## Before/after

**Before** (`temporal_line` returned only the elapsed/idle line, no threshold check):
```python
if elapsed < 1:
    return None  # first prompt of the session: nothing useful yet
return f"Session time: {humanize(elapsed)} elapsed, {humanize(idle)} since your last prompt."
```

**After** (elapsed reused for a second, conditional line):
```python
if elapsed < 1:
    return None  # first prompt of the session: nothing useful yet
line = f"Session time: {humanize(elapsed)} elapsed, {humanize(idle)} since your last prompt."
if elapsed > NUDGE_THRESHOLD_SECONDS:
    line += "\nconsider /clear or a handoff split (cache-hygiene rule)"
return line
```
A session past 6h elapsed now gets a second line in its UserPromptSubmit context injection nudging `/clear` or a handoff split; a session under threshold is unchanged.
