# Scenarios (user guide)

Everywhere you shape work with the kit, it will now surface SCENARIOS, the
situations your thing must survive, before anyone writes a test. You do not
invoke this; it rides the beats you already use. This guide is what you will
see and what a good scenario set looks like.

```
 you explore an idea ──── /kit:think ──► brief gains "Survival scenarios"
        │                                (3-5 situations, no test detail)
 you shape the design ── /kit:design ─► sketch refined, new promises inverted
        │
 you get interviewed ─── /kit:grill ──► Done= arrives WITH 2-3
        │                               "must NOT happen" scenarios
 the spec hardens ────── /kit:spec ───► Edge Cases seeded from the sketch,
        │                               extended by a full pass
 tests get derived ───── /kit:test-plan► matrix rows built from
                                        scenarios + acceptance criteria
        downhill: each step REFINES what the last one named;
        nothing is re-brainstormed from blank at a costlier step
```

## What a scenario is (and is not)

A scenario is a situation with an actor: "a new contributor's session dies
mid-build; they reopen tomorrow". It is NOT a test case ("assert resume skips
completed tasks", that comes later, derived from it) and NOT a category ("the
system fails", no actor, too vague to invert).

## What you do

- **React to the sketch, don't author it.** The kit generates; your value is
  vetoing rows that can't happen in your world and naming the one situation
  only you know about (the weird client, the legacy cron, the person who
  always pastes rich text).
- **Take the must-NOT-happen rows seriously.** They are the cheapest insurance
  in the whole flow: one line at grill time ("money moves without approval")
  becomes a gate later; unnamed, it becomes an incident.
- **Expect adversarial and recovery rows.** The generator deliberately covers
  the two categories humans skip (what games the check; what happens after an
  interruption). Their absence should carry a stated reason, not silence.
- **Defining a new loop?** It is not "designed" until its five survival rows
  exist (convergence, non-convergence, bad input, interruption, gamed
  metric). The kit will hold you to that.

## Common questions

- **"This feels like extra ceremony at idea time."** It is 3-5 rows sketched
  while you are already answering "what breaks at scale". The expensive
  version is discovering the same rows in production.
- **"Where do the rows end up?"** In the brief, then the spec's Edge Cases,
  then the test matrix, then (for contributor surfaces) gauntlet cards. Same
  rows, progressively sharpened; you can trace any test back to the situation
  that justified it.
- **"Can I skip a category?"** Yes, with a reason. "No concurrent access by
  construction, single-writer daemon" is a fine skip; silence is not.
