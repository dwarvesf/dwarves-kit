# Proof of done: ID-398 failure-policy vocabulary

Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | close/escalate/continue vocabulary defined, mapped onto existing verdict grammars, doesn't rename any wired verdict string | Met | `docs/patterns/failure-policy.md` |
| 2 | `/kit:execute`'s retry-then-escalate path names its policy at the task level and the Build-phase outcome call | Met | `commands/execute.md` (Step 2c/2d, Step 4 outcome call) |
| 3 | root-cause-vs-symptom is a separately-judged review step, not a clause | Met | `commands/review.md` new "Root cause vs symptom" subsection, own `root-cause:` finding-key |
| 4 | the named outcome lands in the gate ledger as an additive field, an existing reader consumes it | Met | `lib/gate/gate-ledger.sh` `outcome`/`outcome_read` `policy=` field; `lib/telemetry/lane-telemetry.sh` `report()` failure-policy breakdown |
| 5 | additive: old callers / old ledger lines unaffected | Met | R2 below (`tests/test-gate-outcome.sh` full suite, unrelated ACs 1-9 unchanged) |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | Optional `policy=<close\|escalate\|continue>` field on the SPEC-129 `OUTCOME` marker + an interpretive vocabulary doc + prose wiring in execute.md/review.md |
| Where | `lib/gate/gate-ledger.sh`, `lib/telemetry/lane-telemetry.sh`, `commands/execute.md`, `commands/review.md`, `docs/patterns/failure-policy.md`, `docs/briefs/DECISION-BRIEF-dag-wavefront.md` |
| How it runs | `gate-ledger.sh outcome <rid> <phase> end caught=<bool> policy=<val>` (emit); `outcome-read` (round-trip); `lane-telemetry.sh report` (aggregate) |
| Reversibility | `git revert` this commit; no schema/store/daemon added, pure additive text field |

## 3. Confirmation (runs)

| Run | When (UTC) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-08-27T16:58Z | `bash tests/test-gate-outcome.sh` | 0 | PASS 25/25 |
| R1b | 2026-08-27T16:58Z | `bash tests/test-lane-telemetry.sh` | 0 | PASS 29/29 |
| R2 | 2026-08-27T17:05Z | same two commands, with `lib/gate/gate-ledger.sh` + `lib/telemetry/lane-telemetry.sh` reverted to parent commit `f5e10cb` (`git checkout f5e10cb -- <files>`) | 1 | NEGATIVE CONTROL: RED (5 of the new/touched assertions fail) |
| R3 | 2026-08-27T17:06Z | `git checkout HEAD -- lib/gate/gate-ledger.sh lib/telemetry/lane-telemetry.sh` then re-run R1/R1b | 0 | RESTORE: PASS 25/25 and 29/29 again |
| R4 | 2026-08-27T16:55Z | `bash tests/test-meta.sh` | 1 | pre-existing baseline: 808/815, identical 7 failures reproduced on unmodified `master` at the same commit (side-by-side run, not a stash) |
| R5 | 2026-08-27T16:52Z | `bash tests/test-outcome-emit-sweep.sh` | 1 | pre-existing baseline: 49/51, identical 2 failures reproduced on unmodified `master` |

## 4. Run detail

### R1 GREEN

```
Command: bash tests/test-gate-outcome.sh
Exit: 0
Verdict: PASS
=== 25/25 passed, 0 failed ===
```

### R1b GREEN

```
Command: bash tests/test-lane-telemetry.sh
Exit: 0
Verdict: PASS
=== 29/29 passed, 0 failed ===
```

### R2 NEGATIVE CONTROL

```
Command: git checkout f5e10cb -- lib/gate/gate-ledger.sh lib/telemetry/lane-telemetry.sh
       && bash tests/test-gate-outcome.sh
       && bash tests/test-lane-telemetry.sh
Exit: 1
Verdict: RED-as-expected

test-gate-outcome.sh: 23/25 passed, 2 failed
  FAIL AC10 policy=escalate round-trips via outcome-read
  FAIL AC10 bad policy value rejected (rc=0)
test-lane-telemetry.sh: 26/29 passed, 3 failed
  FAIL ID-398: report has a failure-policy section
  FAIL ID-398: report counts an escalate outcome
  FAIL ID-398: report counts a continue outcome
```

Every OTHER assertion in both files (AC1-AC9, the pre-existing SPEC-099/SPEC-110 render/report
assertions) stayed PASS with the implementation reverted, confirming the additive property:
reverting `policy=` support breaks only the `policy=`-specific assertions, nothing else.

### R3 ROLLBACK/RESTORE

```
Command: git checkout HEAD -- lib/gate/gate-ledger.sh lib/telemetry/lane-telemetry.sh
       && bash tests/test-gate-outcome.sh && bash tests/test-lane-telemetry.sh
Exit: 0
Verdict: PASS
25/25 and 29/29, all 5 previously-red assertions back to green.
```

### R4 baseline (pre-existing, unaffected)

```
Command: bash tests/test-meta.sh          (run in this worktree)
Exit: 1
Verdict: 808/815 -- 7 failures, all pre-existing

Command: bash tests/test-meta.sh          (run in /Users/tieubao/workspace/dwarvesf/dwarves-kit,
                                            master @ f5e10cb, this branch's own base)
Exit: 1
Verdict: 808/815 -- the identical 7 failures (agent devops-triage / V-model lens / architecture.md
inventory count / README agents table count / AGENTS.md intake story / review-agent naming axis /
docs/FEATURES.md freshness), none in a file this change touches.
```

### R5 baseline (pre-existing, unaffected)

```
Command: bash tests/test-outcome-emit-sweep.sh
Exit: 1
Verdict: 49/51 -- the same 2 pre-existing failures reproduced identically on unmodified master
(AC1/AC2 no-orphan sweep; unrelated to the `outcome ... build end` line this branch edits, which
stays on a single line and keeps matching the sweep's per-line regex).
```

## 5. Reproduce

```
bash tests/test-gate-outcome.sh && bash tests/test-lane-telemetry.sh
```
