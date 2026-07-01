# Proof of done: two-tier feed-forward handoff (SG-02)

| | |
|---|---|
| **Profile** | feature (behavioral) |
| **Proof class** | behavioral: real orchestrator injection flow + tests + negative control |
| **Spec** | SPEC-087 Mechanism B (two-tier contract) |
| **Canonical** | this file |

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | HOT `HANDOFF.md` injected in full (overwritten each transition) | PASS | R1 (6a), R2 |
| AC2 | HOT handoff is size-capped (head + notice over `HANDOFF_MAX_LINES`) | PASS | R1 (6d) |
| AC3 | WARM `DECISIONS.md` injected as a POINTER only, body not inlined | PASS | R1 (6b) |
| AC4 | "report IN the records, not your response" wording injected | PASS | R1 (6c) |
| AC5 | prompt injected via temp file on stdin, not an argv arg | PASS | R2, code |
| AC6 | contract documented + sample pair committed | PASS | SPEC-087 Mechanism B, `tests/fixtures/handoff-sample/` |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | hot/warm split in `_build_prompt` (full+capped vs pointer-only) + stdin temp-file injection |
| Where | `lib/orchestrate.sh` (`_build_prompt`, run path), `tests/test-orchestrate.sh` (TEST 6a-6d), `tests/fixtures/handoff-sample/`, SPEC-087 Mechanism B |
| How it runs | orchestrator inlines HANDOFF.md (capped), points at DECISIONS.md, pipes the prompt via `< tmp` |
| Reversibility | additive: no HANDOFF/DECISIONS -> prior behavior; cap default 80 lines |

## 3. Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-06-29 | `bash tests/test-orchestrate.sh` | 0 | PASS (19/19, incl. 4 two-tier + box-not-flipped negative control) |
| R2 | 2026-06-29 | capture-mock run: prompt received on stdin, hot body present, warm body absent | 0 | PASS |

## 4. Run detail

### R1 GREEN, full suite incl. negative control
- Command: `bash tests/test-orchestrate.sh`
- Output (tail): `... PASS hot HANDOFF capped at HANDOFF_MAX_LINES with a truncation notice / ---- / ALL PASS`
- Negative control (pre-existing, still green): a session that does not flip its ROADMAP box
  halts the loop nonzero. Confirms the harness can go RED.
- Mock-injection change: all mocks now read the prompt from stdin (`prompt=$(cat)`), proving the
  stdin injection path end-to-end; assertions unchanged from phase 1.

### R2 two-tier injection shape (TEST 6a-6d)
- 6a: a deep HANDOFF body line (`Read-pointers (verified this run)`) is present, no truncation
  notice -> full injection under cap.
- 6b: `WARM LEDGER` + `DECISIONS.md` present, but the ledger's body line (`append-only:
  invariants + dead-ends, read on demand`) is absent -> pointer-only.
- 6c: `report findings IN the records` present.
- 6d: with `HANDOFF_MAX_LINES=5` over a 20-line handoff, `LINE-5` present, `LINE-20` absent,
  `truncated at 5/20 lines` present.

## 5. Reproduce
```
git switch feat/two-tier-handoff
bash tests/test-orchestrate.sh        # 19/19 ALL PASS
```
