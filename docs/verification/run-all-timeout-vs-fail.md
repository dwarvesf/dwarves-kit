# Verification: run-all reports a timeout as its own fact

`tests/run-all.sh` accumulated timeouts and red assertions into one `failed` list, so the summary printed `run-all: FAILED -> <suite>` for both. They are different facts: a per-suite ceiling hit under load is not a broken suite.

Line 49 already printed `TIMEOUT (300s)` vs `FAIL (rc=N)` per suite, so the information existed. It was the SUMMARY that flattened it, and the summary is what a reader keeps.

## The incident this came from

On 2026-09-12 a full run of the negctl branch printed `run-all: FAILED -> test-meta`. `test-meta` takes 142s on that Mac at 1-minute load ~9; the machine was at 26-55 and the cap is 300s. The suite was green: standalone it passed 851/851 (even with a dirty tree), and a re-run at a raised cap passed 137/137. Two full re-runs went into establishing that, because the summary said only "FAILED".

## Change

- Timeouts accumulate in their own list and get their own summary line, naming `RUN_ALL_TIMEOUT_SECS`.
- A killed suite now says it ran out of time. Previously the FAIL grep ran against a killed suite's log, found no assertion, and printed nothing, which reads as "failed for no reason".
- Both still exit 1. A timeout is still worth surfacing; it is just not the same claim as a red assertion.
- **The default ceiling is unchanged at 300s.** Raising it would weaken the hang guard CI needs, and picking a new constant is the same trap as the one fixed elsewhere this session (a fixed timeout bounding an unbounded quantity). The fix is to say which of the two happened, not to move the number.

## Green run

```
Command: bash tests/test-run-all-timeout.sh
[1] a suite over the ceiling is TIMED OUT, never folded into FAILED
  ok: timeout named on its own line, no FAILED line
[2] the timeout line says what to do instead of treating it as broken
  ok: hint names the knob and the distinction
[3] a killed suite says it ran out of time rather than showing no assertion
  ok: the empty-FAIL-grep confusion is named
[4] a genuinely red suite is still FAILED, never TIMED OUT
  ok: a real failure is untouched by this change
[5] both at once are reported as two separate facts
  ok: one line each, neither swallows the other
[6] the all-green summary is unchanged (no new line on the happy path)
  ok: green path byte-identical
test-run-all-timeout: all 6 passed
Exit: 0
Verdict: PASS
```

Each case builds a throwaway kit-shaped dir holding the REAL `tests/run-all.sh` plus fixture suites, so nothing touches the repo's own `tests/`. The suite carries `# requires: timeout`, so on a runner without the binary run-all skips it rather than hanging on the `sleep 30` fixture.

## Negative control

Revert ONLY `tests/run-all.sh` and keep the new cases.

```
Command: git checkout HEAD~1 -- tests/run-all.sh && bash tests/test-run-all-timeout.sh; git checkout HEAD -- tests/run-all.sh
timedout accumulator present: 0
[3] FAIL: out=test-slowpoke   TIMEOUT (1s) ... run-all: FAILED -> test-slowpoke
[4] ok: a real failure is untouched by this change
[5] FAIL: run-all: FAILED -> test-redherring test-slowpoke
[6] ok: green path byte-identical
test-run-all-timeout: 2 passed, 4 FAILED
restored: 0 dirty
Verdict: RED as expected, then restored clean
```

The control's own output is the defect, stated by the old code: `run-all: FAILED -> test-redherring test-slowpoke` puts a genuinely red suite and a timed-out one on one line with no way to tell them apart.

Cases [4] and [6] pass against BOTH implementations. That is what shows a real failure and the green path are untouched, rather than merely asserted to be.

## Reproduce

```bash
bash tests/test-run-all-timeout.sh
RUN_ALL_TIMEOUT_SECS=1 bash tests/run-all.sh --only <a slow suite>
```

## Scope

`docs/FEATURES.md` stayed fresh: this suite tests `run-all.sh` itself rather than a `/kit:` command, so no registry row's test count moved and SPEC-219's pin is untouched. Verified by regenerating and diffing.
