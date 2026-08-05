# Mega-goals (user guide)

You have ONE destination that takes several DEPENDENT pieces of work to reach: a
migration with phases, a rewrite that needs five steps, a program like "outside
devs can maintain this estate". That is a mega-goal. The kit turns it into a
roadmap on disk and then works the pieces one at a time, each through the normal
loop, each ending in its own PR.

```
 your destination ("X is true when we are done")
        │  /kit:mega decomposes, asks EVERY clarifying
        │  question once, up front, never mid-run
        ▼
 roadmap on disk: sub-goal 01 -> 02 -> 03 ... (3-8, dependent, ordered)
        │
        ▼  one at a time
 sub-goal N runs the bounded goal loop -> its own PR -> ship gate
        │
        ▼
 mega-goal closes on its EXIT CRITERION, a check at the destination
 altitude (e.g. an acceptance run), not on "all sub-goals merged"
```

## What you do

1. **State the destination, not the steps.** "I want X to be true" beats a task
   list; decomposition is the command's job, and it will show you the split for
   approval before anything runs.
2. **Answer the clarification batch once.** Every sub-goal's open question is
   front-loaded into one interview. Mid-run you will not be asked; a decision the
   run had to take alone lands on a ledger you review later.
3. **Let the triage ladder demote you.** If your "mega" is really one bounded
   change, or a flat list of unrelated tasks, the command routes you to a plain
   goal or separate goals instead. Do not fight the demotion: ceremony you did
   not need is time lost. Independent-parallel work routes to `/kit:dispatch`.
4. **Watch PRs, not progress bars.** Each sub-goal ends in a PR through the
   normal ship gate. Merging stays gated the same as any other work.
5. **Hold the exit criterion.** The mega-goal is done when its destination-level
   check passes, never merely when the last PR merges. Name that check at
   planning time; if you cannot name one, the destination is not yet concrete
   enough to run.

## Common questions

- **"Can it fan out and run things in parallel?"** Dependent-sequenced is this
  lane; independent-parallel is `/kit:dispatch`. A real dependency GRAPH (waves,
  fan-in) is neither, and the kit will say so rather than grow a scheduler.
- **"Something new came up mid-program."** New scope is a new sub-goal appended
  to the roadmap (or a new mega), never a silent widening of the current one.
- **"Where is the state?"** On disk in the roadmap files and the specs/PRs it
  produced; nothing lives only in a session. A new session picks up from the
  roadmap.
