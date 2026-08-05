# SPEC-226: Gauntlet telemetry, logging, and learning integration

**Status:** BUILT (lands in the same PR as the gauntlet command; this spec records
the crosscheck and the contract)
Lane: normal

## Problem

`/kit:gauntlet` (side-flow 11) shipped with its own run-record contract but no
wiring into the kit's three existing measurement rails. Unwired, gauntlet runs are
invisible to gate telemetry, unparseable by observe, and their lessons never reach
the weekend paydown.

## Crosscheck (module by module)

| Rail | Current mechanism | Gauntlet fit | Change needed |
|---|---|---|---|
| Telemetry (gate-ledger) | `outcome <rid> <phase> start/end` brackets + `record <rid> <phase> ran/skipped`; phase names are free text (normalize_phase) | `gauntlet` is a legal phase today | Command must CALL it: bracket the run, record the verdict. No lib change |
| Observe (session subsystem) | Parses `[[QL-VERDICT round=N clean=BOOL findings=K]]` round markers from transcripts (test-plan-review-team precedent) | Same grammar fits a gauntlet round exactly | Command emits the marker per round. ZERO observe changes, that is the point of reusing the grammar |
| Logging (run record) | `docs/verification/` proof artifacts | ROUNDS.md already specced | Add per-round cost columns (wall-clock, tokens) so the record doubles as the economics telemetry |
| Learning (lib/learn, weekend-batch) | `gate-ledger.sh debt <rid> ... verdict=wave reason=...` rows collected by `learn debt collect` at paydown | A RECONSIDER halt is exactly a conscious, postponed lesson | Command writes one debt row on RECONSIDER; one log line when a finding graduates to Tier 1 |

## Contract (what the command now does)

1. **Bracket:** `bash lib/gate/gate-ledger.sh outcome <rid> gauntlet start` before
   round 1; `... outcome <rid> gauntlet end caught=<true if any finding>` after the
   verdict. Record: `... record <rid> gauntlet ran "rounds=N verdict=<V> unaided=<bool>"`.
2. **Round markers:** after each round's scoring, emit
   `[[QL-VERDICT round=N clean=<K==0> findings=K]]` in the session output, the
   exact grammar observe already parses.
3. **Cost columns:** ROUNDS.md's per-round row carries wall-clock and token cost.
   The record is the economics source; no second telemetry file.
4. **Learning rail:** on RECONSIDER, write
   `bash lib/gate/gate-ledger.sh debt <rid> significance=high worthiness=high
   verdict=wave reason="gauntlet: surface not converging | gaps: <list> | next: <one line>"`
   so the weekend paydown surfaces it. When a finding graduates into Tier 1
   (command rule 10), append one line to ROUNDS.md naming the finding and the new
   deterministic check, the graduation trail is itself a lesson record.

## Non-goals

- No new lib code, no observe parser changes, no new ledger verbs. The whole spec
  is the command using existing rails.
- No automatic learning-note authoring from findings; the debt row points the
  human at the run record, the paydown decides what to keep.

## Verification

- Fixture check: a transcript containing two gauntlet round markers parses in
  observe's round-marker path identically to a test-plan-review-team transcript
  (same grammar, no code change to verify beyond the fixture).
- Ledger round-trip: after a dry gauntlet bracket (`start`, `record`, `end`),
  `gate-ledger.sh outcome-read <rid> gauntlet` returns the duration.
- Debt row: a RECONSIDER debt line appears in `learn debt collect` output for the
  rid (same rail as grill self-answer rows).
- First live gauntlet run (foundation-workers SPEC-018 T9) records all four:
  bracket, markers, cost columns, and (if RECONSIDER) the debt row.
