# Proof of done: deterministic two-tier handoff (token-optim-v3 SG-02)

| | |
|---|---|
| **Profile** | feature (orchestrator handoff generation) |
| **Proof class** | behavioral , deterministic generator + orchestrator wiring, captured |
| **Lane** | normal |
| **Canonical** | this file |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | The orchestrator emits the two-tier handoff (HANDOFF.md hot + DECISIONS.md warm) deterministically from the finishing session's transcript, no LLM in the handoff path | PASS | R1 (13f), R2 |
| AC2 | Deterministic: same transcript + args + date -> byte-identical output (`cmp`-clean) | PASS | R1 (13a) |
| AC3 | Fidelity: every hand-labeled load-bearing anchor appears in the combined two-tier output; the negative control does not (no hallucination) | PASS | R1 (13c) |
| AC4 | Contract preserved: HOT carries next-sub-goal + grounded read-pointers; WARM carries invariants + dead-ends (SPEC-087 Mech B fields unchanged) | PASS | R1 (13d), R2 |
| AC5 | Default behavior unchanged: with the flag off, the per-session invocation is byte-identical and no regeneration/capture happens | PASS | R1 (13g) + all 12 prior orchestrate tests still green |
| AC6 | No-LLM contract: generator + ported extractor import no network/model libs | PASS | R1 (13e) |
| AC7 | Append-only stays honest: re-running on the same transcript is idempotent (no duplicate DECISIONS block) | PASS | R1 (13b) |
| AC8 | A/B turns-to-first-correct-action(B) <= (A) on a live cold-resume | **DEFERRED to gate** | see §5 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `lib/goal/handoff-gen` (+ `lib/goal/handoff/handoff_gen.py`, `lib/goal/handoff/cc_compact.py` ported verbatim from ops-toolkit SG-01) generates HANDOFF.md/DECISIONS.md deterministically; `lib/queue/orchestrate.sh` regenerates them after grounded completion when `DETERMINISTIC_HANDOFF=1` |
| Where | `lib/goal/handoff/`, `lib/goal/handoff-gen`, `lib/queue/orchestrate.sh` (config var + capture branch + post-completion step), `tests/test-orchestrate.sh` (TEST 13) |
| How it runs | `DETERMINISTIC_HANDOFF=1 orchestrate.sh run <dir>` captures the session to `.orchestrate/<id>.stream.jsonl`, then runs `handoff-gen` on it for the next sub-goal |
| Reversibility | flag defaults off; removing the var disables the whole path with zero change to the default loop |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-06-30 | `bash tests/test-orchestrate.sh` | 0 | PASS (56/56; 8 new SG-02 cases 13a-13g) |
| R2 | 2026-06-30 | `lib/goal/handoff-gen <seed> --dir <tmp> --next-id SG-02 ...` | 0 | arm-B artifact captured (`runs/R2-arm-b-artifact.txt`) |

## 4. Artifact-level A/B (captured, free)

Same scenario (the SG-01 backoff transcript), two handoff artifacts, scored on what a cold-started
session needs to resume without re-discovery. Arm A is a representative hand-written LLM handoff
for this scenario (illustrative); arm B is the deterministic output (R2).

| Resumability criterion | Arm A (LLM-written) | Arm B (deterministic) |
|---|---|---|
| Always produced (never skipped) | depends on the model remembering | **yes, by construction** |
| Reproducible (same in -> same out) | no (free-text, varies per run) | **yes (`cmp`-clean, AC2)** |
| Next action present | usually | yes (first outstanding cue) |
| Read-pointers grounded in real touched files | sometimes fabricated | **yes, real paths + edit counts** |
| Decisions + dead-ends carried (warm) | often dropped to save space | yes (idempotent ledger) |
| Load-bearing anchors retained | model's discretion | **7/7 anchors, 0 hallucinated (AC3)** |

Read: arm B is at least as resumable on every criterion and strictly better on the ones that
caused the re-discovery tax (always-produced, reproducible, grounded). "Deterministic +
always-produced beats occasionally-excellent-but-skippable" (the sub-goal's quality bar).

## 5. Live A/B (deferred to the gate)

AC8's live turns-to-first-correct-action A/B requires two real cold-resume sessions and is the
EXPENSIVE Opus path in the SG-12 bench (`experiments/token-eval-bench/run-ablation.sh`). It is left
for Han at the gate (this is a `gate` sub-goal). To run it:

```
# add a det-handoff arm to the bench, then:
cd experiments/token-eval-bench && bash run-ablation.sh --arms "handoff det-handoff" --tasks mini-mega --trials 1
# expect: turns-to-first-correct-action(det-handoff) <= (handoff); tokens parity (handoff is text, not an LLM call)
```

The deterministic mechanism, its determinism, fidelity, no-LLM property, and orchestrator wiring
are all captured above; the live turns-to-green number is the only remaining confirmation.

## 6. Reproduce

```
cd <kit>; bash tests/test-orchestrate.sh                       # 56/56 incl. TEST 13a-13g
DETERMINISTIC_HANDOFF=1 lib/goal/handoff-gen tests/fixtures/handoff-det/seed.jsonl \
  --dir /tmp/h --next-id SG-02 --next-title x --date 2026-06-30 # arm-B artifact
```
