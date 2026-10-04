# Retro: wrap step 0 scope cycle and the lighter-defaults follow-ups
Date: 2026-10-02
Sprint: 2026-10-02 (one day)

## Metrics
- Spec: SPEC-383 (rid `wrap-step0-scope`), lane `full`. Tasks planned: 4 (T1 to T4), completed: 4, deferred: 0.
- PRs: #881 (step 0 stops main-checkout writes only, adds `--no-pull`), #882 (step 3 merges only the session's own PRs via `--pr`), #883 (`negative_control` knob), #885 (`test.suite` knob, affected tests in the dev loop), #886 and #887 (red suites on master fixed).
- #881: 18 files, +850/-36, 10 branch commits. Follow-ups: #882 1 file pair, +4/-4; #883 +84/-5; #885 +69/-3; #886 +59/-44; #887 +157/-38.
- Ledger timing for SPEC-383: start 10:28Z, spec validate 2 rounds (209 s and 240 s of wall clock, 7 reviewers each), build 10:38Z to 11:18Z, review 11:18Z to 12:25Z, #881 merged 12:28Z. Follow-ups merged by 14:35Z.
- Full wrap suite on the build: 2072 passed; 2113 passed on the final run. Negative controls: NC1 to NC8.

## What worked
- Opus review on the built branch found 6 issues, including a HIGH: under a step 0 stop, a PR whose head the main checkout holds could still be re-merged into that checkout, landing a live session's mid-iteration work. All 6 folded as new commits, with the fix in code (`merge --no-pull` skips any PR whose head the main checkout holds), not prose.
- Negative controls caught their own weak spots. Three of eight were vacuous on the first pass (the mutated code did not turn the named test red) and were redone before the proof was written.
- The logged `validate` override at the two-round ceiling kept the cycle moving without hiding the open findings: the override reason names the round 2 criticals and who folded them.
- The follow-ups were scoped to one PR each (1 to 11 files) and merged in under a minute of PR life. #882 is a 4-line change.

## What hurt
- Ceremony outweighed the change. A scoped fix (one flag, one doc section, tests) took roughly 3 hours of operator time through spec, two validate rounds, build, review and proof. The operator then asked for lighter defaults (#883, #885) and a nightly regression (ops-toolkit #3841) to replace per-change heavy gates.
- Both validate rounds returned NEEDS REVISION with 3 criticals each (14 and 12 warnings), and no third round was allowed. Round 1 flagged the unenforced re-merge-in-main exception; round 2 recorded it as accepted residue; code review then rated it HIGH and it had to be fixed anyway. Validate named the defect twice and the spec still shipped it to build.
- 3 of 8 negative controls were vacuous on the first pass. Nothing in `negctl` rejects a mutation that leaves the target test green when paired with the wrong suite or wrong assertion, so the lead had to notice by hand.
- Master carried red suites that #886 and #887 had to fix after the main change shipped. The red state sat on master after the main change shipped; the nightly regression exists to surface that within a day.
- Four gates were overridden or skipped on a full-lane run (grill, think, design, test-plan), each with a valid reason. The overrides were correct for a pre-specified brief, but they cost ledger noise on every cycle of this shape.

## Action items
- [x] Add a `negative_control` knob so the heavy control runs on full-lane only -- owner: @tieubao -- deadline: 2026-10-02 (shipped in #883)
- [x] Add a `test.suite` knob so the dev loop runs affected tests, not the full suite -- owner: @tieubao -- deadline: 2026-10-02 (shipped in #885)
- [x] Fix the red suites on master -- owner: @tieubao -- deadline: 2026-10-02 (shipped in #886 and #887)
- [x] Nightly full dwarves-kit regression, so red master surfaces in a day, not in the next change's gates -- owner: @tieubao -- deadline: 2026-10-02 (ops-toolkit #3841)
- [ ] Make `negctl.sh` fail a mutation whose named test stays green, or print the red test names beside the mutation so a vacuous control is visible in the output -- owner: @tieubao -- deadline: 2026-10-09
- [ ] When validate round 1 raises a critical against a design invariant, the spec fold must name the code or test that enforces it; "accepted residue" on a critical needs an operator ack, not the spec author alone -- owner: @tieubao -- deadline: 2026-10-09
- [ ] Round 2 of `spec-validate` re-checks only the round 1 criticals (one or two lenses) instead of repeating all 7 reviewers -- owner: @tieubao -- deadline: 2026-10-16
- [ ] Pre-specified operator briefs for a scoped fix route to a lighter lane by size rule, so grill, think, design and test-plan are not logged as overrides one by one -- owner: @tieubao -- deadline: 2026-10-16

## Kit feedback
- Doc-impact and completeness sweep (1b): no `completeness.log` exists on this host, so there are no un-cleared warnings to surface. The spec's own docs task (consumer-contract, CHANGELOG, implementation notes, proof of done) covered the companion docs; `docs/FEATURES.md` needed `feature-registry.sh check --fix` after the new spec shifted its counts.
- Decision capture (1c): no decision fell outside a SPEC Decision Log. The narrowed step 0 stop (main-checkout writes only) is recorded in SPEC-383; no new ADR needed.
- Lane telemetry (1d): `lane-telemetry.sh misfires` has no line for `wrap-step0-scope`. The lane was `full`, classified `full`, no misroute.
- A `gate-ledger.sh` call with a mistyped rid silently creates a new run log (a stray `fix-wrap-step0-scope.log` with one `reflect` line was created while looking for the real rid `wrap-step0-scope`). A rid that has no START record should be refused or warned.
- The Reflect bracket uses `Reflect`, while the ledger line is written lowercase `reflect`; harmless, but a reader grepping for `Reflect` misses it.
