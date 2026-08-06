# Lanes (user guide)

Not every change deserves the full ceremony. The lane decides how much of the
spine (guide: `spine.md`) your change rides. You do not pick a lane by feel;
the intake runs this tree:

```
        is it a defect / regression / failing test?
                 │ yes                │ no
                 ▼                    ▼
                bug          new work on an existing repo
        (debug loop first:   with no operate-layer docs?
         root cause before        │ yes        │ no
         any fix)                 ▼            ▼
                              backfill    how big / risky?
                                          ├─ trivial edit ......... tiny
                                          ├─ one bounded change ... normal
                                          └─ risk-list match ...... full

        when in doubt between two lanes, take the heavier one
```

What each lane costs and buys:

| Lane | Ceremony | You get |
|---|---|---|
| tiny | almost none; the one obvious edit | speed; no spec, no interview |
| normal | spec + test plan + execute + review | a contract and verification for one bounded change |
| full | the whole spine incl. spec-validate, deeper review | the safety net for risky, cross-cutting, or irreversible work |
| bug | debug loop before anything | a recorded root cause; no guess-fixes |
| backfill | operate-docs first | a repo the kit can actually drive afterward |

## What you do

- **Describe the change honestly; let the classifier route.** Downgrading
  ("it's tiny, trust me") is what the floor check exists to catch: a change
  that touches money, auth, migrations, or shared infra is full-lane no matter
  how small the diff.
- **Take the heavier lane on a tie.** The extra cost is one spec; the cost of
  the lighter lane being wrong is a production incident.
- **Expect escalation mid-flight.** If execute discovers the change is bigger
  than specced, the lane re-classifies upward. That is the system working, not
  scope creep by the agent.

## Common questions

- **"Why did my one-line change get the full lane?"** The risk list is about
  blast radius, not diff size. One line in a payment path is full-lane.
- **"Can I force tiny?"** You can say so explicitly; the kit records that as
  your call. The floor check will still refuse silently unsafe downgrades.
