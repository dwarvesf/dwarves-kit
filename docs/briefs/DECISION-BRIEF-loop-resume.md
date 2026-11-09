# Decision brief: bounded loops resume from their own records

**Status:** decided; built in the same PR.
**Question:** several bounded loops keep their position (round number, clean streak, retry count) only in agent context. A context loss or a new session restarts them from zero. How do they resume without a new state store?

## Decision

A loop's position is derived from the record it already writes. No new store, no new daemon.

```
  loop writes its record every round        resume reads the same record
  ─────────────────────────────────         ────────────────────────────
  gauntlet ROUNDS.md      [[QL-VERDICT ...]]  ┐
  spec ## Test plan critique  [[QL-VERDICT]]  ├──▶ lib/loop/ql-verdict.sh resume <file>
  ui-design / verify rounds   [[QL-VERDICT]]  ┘     round=<next> clean_streak=<k> last_findings=<n>
  greenlight retries   run ledger ACTION lines ──▶ gate-ledger.sh actions <rid> greenlight-retry sha=<head>
```

| Loop | Record it already writes | Resume reads |
|---|---|---|
| gauntlet | `ROUNDS.md` with one `[[QL-VERDICT round=N clean=B findings=K]]` per round | next round, consecutive clean rounds (the two-pass SOLID rule), last K |
| test-plan-review-team | the spec's `## Test plan critique` QL-VERDICT lines | next round, last K (the strictly-falling rule) |
| ui-design, verify | their QL-VERDICT lines | same |
| greenlight | nothing today | a new `ACTION` line per retry in the run ledger, counted per head sha |
| onboard | n/a | none: the wizard already re-detects every step |

## Rules

- **One parser for QL-VERDICT.** `lib/loop/ql-verdict.sh` owns the grammar `\[\[QL-VERDICT round=[0-9]+ clean=(true|false) findings=[0-9]+\]\]`; `lib/gauntlet/stats.sh` calls it instead of keeping its own copy. A malformed marker stays a loud error.
- **Resume is read-only.** It never edits a record. A missing record means round 1.
- **Greenlight keeps no store.** It appends `ACTION | greenlight-retry sha=<sha> n=<k>` through the existing `gate-ledger.sh action` verb, and counts those lines for the current head sha on start. A new head sha resets the budget, as today.
- **Prose calls the verb.** Each loop command runs resume at its start and continues from the printed round, instead of counting in context.

## Rejected

- A `kit-loops/` state store beside `kit-attempts/`: a second copy of facts the records already hold, which can drift from them.
- Persisting the onboard step: the wizard is idempotent and re-detects; a stored step could go stale.
