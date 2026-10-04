# Retro: kit follow-through (validate-round verb, wrap split)
Date: 2026-09-30
Sprint: 2026-09-29 to 2026-09-30

## Metrics
- Specs planned: 3 (SPEC-363, SPEC-364, SPEC-365), plus 1 added mid-cycle (SPEC-374)
- Shipped: 2. #842 (SPEC-363 validate-round verb: 22 commits, 11 files, +2168/-41) and #853 (SPEC-374 wrap split: 13 commits, 35 files, +10355/-9524)
- Parked: 2. SPEC-364 after 4 validation rounds all NEEDS REVISION; SPEC-365 because #835 made its ci-label gate opt-in and off by default, mid-build
- Validation: 13 rounds of 7 reviewers (about 91 reviewer runs), plus 3 single-reviewer fold-diff checks
- Builds: 9 Devin workers (swe-2-max) through tools/worker-launch
- Wall clock: about 23 hours, including a 7 hour Opus weekly-limit pause

## What worked
- The fold-diff check. One Opus reviewer reading only a fold's diff before a build caught a critical the fold itself introduced: SPEC-363's ship-gate cross-reference comment would have broken the Codex sha256 pin on hooks/ship-gate.sh. Three full rounds had missed it.
- The critical bar "critical only if the spec's own tests would miss it". It moved round 4 from blocking on build-catchable findings to blocking on real gaps, and let SPEC-363 and SPEC-365 pass.
- Dogfooding the validate-round verb on SPEC-374 right after #842 merged. Its first real use wrote every record in the right order and computed the validation-wide caught=true rollup on the APPROVED round.
- Devin for builds, Claude subagents for review. The lens reviews caught real defects every time: resume taking over forged records, shell injection through reviewer text in the close templates, a missing C13 wiring test, and the stale base against #850.
- Verbatim-move proof for the split: a sorted assert-label diff against master's monolith, byte-identical --help output, and one deliberate code break per suite. #850 landed mid-build and the label diff caught its 17 asserts before merge.

## What hurt
- Folds created the next round's critical. SPEC-364 ran four rounds and each fix introduced the next blocker (empty red log, unbounded sk- redaction, redaction outside LC_ALL=C). SPEC-365's fail-closed probe fold broke every repo without a ci label.
- Spec bloat from folding every warning. SPEC-365 grew from 204 to 641 lines, SPEC-363 from 330 to 471, SPEC-364 from 206 to 338. Builders then implemented dozens of reviewer-invented cases.
- Full-lane ceremony on internal tooling. About 91 Opus reviewer runs for changes of 400 to 500 lines each.
- A large, high-churn file. lib/wrap/wrap.sh (3,616 lines, 55 commits in 30 days) and tests/test-wrap.sh (5,987 lines, 73 commits) made every agent edit read everything and every check rerun about 1,600 asserts for about 8 minutes.
- Host contention. Other sessions looping negctl over the full test-wrap drove the Mini's load average to 236, which stretched every build and proof.
- Stale local checkouts. The lead read an outdated ops-toolkit memory note and hand-rolled Devin waits (hitting a wrong flag and Orca's long-poll limit) while `worker-launch wait` already existed on origin.
- Master red, independent of this work: six suites, two test-wrap wording asserts and two stale Codex pins (safety-gate.sh, ship-gate.sh) on a clean export. Every PR's CI inherits them.
- Retro trigger miss. Ship gates recorded by hand before the PR number existed carried no `shipping pr=#<n>` text, so /kit:wrap step 8 found no ship line until the lead re-recorded it.

## Action items
- [ ] Make the fold-diff check a named step in commands/spec.md step 5: after any fold, one reviewer reads only the fold diff before the build or the next round -- owner: @tieubao -- deadline: 2026-10-07
- [ ] Add a light lane for internal kit tooling: one validation round with the "critical only if tests would miss it" bar, then the fold-diff check, then build -- owner: @tieubao -- deadline: 2026-10-07
- [ ] Cap spec growth on folds: warnings that the tests would catch go to the builder's notes, not into the spec -- owner: @tieubao -- deadline: 2026-10-07
- [ ] Fix master red: six suites, two test-wrap wording asserts, repin the two stale Codex hook pins -- owner: @tieubao -- deadline: 2026-10-03
- [ ] Split tests/test-meta.sh the way SPEC-374 split test-wrap -- owner: @tieubao -- deadline: 2026-10-14
- [ ] Have `gate-ledger.sh record <rid> ship` (or the ship-gate) write the `shipping pr=#<n>` form once the PR exists, so a hand-recorded ship still triggers the retro -- owner: @tieubao -- deadline: 2026-10-14

## Kit feedback
- The commit-format hook reads the whole command and blocks a compound command whose `-m` subject is over 72 characters, including the unrelated steps before it.
- The board-row gate cannot read an `-F` message file created in the same command; use `-m` pairs.
- The ship-gate blocked a compound `git push ... 2>&1 | tail`; push with a plain command.
- `orca terminal wait` allows one long-poll at a time; `worker-launch wait a=<h> b=<h>` is the right tool and the ops-toolkit memory note says so on origin.
- Lane misfires in `lane-telemetry.sh misfires` are from other cycles' rids (batch-pr-opened, wrap-absorbed-proof, and others): accepted noise for this retro, not this cycle's runs.
