# Dispatch vs mega-goal (user guide)

Two commands handle "this is more than one piece of work", and they are not
interchangeable. The routing question is one word: are the pieces DEPENDENT?

```
 several pieces of work
        │
        ├─ independent of each other, no shared files, any order?
        │       └──> /kit:dispatch  (parallel workers, disjointness
        │            gate proves they can't collide before launch)
        │
        ├─ dependent, one ordered chain toward one destination?
        │       └──> /kit:mega      (roadmap of sub-goals, one at a
        │            time, one PR each; guide: mega-goal.md)
        │
        └─ a real dependency GRAPH: fan-out, fan-in, waves?
                └──> neither. The kit says so and stops; that shape
                     belongs to a dedicated scheduler, not this kit
```

Why the split is strict:

- **Parallel + dependent = collisions.** Two workers touching coupled files
  produce merge wreckage that costs more than the parallelism saved. The
  disjointness gate exists because this failure is quiet until merge time.
- **Sequential + independent = waste.** Queueing unrelated tasks behind each
  other buys no safety; dispatch them.
- **Graph = scope honesty.** Pretending a DAG is a chain (or a fan-out) makes
  the kit a bad scheduler instead of a good executor. Naming the limit beats
  faking the capability.

## What you do

- **Describe the pieces and their coupling; let the router decide.** "These
  five doc fixes are unrelated" routes to dispatch; "these five steps each
  need the last one's output" routes to mega.
- **For dispatch: trust the gate.** If it refuses parallel launch because two
  tasks share files, that refusal just saved you the merge conflict. Re-slice
  the tasks or accept sequencing.
- **For mega: read the mega-goal guide.** Destination first, clarifications
  once, exit criterion held.
- **Batch the tiny stuff.** Several trivial items do not deserve either
  command; they batch into one ordinary change.

## Common questions

- **"Can dispatch workers talk to each other?"** No, and that is the point:
  anything requiring coordination mid-flight was dependent work misrouted.
- **"My mega's sub-goals could partly run in parallel."** Split them: the
  truly independent parts dispatch; the dependent chain stays mega. Mixed
  shapes are two invocations, not one clever one.
