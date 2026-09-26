# SPEC-314: spec-validate gains a sustainability lens

**Status:** VALIDATED
Lane: normal
Type: spec-feature
**Proof:** `docs/verification/sustainability-lens.md`; `tests/test-meta.sh`, the spec-validate roster block.

## Problem

`/kit:spec-validate` runs six lenses. Each one judges whether the design is right on the day it ships. None asks what the design costs to keep alive a year later.

The coverage gap, by dimension:

| Dimension | Covered today |
|---|---|
| Growth, coupling, over-engineering | Reviewer 4 and Reviewer 5 |
| Recovery from an incident | Reviewer 2, partly |
| Run cost (infra, API calls, model tokens, quota) | no |
| Owner, and the signal that shows it has died | no |
| Dependency lifespan (vendor API, pinned version, upstream patch, credential expiry) | no; Reviewer 3 asks whether an API is stable today |
| Retirement path | no |
| Handover to someone who did not build it | no; the N7 note is advisory and names no question |

The operator's estate keeps paying for these gaps: launchd jobs that die silently, a heartbeat that pages forever after its job was retired, a 1Password rotation that leaves stale copies, vendored patches that drift from upstream. Six lenses would pass any of those specs.

## Contract

- `commands/spec-validate.md` gains `### Reviewer 7: Sustainability Critic`, placed after Reviewer 6. It is advisory, like Reviewers 1-5.
- Reviewer 7 first decides whether the spec is long-lived. A spec is long-lived when it creates, or moves onto a new host or vendor, something that keeps running or keeps costing after merge: a scheduled job, daemon, service, or deploy target; a data store outside the repo; a new external dependency (package, vendor API, fork, or local patch); a credential; or per-use paid calls. An edit to an in-repo hook, script, or ledger that the repo's own tests already cover is not long-lived.
- A spec that is not long-lived gets a one-line pass, `not long-lived: <why>`, and no findings.
- A long-lived spec gets five questions. A missing or hand-waved answer is a warning.
  1. Run cost: the monthly cost at expected load, and any unbounded cost path.
  2. Owner and liveness: who owns it after merge, and which signal fires when it stops.
  3. Dependency lifespan: which dependency breaks or disappears first, and what happens then.
  4. Retirement: how it is turned off with no orphaned schedule, heartbeat, secret, or data.
  5. Handover: whether someone who did not build it can debug and rebuild it from the repo.
- Reviewer 7 does not repeat Reviewer 2 (incident recovery) or Reviewer 5 (growth and coupling).
- Reviewer 7 carries a calibration block like Reviewers 5 and 6: flag only a gap that would let the thing die silently, cost without bound, or outlive its purpose. A short answer in `## After state` or `## Failure modes` counts.
- The lens text avoids the word `references`: `tests/test-design-record.sh` pins its absence from the command.
- The heading reads `## The 7 reviewers`. The frontmatter says `7 specialist lenses ... (6 advisory, 1 blocking on the design record)`. The output-format sentence says `all 7 reviewers`. Every `Reviewers 1-5` advisory phrase (the run-order sentence, Reviewer 6's intro, the Exception under Output format) says `Reviewers 1-5 and 7`. Reviewer 6 stays the one blocking reviewer.
- Reviewer 7 records nothing new in the gate ledger. Its findings land in the existing report and the existing `Validate` record counts.

## Picture

```
 /kit:spec-validate
    |
    v
 R1 security -> R2 failure -> R3 assumptions -> R4 scope -> R5 design -> R6 design record -> R7 sustainability
                                                                          (BLOCKING)          (advisory)
                                                                                                  |
                                                         long-lived? --no--> "not long-lived: <why>", pass
                                                              |
                                                             yes
                                                              v
                                          cost / owner+liveness / dependency lifespan / retirement / handover
                                                              |
                                                              v
                                           unanswered -> Warning in the report; Verdict rules unchanged
```

## Design

obvious: one more advisory prompt section in an existing command. No code path, schema, or control flow changes, and Reviewer 6's blocking rule is unchanged.

Approaches considered:

| Approach | Why not |
|---|---|
| Fold the five questions into Reviewer 5 | Reviewer 5 already carries six bullets plus a calibration block. A separate lens keeps its own long-lived gate, so short-lived specs skip it in one line. |
| Add a `## Upkeep` section to the spec template | Every spec would owe a new section, most of them short-lived. The reviewer reads the existing `## Failure modes`, `## After state`, and `Not covered` text instead. Revisit if Reviewer 7 warns on most long-lived specs. |
| Insert the lens as Reviewer 6 and renumber | Tests and docs pin `Reviewer 6: Design Record Auditor` by name. Appending as Reviewer 7 keeps those pins. |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the lens | `commands/spec-validate.md` | the Contract above |
| T2: roster tests | `tests/test-meta.sh` | the `## The 6 reviewers` assertion becomes `## The 7 reviewers`; new asserts for `^### Reviewer 7:` and for no `BLOCKING` inside the Reviewer 7 section (awk-scoped from `### Reviewer 7` to `## Output format`); the count-drift guard also rejects `6 reviewer` and `6 specialist lenses` |
| T3: docs | `docs/MANUAL.md`, `docs/architecture.md:129,193`, `docs/workflow-paths.md:94,242,376`, `docs/tiers.md`, `docs/WORKFLOW.md:1354`, `README.md:337`, `docs/CHANGELOG.md`, regenerated `docs/FEATURES.md` | every live spec-validate count says 7. Untouched: `docs/architecture.md:113`, `docs/workflow-paths.md:257`, `tests/test-meta.sh:826`, which count `/kit:test-plan-review-team` lenses |
| T4: eval | `tests/fixtures/sustainability-lens/long-lived-gaps.md`, `tests/fixtures/sustainability-lens/short-lived.md`, `docs/verification/sustainability-lens.md` | the three eval rows below, run and recorded |

## Test plan

The lens is prompt text, so a grep proves presence and a behavioral eval proves it works.

| Case | Setup | Expected |
|---|---|---|
| Roster | `tests/test-meta.sh` | the four T2 assertions pass |
| Catches a gap | a fresh subagent runs the new Reviewer 7 text on a fixture spec that adds a nightly launchd job calling a paid model, with no heartbeat, no owner, no retirement step | warnings name the liveness gap, the unbounded cost, and the missing retirement path |
| Stays quiet | the same reviewer on a fixture spec that renames a CLI flag | one line, `not long-lived: ...`, no warnings |
| Negative control | a fresh subagent runs the six-reviewer command from `master` on the launchd fixture, twice | no finding in either run names run cost, owner or liveness, retirement, or handover; one such finding means the gap claim is wrong |

Each eval runs on a fresh Sonnet subagent with the command text and the fixture only. The catch and quiet cases run once each. LLM output varies, so the eval proves the lens can fire, not that it always fires.

## Verification

`bash tests/test-meta.sh`, `bash tests/test-design-record.sh`, `bash tests/test-picture-section.sh`, and `bash tests/test-understanding-wiring.sh` exit 0. `bash tests/run-all.sh --changed` exits 0. The three eval cases are recorded in `docs/verification/sustainability-lens.md`.

## After state

`/kit:spec-validate` runs seven lenses. A long-lived spec with no liveness signal, no cost bound, or no retirement path gets a warning before build. A short-lived spec pays one line.

Not covered: the lens stays advisory, so a spec can ship with the warnings open. No code checks whether a spec's liveness answer is wired; `job-monitoring-onboarding` still owns that at build time.

## Decision Log

- Advisory, not blocking. Reviewer 6 stays the only blocking lens.
- Validation (six lenses, APPROVED, design record PASS, design-bearing=no) raised seven warnings, all folded in: the advisory-set phrases, two missed docs and two lines to leave alone, the T2 test details, the `references` pin, a narrower long-lived trigger plus a calibration block, a T4 for the eval, and the named test suites.
