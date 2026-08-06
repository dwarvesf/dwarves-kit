# Workflow test catalog

The case coverage design for testing the framework itself. Testing a framework is hard
because the interesting failures are in the SEAMS (gates, retries, state transitions,
concurrency), not in any one script. This catalog enumerates the cases per layer (brief
§6) so coverage is a checklist, not a vibe. Every case names what it proves, how the
fault is injected, the expected signal, and where the result surfaces.

Status: design catalog. Cases become executable via the L1 `scripted` executor and the
L2/L3 suites (ID-423); the TUI renders any of them live from the same event stream.

## L1 · Mechanism correctness (scripted model, every kit commit, ~free)

The model is replaced by a scripted executor (canned outputs + injected faults), so a
whole lane replays deterministically in seconds. These cases assert the ENGINE.

| Case | Proves | Injection | Expected signal |
|---|---|---|---|
| M-01 happy path | full lane wires: every gate recorded, board transitions legal, ledger rows schema-valid | none | run_end pass; gate ledger complete; board row reaches shipped |
| M-02 ship-gate negative | the gate actually blocks | delete the proof artifact before ship | ship blocked; run_end fail with named gate |
| M-03 fail-fix-retry | worker garbage is caught and repaired, bounded | worker returns broken diff once | verifier FAIL -> fix-agent -> retry -> pass; attempt=2 recorded |
| M-04 retry exhaustion | no infinite loop; honest failure | worker returns garbage always | stops at max retries; run_end fail (not hang, not false pass) |
| M-05 verifier crash | crash distinguished from verdict | verifier script exits 2 mid-run | harness-error status, not task-fail; surfaced in report |
| M-06 interrupt/resume | no state corruption on kill | SIGTERM mid-stage | locks released, goal registry freed, resume or clean abandon |
| M-07 concurrent runs | parallel writers isolated | two scripted lanes at once | no ledger interleave corruption; worktree isolation holds |
| M-08 hook failure | fail closed, not silent | gate script missing/nonzero | run halts with named hook; never silently skips the gate |
| M-09 malformed intake | garbage in is rejected early | empty/contradictory brief | classify/grill rejects; no downstream stage runs |
| M-10 illegal transition | board state machine holds | force queued -> shipped | transition rejected with reason |
| M-11 termination contract | runs never end on a question | scripted stage emits a question | loop answers or fails; run_end never status=question |
| M-12 append-only ledger | evidence is immutable | rerun same scenario | prior rows byte-identical; new rows appended |

## L2 · Stage quality (golden inputs, per stage/model change, cents)

Each workflow stage is an artifact -> artifact function benched in isolation on frozen
real artifacts. This is where per-part model profiles come from.

| Case | Stage | Golden input | Judge |
|---|---|---|---|
| S-01 spec quality | brief -> spec | frozen real briefs | rubric + spec-validate lenses |
| S-02 test-plan coverage | spec -> test plan | frozen specs | coverage vs hand-built matrix |
| S-03 worker build | spec -> diff | smoke-code-shaped task suites | hidden checks (shipped today) |
| S-04 verifier catch rate | diff -> verdict | real clean diff + N planted defects | catch rate vs false-alarm rate on the clean twin (ID-392) |
| S-05 review lenses | diff -> findings | seeded vulns/regressions per lens | seeded-recall + precision |
| S-06 fix-agent | finding -> patch | frozen verifier findings | fixes the finding, no collateral diff |

## L3 · End-to-end composition (fixture repo, nightly/release/model drop, dollars)

3-5 scenarios against a purpose-built sandbox repo with a real test suite, so
"shipped" is objective. 3x repeats; flake is a result, not noise.

| Case | Scenario | Expected signal |
|---|---|---|
| E-01 clean brief | brief -> shipped PR, default routing | shipped; yield/cost/wall baselines |
| E-02 ambiguous brief | brief with a planted contradiction | grill catches it; never ploughs through |
| E-03 landmine repo | fixture repo with a planted pitfall | research-pitfalls or a verifier catches it pre-ship |
| E-04 kit-off twin | E-01 with gates/verifiers off | the headline delta: what the kit adds |
| E-05 stability probe | E-01 x3 same config | flake rate; variance bounds on the baselines |

## Reporting contract

Every case, at every layer, emits the same event stream (README "Event protocol") and
lands in the same fact table with `layer` and `case` dimensions. The TUI renders a run
live; `render` produces the scoreboard; failures carry fingerprints (the verbatim
failing case/step), never just a count.
