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
                                             (suggested; you assign it)

        default to normal; the diff floor covers hard paths
```

What each lane costs and buys:

| Lane | Ceremony | You get |
|---|---|---|
| tiny | almost none; the one obvious edit | speed; no spec, no interview |
| normal | spec + fresh-context validation + light test plan + execute + review | a contract and verification for one bounded change |
| full | the whole spine incl. spec-validate, deeper review | the safety net for risky, cross-cutting, or irreversible work |
| bug | debug loop before anything | a recorded root cause; no guess-fixes |
| backfill | operate-docs first | a repo the kit can actually drive afterward |

## What you do

- **Describe the change honestly; let the classifier route.** The classifier
  starts from `normal` and never picks `full` from the words of a task. When
  the words look risky it prints one suggestion line, and you decide whether
  to assign `full`. Downgrading ("it's tiny, trust me") is what the floor
  check exists to catch.
- **Let the diff set the floor.** At push, the ship gate looks at the files
  you changed. A migration, auth or secrets file, a CI workflow, kit config,
  or an added data-loss line gets the full lane's gates whatever lane the spec
  says. It only runs where the repo turned `lane_gates` on. A repo can add its
  own paths with `[lanes] extra_hard_paths`.
- **A tie goes to the heavier lane when you can see the risk.** The extra
  cost is one spec; the cost of the lighter lane being wrong is a production
  incident. The normal lane already requires a fresh-context validation and
  a review, which catch what no file path shows (authz, an API contract, an
  external provider).
- **Expect escalation mid-flight.** If execute discovers the change is bigger
  than specced, the lane re-classifies upward. That is the system working, not
  scope creep by the agent.

## Common questions

- **"Why did my one-line change get the full lane?"** Either you assigned it
  after a suggestion, or the diff floor caught a hard path. The risk list is
  about blast radius, not diff size: one line in a migration is full-lane at
  push.
- **"Can I force tiny?"** You can say so explicitly; the kit records that as
  your call. The floor check will still refuse silently unsafe downgrades.
