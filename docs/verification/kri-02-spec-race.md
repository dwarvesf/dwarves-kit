# Proof of done , kri-02-spec-race (SPEC-128 wavefront spec-number reservation)

Behavioral change: `spec-next.sh reserve` + orchestrate `_wave_run` dispatch reservation.
Spec: `docs/specs/SPEC-128-spec-reservation-race.md`. Branch: `feat/kri-02-spec-race`.

## Acceptance criteria -> confirmation

| # | Acceptance criterion | Evidence | Verdict |
|---|---|---|---|
| 1 | N concurrent `reserve` -> N distinct numbers (atomic claim) | test T2: 20 emitted / 20 distinct | PASS |
| 2 | a reserved number reads as TAKEN before its branch exists | test T3: check says TAKEN, next advances | PASS |
| 3 | NEGATIVE CONTROL: old `next` path DOES collide | test T4: 20 emitted / 1 distinct | PASS |
| 4 | SPEC-064 `next`/`check` contract byte-identical on empty ledger | test T5 + test-hooks 452/452 | PASS |
| 5 | reconcile: realized + TTL-expired reservations stop counting + pruned | tests T6, T7 | PASS |
| 6 | orchestrate `_wave_run` reserves + injects; degrades on failure | test T10 | PASS |

## Confirmation run-table

Command: bash tests/test-spec-reserve.sh
Exit: 0
Verdict: PASS
Detail: 23/23 assertions green. T2 (core concurrency) = 20 parallel `reserve` -> 20 distinct
numbers, zero collisions. T3 fold-in, T5 SPEC-064 contract, T6/T7 reconciliation, T8 repo
scope, T9 stale-lock reclaim, T10 orchestrate wiring + degrade path all green.

Command: bash tests/test-hooks.sh
Exit: 0
Verdict: PASS
Detail: 452/452. The SPEC-064 spec-next contract assertions (check flags a taken number ->
TAKEN + exit 1; next is a 3-digit number) still pass , the reservation fold-in is additive
and byte-identical on an empty ledger.

Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS
Detail: 667/667. No regression across the meta-integrity suite.

Command: bash tests/test-orchestrate-wavefront.sh
Exit: 0
Verdict: PASS
Detail: ALL PASS. The `_wave_run` reserve-injection change did not disturb the wavefront
scheduling or the flip-contract prompt-injection tests.

## NEGATIVE CONTROL

The proof must be able to observe a FAILURE, or a green run proves nothing. Two independent
negative controls:

1. **In-test negative control (T4):** the SAME harness that shows `reserve` never collides
   fires the OLD, un-reserved path , 20 parallel `spec-next.sh next` , and asserts it DOES
   collide. Observed: 20 emitted, 1 distinct (all identical). This proves the concurrency
   test can SEE a collision; the distinctness of `reserve` (T2) is therefore meaningful, not
   vacuous.

   Command: (T4, inside test-spec-reserve.sh) 20x parallel `spec-next.sh next`, no reserve
   Exit: 0
   Verdict: PASS (collision observed as designed: 1 distinct < 20)

2. **Revert -> RED -> restore:** removing the `reserve` subcommand's atomic claim (making it
   a bare `next` + append with no lock) makes T2 FAIL (concurrent claimers read the same max
   before either appends). Re-applying the mkdir-mutex restores GREEN. Mechanism: the mutex
   is the load-bearing property; without it the append-after-read is not indivisible.

   Verdict: PASS (the test is sensitive to the fix; the fix is what makes it green)

## Reproduce

```
cd ~/workspace/tieubao/dwarves-kit
git switch feat/kri-02-spec-race
bash tests/test-spec-reserve.sh        # 23/23, incl. T2 concurrency + T4 negative control
bash tests/test-hooks.sh               # 452/452 (SPEC-064 contract intact)
bash tests/test-orchestrate-wavefront.sh   # ALL PASS (wiring undisturbed)
```

Final Verdict: PASS
