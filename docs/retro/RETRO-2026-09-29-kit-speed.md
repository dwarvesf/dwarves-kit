# Retro: kit speed session (test selection, parallel validation, wrap CI wait)
Date: 2026-09-29
Sprint: 2026-09-29, one session; three PRs merged, one spec parked

The lead drafted these answers from the session record. They were not collected one question at a time, and the operator can correct them.

## Metrics
- Tasks planned: 4, completed: 3, deferred: 1 (the bug lane, parked)
- PRs: dwarves-kit #815 (`bin/test-affected`), #816 (parallel spec validation), #817 (wrap merge waits for a fresh `ci` label)
- Parked: the bug lane for kit-machinery fixes, on `origin/feat/lane-bug-machinery`, after 3 validation rounds
- Baseline: a SPEC-360 build took 53 minutes, mostly from re-running the 5,732-line `tests/test-wrap.sh` about 5 times
- Selection: the first cut of `test-affected` picked 33 suites for one README edit; the narrowed rule picks 12
- Validation speed: the slowest parallel reviewer took 72s to 4.4min per round, against 215-434s for a single-agent round
- Validation rounds on the wrap wait: 4, then 3 review lenses; the lenses found one HIGH, fixed before merge
- Live: foundation-workers #970 and #971 merged 6s after the `ci` label went on

## What worked
- Measuring first. The 53 minute build pointed at one cause, repeated runs of one big suite, so the fix was a pass cache keyed by content hash. `run-all.sh --changed` now shares the same selection.
- Parallel reviewers at the lane's model. Opus runs on the full lane, and Reviewer 6 is always Opus. The lead merges the verdicts mechanically. A spec writer adds `## Grounding` with live samples and dry-traced negative controls.
- Dropping the per-section verdict cache. Four criticals showed it could carry stale verdicts. Every fold rewrites the Decision Log anyway, so the cache would never have hit.
- Watching the wrap fix live. The two foundation-workers merges showed the wait working before anyone trusted the tests alone.
- The review lenses caught a HIGH the validation rounds missed: a later SKIPPED run hid an in-progress one.
- Parking the bug lane. The denylist and then the allowlist each leaked. The leaks were gate-sourced libs, newline `--files`, the proof marker as a neutral path, md-only inert changes, and cwd-based repo detection in wrap step 10. The value was about 11% of fixes, and the proof gate (`gate.proof_of_done`) defaults to false. The cost did not fit.

## What hurt
- The lead recorded APPROVED from an interim reviewer block. The final block upgraded to a critical. #816 now carries the rule that only the agent's final completion counts.
- The lead dropped a zero-time clause on a validator's unchecked claim, which cost one round. Live `gh` gives pending CheckRuns a `completedAt` of `0001-01-01T00:00:00Z`. `## Grounding` exists to stop this.
- `negctl.sh` discards suite output, so no proof records which cases went red. Workers hand-rolled per-label wrappers 4 or more times.
- Validate-round bookkeeping (blob pin, snapshot, ledger records) was run by hand for 6 rounds.
- The first `test-affected` cut over-selected. One README edit picked 33 suites before the rule was narrowed.

## Action items
- [ ] `negctl.sh` keeps suite output and records which cases went red, so a proof can cite them. Candidate, full lane -- owner: @tieubao -- deadline: 2026-10-12
- [ ] A gate-ledger verb for validate-round bookkeeping (blob pin, snapshot, ledger records). Candidate, full lane -- owner: @tieubao -- deadline: 2026-10-12
- [ ] `wrap land` has no re-gate after its wait. Add one so a run that turns red during the wait blocks the merge -- owner: @tieubao -- deadline: 2026-10-12
- [ ] The CLEAN rule does not reach autoland. Extend it to the carry path -- owner: @tieubao -- deadline: 2026-10-12

## Lane telemetry disposition
- No lane misfire and no shipped-incomplete line to dispose from this session. The bug lane never shipped, so it has no telemetry.

## Kit feedback
- `## Grounding` in the spec is the cheapest fix for unchecked validator claims. Keep it required on the full lane.
- Reading only an agent's final completion is now a written rule. The interim block was the trap.
