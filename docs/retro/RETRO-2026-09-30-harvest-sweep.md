# Retro: harvest sweep (SPEC-357)
Date: 2026-09-30
Sprint: 2026-09-28 to 2026-09-30

## Metrics
- Tasks planned: phase 1 (T1 to T19, T13b, T22), completed: phase 1; deferred: the rest, split into SPEC-358.
- Commits: 9 merged PRs (1 feature, 1 spec carry, 1 docs backfill, 6 fixes).
- Key PRs: #814 phase 1, #836 sonnet extractor with codex fallback, #828 weekly limit hold, #826 plist discovery, #821 transcript restate, #838 test isolation.
- Spec validation: 5 rounds, criticals 3, 2, 2, 1, 1. The operator overrode the fifth.
- Build: about 9 hours in the ledger, then a live rollout and two more fix waves.
- Cost: measured at about double the spec estimate.
- Ledger check: the sweep suite reached 632/632 with 5 negative controls red then green (harvest-extractor-fallback.log).
- Lane telemetry: no harvest run appears in the misfire list. Accepted noise: none owed for this cycle.
- Completeness sweep: `~/.claude/dwarves-kit/logs/completeness.log` does not exist, so no un-cleared warnings. One doc gap: the manual and README backfill landed in #829, after the feature.

## What worked
- Validation caught real design faults before code: stage-2 fetch without creds, git over ssh under launchd, `last_success` advancing on a capped run, ledger rows dropping why and source. Each would have been a live bug.
- Serial groups of about four tasks, each checked by a fresh Sonnet verifier, caught a real defect in every group. The verifier was cheap and never came back empty.
- The dedicated `tests/test-harvest-sweep.sh` suite kept negative controls affordable. The 220s full suite would have cost over six hours.
- Moving the build from Claude subagents to Devin workers mid-way kept the work moving when the first model tier was the bottleneck.
- The implementation notes recorded each deviation as a delta, so this retro needed no reconstruction.

## What hurt
- Validation ran five rounds and still left the operator to override the last. Round 4 and 5 findings were narrower each time; the spec kept absorbing design that only reality could settle.
- The live rollout found three bugs no test caught: a Devin transcript that continued the agent's task, a prose-only probe, a 0600 plist invisible to vps-mon discovery.
- The first scheduled runs found two more: a weekly usage limit read as an auth failure, and host config leaking into tests.
- All five escapes share a cause: tests ran against fixtures and a clean environment, never the real launchd job, real model output, or a real host config.
- Cost came in at double the estimate. The spec priced one extraction pass and not retries, the fallback extractor, or verifier passes per group.
- Docs landed after the code (#829), and the kit-side FEATURES registry was already stale at baseline.

## Action items
- [ ] Add a live smoke step to the spec template for scheduled or model-calling features: one real run under the real scheduler with a real model before ship. Owner: @tieubao. File: `templates/spec.md` and the `/kit:spec` skill. Deadline: 2026-10-14.
- [ ] Cap spec-validate at three rounds. From round 4, only criticals that reference a real failure trace are blocking; the rest fold into build notes. Owner: @tieubao. File: `commands/spec-validate.md`. Deadline: 2026-10-14.
- [ ] Add a cost line to the spec template covering retries, fallback path, and per-group verifier passes, and record actual cost in the retro. Owner: @tieubao. File: `templates/spec.md`. Deadline: 2026-10-14.
- [ ] Make a model-output classifier test a fixture-from-real-output rule: a probe or error classifier needs one captured real transcript row (the weekly limit and prose-only probe cases). Owner: @tieubao. File: `tests/test-harvest-sweep.sh` first, then the `docs/impl-playbook/testing-strategy.md` pointer. Deadline: 2026-10-21.
- [ ] Have `lib/testenv` style isolation pinned by default in every new suite: neutral HOME and config, so host config cannot leak. Owner: @tieubao. File: `tests/run-all.sh` wrapper. Deadline: 2026-10-21.
- [ ] Make `/kit:execute` accept a serial-group mode with one fresh task-verifier per group, since it proved out. Owner: @tieubao. File: `commands/execute.md`. Deadline: 2026-10-21.
- [ ] Regenerate `docs/FEATURES.md` at the end of the build, and gate the docs backfill in the same PR as the feature. Owner: @tieubao. File: `docs/WORKFLOW.md` doc-impact map. Deadline: 2026-10-14.

## Kit feedback
- The negctl helper runs its command three times per control; a per-suite runtime note in the spec template would prevent the 220s suite trap.
- `/kit:execute` has no native path for a non-Claude worker (Devin). The mid-build switch was hand-run and left no ledger rows per group.
- Decision-capture: the split into phase 1 and SPEC-358, and the choice of a dedicated suite, are already in the spec and implementation notes. Nothing new to record.
