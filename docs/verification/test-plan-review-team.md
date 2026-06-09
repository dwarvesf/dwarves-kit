# Proof of done: /kit:test-plan-review-team (SPEC-047)

| | |
|---|---|
| **Profile** | feature (a new kit command) |
| **Proof class** | behavioral (the command's critique output) |
| **Spec** | [`docs/specs/SPEC-047-test-plan-review-team.md`](specs/SPEC-047-test-plan-review-team.md) |
| **Canonical** | this file (table-first per ADR-0026) |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | command exists, dispatches 5 lenses, writes `## Test plan critique` spec-first | PASS | R1 |
| AC2 | bounded revise loop: distinct reviser, cap 3, QL-VERDICT, strictly-falling | PASS | R1 |
| AC3 | report-only; SOLID/REVISE/RECONSIDER verdict | PASS | R1 |
| AC4 | the 5 lenses map to `test-design-standard.md` | PASS | R1 |
| AC5 | meta-test pins the heading + spec-first + loop contract; suite green | PASS | R2 |
| AC6 | V-model (SPEC-031) names the test-design-review node | PASS | R2 |
| AC7 | the lenses are falsifiable: they raise CRITICAL on a seeded-gap plan, clear on a good one | PASS | R3 (neg), R4 (green) |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `/kit:test-plan-review-team`: 5 parallel test-design lenses + a bounded revise loop, between `/kit:test-plan` and `/kit:execute` |
| Where | `commands/test-plan-review-team.md`; pins in `tests/test-meta.sh`; cross-refs in SPEC-031, `test-design-standard.md`, `architecture.md` |
| How it runs | `/kit:test-plan-review-team` resolves the active spec, dispatches the lenses via Task, appends `## Test plan critique` |
| Reversibility | docs/command only; `git revert`. No code, no host state |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 static contract | 2026-06-09 | `grep` pins (heading, spec-first, 5 lenses, QL-VERDICT, standard) | 0 | PASS |
| R2 meta-test | 2026-06-09 | `bash tests/test-meta.sh` | 0 | PASS (394/394) |
| R3 NEGATIVE CONTROL | 2026-06-09 | dispatch Coverage + Oracle lenses on a seeded-gap `## Test plan` | n/a | RED-as-expected (both CRITICAL, 2/10) |
| R4 green | 2026-06-09 | same 2 lenses on a fixed `## Test plan` | n/a | PASS (no CRITICAL, 7/10) |

## 4. Run detail

### R2 GREEN, meta-test
- Command: `bash tests/test-meta.sh`
- Exit: 0
- Output (excerpt):
  ```
  PASS test-plan-review-team.md exists + writes '## Test plan critique' spec-first (SPEC-047)
  PASS test-plan-review-team.md carries the QL-VERDICT loop + encodes test-design-standard.md (SPEC-047)
  Passed: 394 / 394
  ```
- Verdict: PASS. New pins green; the prior suite (incl. the architecture inventory row count) stays green after adding the command's inventory row.

### R3 NEGATIVE CONTROL, the lenses bite on a seeded-gap plan
The gapped plan: AC2 ("reject invalid config with a clear error") has NO test row; case 2 is "should work" / proof TBD.
- Command: dispatch the Coverage + Oracle lenses (the command's inline lens prompts) via Task on the gapped plan.
- Exit: n/a (subagent findings)
- Output (excerpt):
  ```
  Coverage lens: CRITICAL: AC2 has zero test coverage (orphan AC). ... SCORE: 2/10
  Oracle lens:   CRITICAL: No negative controls anywhere; CRITICAL: AC2 zero coverage;
                 HIGH: case 2 "should work" is unfalsifiable; HIGH: proof is TBD. SCORE: 2/10
  ```
- Verdict: RED-as-expected. Both lenses raise CRITICAL on the exact seeded gaps (uncovered AC, missing negative control, unfalsifiable oracle). Proves the lenses are not trivially green.

### R4 green, the same lenses clear on a fixed plan
The fixed plan: AC2 covered by a failure-injection case + a boundary case; concrete pytest proofs; named negative controls.
- Command: same 2 lenses on the fixed plan.
- Output (excerpt):
  ```
  Coverage lens: every AC -> >=1 case, every case -> an AC, matrix present. No CRITICAL. SCORE: 7/10
  Oracle lens:   oracles checkable, proofs concrete, negative controls exist. No CRITICAL. SCORE: 7/10
  ```
- Verdict: PASS. CRITICAL findings cleared, scores 2/10 -> 7/10. The gap closing is exactly what the revise loop drives toward; the lenses reward a real plan and punish a hollow one.

## 5. Reproduce

```sh
# static + meta
grep -F '## Test plan critique' commands/test-plan-review-team.md
bash tests/test-meta.sh                          # 394/394
# behavioral: run the lane on a real spec that has a ## Test plan
/kit:test-plan-review-team                        # in a repo/branch with an active spec
```

Note: R3/R4 dispatched 2 of the 5 lenses (Coverage, Oracle) as the falsifiable core; the full command runs
all 5 + the bounded reviser loop. The negative control (R3) is the load-bearing proof: a deliberately broken
test plan must produce CRITICAL findings, and it does.
