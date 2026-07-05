# Sub-goal 03: stop test fixtures polluting the real completeness.log

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table , the full test suite runs and the REAL `completeness.log` is byte-unchanged (captured shasum before == after). Negative control: a test with the guard removed DOES write to it.
**Depends on:** none.
Model: sonnet
Effort: low
**Branch:** feat/kit-clean-03-fixtureiso
**PR base:** master

## Outcome

The test suite never writes to the operator's real telemetry. The SPEC-073 eval (bonus finding, ID-087) found 9 identical `LANE-CHECK downgrade ... "add user authentication with jwt sessions"` lines in the real durable `completeness.log` , a TEST fixture that leaked because some `lane-classify check` invocations ran without `DWARVES_KIT_LOG_DIR` set. Fix: every test that exercises `lane-classify check` (or anything that writes `completeness.log`) sets `DWARVES_KIT_LOG_DIR` to a temp dir; optionally, `check`'s write is guarded to no-op when it detects a test/non-interactive context. The real corpus stays clean so the eval + dashboard read real signal, not fixture noise.

## Quality bar

Prefer the smallest fix that guarantees isolation: make the TESTS set `DWARVES_KIT_LOG_DIR` (the existing convention) rather than adding runtime magic to `check`. If a code-side guard is added, it must NOT change `check`'s real-run behavior , only suppress the write under an explicit test signal. Do not clean the already-polluted lines as part of this (that is a one-off operator action, note it).

## How to close the loop

Kit-adopted repo: read `AGENTS.md` first; classify + record gates before push.

```
cd dwarves-kit
# find every test path that can reach the completeness.log writer without the env set
grep -rn 'lane-classify.sh" *check\|lane-classify.sh check' tests/
# proof: shasum the real log, run the whole suite, shasum again == unchanged
L=~/.local/state/dwarves-kit/logs/completeness.log; a=$(shasum "$L" 2>/dev/null)
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1; done
b=$(shasum "$L" 2>/dev/null); [ "$a" = "$b" ] && echo CLEAN || echo POLLUTED
```

Proof run-table at `docs/verification/fixture-isolation.md` (the shasum-unchanged capture + the negative control).

**Done =** running the full suite leaves the real `completeness.log` byte-unchanged (shasum before==after, captured), the negative control (guard removed) proves the test would otherwise pollute, and the gates are recorded.

## Handoff on completion

1. Flip 03's ROADMAP box, PR # + SHA.
2. HOT `HANDOFF.md`: next per roadmap.
3. WARM `DECISIONS.md`: test-side env vs code-side guard (which was chosen + why).
4. Report IN records, EXIT.

## Scope edges

**In:** test env isolation for `completeness.log` writers (+ optional non-interactive guard in `check`).
**Out:** detectors (02); the eval report (shipped); start-wiring (01).
**Not:** cleaning the already-leaked lines (a one-off operator action; note it in the proof); a general test-sandbox framework.

## Where to look

`lib/lane-classify.sh` (the `lane_check` completeness writer, now on the durable resolver), the tests that invoke `lane-classify check` (`tests/test-lane-escalation.sh`, `tests/test-hooks.sh`, `tests/test-lane-classify.sh`), dwarves-kit board ID-087, `docs/research/2026-07-02-effectiveness-eval.md` (bonus finding).

## PR body

Stop test fixtures writing to the operator's real `completeness.log` (tests set `DWARVES_KIT_LOG_DIR`). ID-087 (`#kit-telem-followup`). Verify: shasum-unchanged run-table. Proof: `docs/verification/fixture-isolation.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telem-cleanup/ROADMAP.md`.

## Notes

<empty>
