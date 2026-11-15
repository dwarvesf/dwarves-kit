# Retro: serial-path join for tiered verification
Date: 2026-11-16
Sprint: 2026-11-16

Answers drafted by the lead from the session record. Edit any line that misreads it.

## Metrics
- Tasks planned: 1 (rule 4, serial path joins per DAG level), completed: 1, deferred: a join that holds the level's merges back.
- Code: about 95 lines in `lib/queue/orchestrate.sh`, one new suite of 13 checks, 3 negative-control mutations all red.
- The new suite is red on the previous `orchestrate.sh` (10 of 13).

## What worked
- Reusing `_join_run`, the cleanup and the interrupt handler kept the new code to two functions and one call site.
- Running the new suite against the previous file before the negative control showed the tests were not vacuous before any mutation was written.

## What hurt
- The spec's "join per DAG level" assumed a merge step the serial loop does not have. The honest version is weaker than the wave join (post-merge, base tree, no pre-level baseline), and that is the call to confirm.

## Action items
- [ ] Decide whether the serial join must hold a level's merges back (workers open the PR, the conductor merges after the join); it changes the worker prompt and box grounding -- owner: @tieubao -- deadline: 2026-11-30
- [ ] Run a tiered pilot on a real serial mega-goal and read the level join timings -- owner: @tieubao -- deadline: 2026-11-30

## Kit feedback
- `wrap start` and `negctl.sh` worked as documented; `negctl.sh` needs the code committed first, which the notes could say.
