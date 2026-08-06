# The V-model (user guide)

Why does the kit keep testing at every level, and why can "every task is green"
still end in a failed acceptance run? Because building and proving happen at
FOUR different altitudes, and each build altitude has a mirrored test that only
makes sense at that altitude:

```
 LEFT · what gets built              RIGHT · what proves it
 requirement ("users can X") ◄─────► acceptance test (does the PROGRAM
   │                                  satisfy the original ask?)
   solution design           ◄─────► system test (whole suite, end to end)
     │
     spec (tasks + criteria) ◄─────► integration test (do the tasks
       │                              wire together?)
       code (one task)       ◄─────► unit / task test (is THIS task right?)
```

The kit walks the left arm down as you shape work (think, design, spec, execute)
and the right arm up as it verifies (task-verifier per task, then integration,
then system, then acceptance). `/kit:verify` re-runs the whole right arm on
demand without rebuilding anything.

## The one insight to keep

**Each right-arm level catches what the level below cannot see.** All tasks
green + integration red means the pieces are individually right and wired
wrong. Everything green below + acceptance red means you built the spec
faithfully and the spec missed the requirement. Neither is a contradiction;
both are the model working. The expensive failure is skipping a level and
finding its class of bug in production instead.

## What you do

- **Give every level something to check.** Acceptance needs a stated
  requirement ("done means a user can X"), integration needs the spec's wiring
  claims, tasks need acceptance criteria with runnable commands. A level you
  gave nothing to check is a level that silently passes.
- **Read failures at their altitude.** A task-level failure gets a task-level
  fix; an acceptance failure means revisit the SPEC or requirement, not
  hot-patch a task until the symptom moves.
- **Do not skip up the arm.** Asking for "just run the acceptance check" while
  unit tests are red buys you a slow, ambiguous failure instead of a fast,
  precise one.

## Common questions

- **"This feels heavy for a small change."** Lanes scale it: a tiny change runs
  a short arm. The full V is for full-lane work; the model is the map, not a
  toll.
- **"Where does the gauntlet fit?"** It is an acceptance test whose requirement
  is "an outside dev can work here", the top-right corner, applied to the
  contributor surface (guide: `gauntlet.md`).
