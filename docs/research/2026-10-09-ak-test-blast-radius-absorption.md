---
title: "ak:test blast-radius absorption: rerun only failed suites, never weaken a failing test"
date: 2026-10-09
purpose: >
  Absorption pass over the "/ak:test, testing by blast radius" infographic (bestagentkits/agentkit)
  against the kit's test selection. The kit already selects tests by cause, so most of the sheet is
  covered. Records the verdict per mechanism: two absorbed (run-all --failed, the fix-agent
  frozen-evaluator line), two parked with an unpark trigger, the rest skipped as covered.
source_repos: [dwarves-kit]
refresh_cadence: none
next_review: null
status: active
---

# ak:test blast-radius absorption

Evidence of the one real gap: on 2026-10-08, sha 5802f66e had three back-to-back 228-suite runs, each 10 to 11 minutes and each exit=1, before smaller reruns (per-host `suite-times.tsv`). A fix loop reran the whole suite when only the failing suites needed it.

## Verdict

| Mechanism | Verdict | Why |
|---|---|---|
| select tests by cause (diff -> suites) | skip, covered | bin/test-affected + run-all --changed |
| mandatory/safety-critical always runs | skip, covered | `# always:` header, run-all.sh:145 |
| full suite is the backstop | skip, covered | nightly --all with KIT_RUN_ALL=1 |
| depth lanes (critical/feature/impact/light) | skip | bash suites have no depth knob; `# always:` already is the critical lane |
| when in doubt go broader (UNCOVERED widens) | park | unpark when the nightly --all fails on a change whose PR --changed run passed (an escaped defect) |
| audit/optimize: slow or redundant suites | park | history caps near 14 runs per suite, too few to judge catch value; unpark when the history holds 30+ runs per suite, or --changed p95 wall passes 5 min |
| rerun only failed suites in a fix loop | absorb | this PR: run-all --failed |
| never weaken a failing test | absorb | this PR: fix-agent contract line |

The sheet's "5 questions before writing a test" list is covered by the test-plan / test-writer layer pick (`agents/test-writer.md:33`, "Pick the layer per case").

## What shipped

- `bash tests/run-all.sh --failed` reads the latest line per suite from the suite-times history (`suite-times.sh failed`) and reruns only those with exit != 0. Exit 124 (a kill) and 255 (a dead worker) count. It never runs a suite to find failures.
- Always-on lints: `--changed` adds every `# always:` suite, so `--failed` mirrors it, but only when at least one failed suite is rerun. An all-green or empty history runs nothing.
- `agents/fix-agent.md` gains a frozen-evaluator rule in the style of `agents/test-writer.md`; `commands/greenlight.md` Step 4 passes it to the fix agent.
