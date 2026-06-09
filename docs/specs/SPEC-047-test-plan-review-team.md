# SPEC-047: /kit:test-plan-review-team (adversarial test-design critique)

Status: Implemented
Date: 2026-06-09
Relates-to: SPEC-046 (verification framework, the spine + QL-VERDICT contract), SPEC-018 (test plan per spec, the `## Test plan` home + drift guard), SPEC-031 (V-model), SPEC-016/023 (devs-team / visual-team team pattern), docs/verification/test-design-standard.md (the standard this executes)

## Problem

The kit reviews two of the three V-model artifacts adversarially and skips the third:

- The **spec** gets `/kit:spec-validate` (5 lenses, pre-implementation).
- The **code** gets `/kit:review-team` (3 lenses, post-implementation).
- The **test design** , the bridge between them , gets neither. `/kit:test-plan` writes a `## Test plan`
  coverage matrix into the spec, and `/kit:execute` runs it unreviewed.

The quality bar for a test design exists as reference (`docs/verification/test-design-standard.md`: coverage
rule, test ladder, falsifiability, one-source/three-roles, sign-off checklist) but has **no executor**. So
coverage gaps, weak/fake negative controls, non-runnable proofs, and flaky designs only surface AFTER
`/kit:execute` runs , as retry loops, surprise RED runs, or "we never covered that" post-hoc.

## Solution

A new command `/kit:test-plan-review-team` that critiques a spec's `## Test plan` via 5 parallel
adversarial lenses and tightens it through a bounded revise loop, slotted between `/kit:test-plan` and
`/kit:execute`. It mirrors `/kit:devs-team` (same team machinery, one altitude down) and is **report-only**
(never blocks `/kit:execute`).

### Command contract (`commands/test-plan-review-team.md`)

- **Resolve** the active spec (branch-aware, spec-first) and read its `## Test plan` + `## Acceptance
  Criteria` + named failure modes. No `## Test plan` -> tell the user to run `/kit:test-plan`, stop.
- **5 lenses, in parallel** (read-only Task subagents, inline prompts , no per-lens agent files, like
  devs-team). Each encodes a slice of `test-design-standard.md`:
  1. Coverage completeness (every AC <-> a test; category matrix; failure modes covered).
  2. Oracle & falsifiability (credible negative control per load-bearing case; real oracle, not "should work").
  3. Feasibility & reproducibility (concrete pasteable isolated proofs; honest TBD/no-check).
  4. Test-ladder & boundary depth (climbs to a real-state run for stateful/behavioral; edges enumerated).
  5. Determinism & maintainability (flakiness sources mitigated; env pinned; CI/sandbox-runnable).
- **Bounded revise loop**: if findings > 0 and round < 3, a DISTINCT reviser subagent (producer != reviewer)
  revises the `## Test plan`, then re-critique. `[[QL-VERDICT round=N clean=BOOL findings=K]]` per round;
  findings must strictly fall (non-falling -> stop). Stop early at 0.
- **Write + report**: append `## Test plan critique` to the spec (replace-not-stack), with rounds, findings
  by severity, the 5 scores, and a `SOLID / REVISE / RECONSIDER` verdict. Never blocks.

## Acceptance criteria

- [x] AC1: `commands/test-plan-review-team.md` exists, dispatches 5 lenses in parallel, writes
      `## Test plan critique` spec-first (replace-not-stack).
- [x] AC2: The bounded revise loop uses a distinct reviser (producer != reviewer), caps at 3 rounds, emits
      the `[[QL-VERDICT ...]]` marker, and enforces strictly-falling findings.
- [x] AC3: Report-only , the command never blocks `/kit:execute`; verdict vocabulary is SOLID/REVISE/RECONSIDER.
- [x] AC4: The 5 lenses map to `docs/verification/test-design-standard.md` (named in the command's lens text).
- [x] AC5: A meta-test pins the literal `## Test plan critique` heading + the `spec-first` write target
      (drift guard, SPEC-018/023 shape); `tests/test-meta.sh` stays green.
- [x] AC6: The V-model doc (SPEC-031) names the test-design-review node between test-plan and execute.

## Test plan

Date: 2026-06-09
Source: this spec's ## Acceptance criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | command file exists + dispatches 5 lenses + writes `## Test plan critique` spec-first | happy-path | AC1, AC3 | grep finds the heading, `spec-first`, 5 numbered lenses, SOLID/REVISE/RECONSIDER | `grep -c` assertions in `tests/test-meta.sh` |
| 2 | meta-test pins the critique heading + spec-first; suite stays green | regression | AC5 | new pins PASS; prior 390 pins unbroken | `bash tests/test-meta.sh` |
| 3 | loop caps at 3 rounds + QL-VERDICT + strictly-falling | happy-path | AC2 | command text states cap=3, the marker, the strictly-fall rule | `grep -F` for `round`, `strictly`, `[[QL-VERDICT` |
| 4 | lenses name the standard | happy-path | AC4 | `test-design-standard.md` referenced in the lens block | `grep -F 'test-design-standard.md'` |
| 5 | dogfood: critique a real `## Test plan` with a seeded gap | live | AC1, AC2 | Coverage+Oracle lenses raise CRITICAL (RED-as-expected), loop closes the gap, findings fall | recorded run in `docs/verification/test-plan-review-team.md` |
| 6 | V-model names the node | happy-path | AC6 | SPEC-031 contains the test-design-review node | `grep -F 'test-plan-review' docs/specs/SPEC-031-*.md` |

### Coverage notes
- Categories skipped: security/abuse, failure-injection , this is a docs/command artifact (prompt text +
  meta-pins), not a network/data surface; the proof class is behavioral (a command's output behavior), not
  stateful. No untrusted input path to abuse.
- This is a coverage TARGET, not an exhaustive list.

## Verification

Proof at `docs/verification/test-plan-review-team.md` (table-first per ADR-0026, dogfooding the new
convention): the meta-test green run + a dogfood critique run on a seeded-gap test plan showing the negative
control (Coverage/Oracle lenses bite) and convergence.

## Out of scope

- Making `/kit:test-plan` a roundtable. It stays the deterministic matrix-writer (personas belong in the
  adversarial review, per its own rationale, SPEC-016 DEC-004).
- A hard gate. Report-only by decision (matches devs-team/visual-team; the team-never-blocks philosophy).
- Per-lens agent files. The lenses are inline (devs-team shape); minimum infra.
