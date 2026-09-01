# Proof of done: ID-392 review-economics telemetry (the slop metric)

Behavioral change: `lib/telemetry/lane-telemetry.sh report` now emits a "review economics"
section, read-side only, over the run-ledger lines SPEC-061 (`| GATE | review | ran |`) and
SPEC-129 (`| OUTCOME | review | end | caught=.. dur_s=..`) already write. New `_review_agg()`
aggregates first-pass acceptance (1-round runs whose last review OUTCOME closed
`caught=false`), rework round-trips (runs with >1 review GATE line), reviewer minutes (sum of
`dur_s` across every review-phase OUTCOME bracket for a run), and escape rate (existing
`_escapes()` count over shipped runs, per SPEC-062). No new write verb, no new store, per the
DECISION-BRIEF-review-economics.md build constraint.

## Green run

Command: `bash tests/test-hooks.sh` (full repo suite; includes the new "lane-telemetry: review
economics (ID-392)" section)
```
=== Results ===
Passed: 497 / 497
All tests passed.
```
Exit: 0

Command: `bash lib/telemetry/tests/smoke.sh` (the module's own hermetic suite, unaffected by
this addition; confirms no regression in the resolver/wiring tests)
```
smoke: all 17 passed
```
Exit: 0

Manual fixture run (`docs/briefs/DECISION-BRIEF-review-economics.md`'s own worked shape: one
clean first-pass run, one 2-round rework run, one escaped defect):
```
review economics (2 reviewed runs):
  first-pass acceptance: 1/2 (50%)
  rework round-trips: avg 1.5 review round(s)/run; 1 run(s) needed >1 round
  reviewer time: 25.0 min (sum of review-phase OUTCOME brackets)
  escape rate: 1/2 shipped run(s) later traced an escaped defect (50%)
```
Exit: 0

## NEGATIVE CONTROL

`git stash push -- lib/telemetry/lane-telemetry.sh` (reverting only the source change, keeping
the new test fixtures) then seeding a fresh ledger with one clean-review run and running
`report`:

```
$ DWARVES_KIT_LOG_DIR="$RE_NC" bash lib/telemetry/lane-telemetry.sh report | grep -c "review economics"
0
```
Exit: 0 (grep found nothing) -- RED as expected: with the source change reverted, `report`
carries no "review economics" section at all.

`git stash pop` restored the fix; the same seed then reproduces the section:
```
  review economics (1 reviewed run):
```
Exit: 0 -- back to PASS, confirming the revert (not an unrelated environment change) is what
flips the result.

## Reproducible

- `bash tests/test-hooks.sh` (full suite)
- `bash lib/telemetry/tests/smoke.sh` (module suite)
- The manual fixture sequence is inlined verbatim in
  `tests/test-hooks.sh` under "=== lane-telemetry: review economics (ID-392) ===", driven
  through the real `gate-ledger.sh start/record/outcome` write verbs (not hand-crafted log
  lines), including its own negative control (collapse a 2-round run to 1 clean round ->
  first-pass flips from 1/2 to 2/2).
