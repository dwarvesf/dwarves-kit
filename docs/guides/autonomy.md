# The autonomy dial (user guide)

How much the kit does before checking with you is YOUR setting, per run, set by
how you phrase the ask. Four positions:

```
 propose ─── low (default) ─── high ─── max
    │            │               │        │
 plans only,  stops at every  stops only  stops only at the
 runs nothing advisory        at the 4    4 hard stops or a
              checkpoint      hard stops  real blocker; runs
                              + the       all the way to a PR
                              push/PR
```

| You say | Position | It stops at |
|---|---|---|
| "propose it, don't run anything" | propose | after planning; waits for go |
| "run it, check with me at each phase" | low (default) | every advisory phase checkpoint |
| "run the lane, only stop at hard stops" | high | the 4 hard stops + the push/PR |
| "run it all the way to a PR, your call" | max | only the 4 hard stops + a real blocker |

Two things never move with the dial:

1. **The 4 hard stops hold at every position** (guide: `gates-and-proof.md`).
   Max autonomy is not gate bypass; it is fewer courtesy check-ins.
2. **Decisions taken alone get recorded.** At high/max, a judgment call you
   would have been asked about lands on a ledger instead of interrupting you;
   you review the calls afterward, not the pauses during.

## What you do

- **Match the dial to reversibility, not to trust.** Reversible work on a
  branch tolerates max; anything outward-facing (a send, a publish, a deploy)
  deserves low even from an agent you trust, because the cost of a wrong
  check-in is seconds and the cost of a wrong send is not.
- **Say the position in the ask.** The phrasing table above IS the interface;
  there is no config file to edit per run.
- **Review the ledger after a high/max run.** The recorded solo decisions are
  where course corrections live; skipping the review converts recorded
  decisions back into silent ones.

## Common questions

- **"It asked me something at max autonomy."** Then it hit a hard stop or a
  genuine fork with irreversible consequences either way. That is the designed
  floor, not disobedience.
- **"It did NOT ask me something I wanted to weigh in on."** Lower the dial
  next run, or name the concern in the ask ("check with me before touching the
  schema"); named concerns become checkpoints at any position.
