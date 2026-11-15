# Retro: serial-path join for tiered verification
Date: 2026-11-16
Sprint: 2026-11-16

Answers drafted by the lead from the session record. Edit any line that misreads it.

## Metrics
- Tasks planned: 1 (rule 4, serial path joins per DAG level), completed: 1, deferred: a join that holds the level's merges back.
- Code: about 150 lines in `lib/queue/orchestrate.sh`, one new suite of 19 checks, 6 negative-control mutations all red.
- The new suite is red on master's `orchestrate.sh` (14 of 19).
- A two-lens review (security, architecture and tests) found 2 highs and 3 mediums in the first version; all were fixed before landing.

## What worked
- Reusing `_join_run`, the cleanup and the interrupt handler kept the new code to two functions and one call site.
- Running the new suite against the previous file before the negative control showed the tests were not vacuous before any mutation was written.

## What hurt
- The first version joined right after a sub-goal completed. The review showed that a red halt then held for one process only, that config was read after the first worker had merged, and that the level walk was exponential on a fan-out cycle. Joining at the top of each cycle with markers and a pinned base fixed all three; a design that shipped them first would have saved a pass.
- The spec's "join per DAG level" assumed a merge step the serial loop does not have. The honest version is weaker than the wave join (post-merge, base tree, no pre-level baseline), and that is the call to confirm.

## Action items
- [ ] Decide whether the serial join must hold a level's merges back (workers open the PR, the conductor merges after the join); it changes the worker prompt and box grounding -- owner: @tieubao -- deadline: 2026-11-30
- [ ] Run a tiered pilot on a real serial mega-goal and read the level join timings -- owner: @tieubao -- deadline: 2026-11-30

## Kit feedback
- `wrap start` and `negctl.sh` worked as documented; `negctl.sh` needs the code committed first, which the notes could say.
