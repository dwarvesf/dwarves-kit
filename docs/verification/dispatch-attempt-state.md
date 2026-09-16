# Verification -- dispatch-attempt-state

`lib/goal/attempt-state.sh` separates the attempt state from the task state, so a disconnected
worker holds an unknown outcome inside a grace window instead of being written off as FAILED and
re-dispatched.

## Green run

```
Command: bash tests/test-attempt-state.sh
Exit: 0
Verdict: PASS
```

All 15 cases pass:

| Case | What it pins |
|---|---|
| 1 | the legal walk: dispatch, disconnect, resume, commit, with the TASK staying `dispatched` across the window |
| 2 | `abandon` takes the task to `lost` |
| 3 | illegal: `committed -> running` refused |
| 4 | illegal: `lost -> running` refused |
| 5 | illegal: a second `dispatch` while an attempt is live refused |
| 6 | grace not expired: `lose-attempt` refused, and the refusal names the seconds left |
| 7 | grace expired: attempt `lost`, task freed to `queued`, worker excluded |
| 8 | the exclusion is enforced, not only recorded: re-dispatch to that worker refused |
| 9 | a different worker picks the freed task back up |
| 10 | a second `commit-result` for the same task exits 0 as a no-op that names the winner |
| 11 | resume inside the window then a late replacement: exactly one committed result, the real one |
| 12 | a recorded sibling committing late is `superseded`, the first commit stands |
| 13-14 | `status` reports the grace remaining, and reports it expired |
| 15 | `--grace` sets the window rather than a hardcoded constant |

```
Command: bash tests/run-all.sh
Exit: 0
Verdict: PASS (149 suites)
```

## Negative control

```
Command: bash lib/gate/negctl.sh <worktree> "bash <worktree>/tests/test-attempt-state.sh" "bash <mutate-script>"
Exit: 0
Verdict: PASS
```

negctl output:

```
Exit: 0 (green before mutation)
Mutation: neuter the grace-window guard in lose-attempt
Changed: lib/goal/attempt-state.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/goal/attempt-state.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation replaced the window comparison `[ "$now" -le "$until" ]` with a condition that never
holds, so `lose-attempt` would accept a disconnected attempt while its window still had time left.
That is the duplicate-dispatch bug itself. The suite went red and returned green after restore.

## Not proven

- No live `/kit:dispatch` run drove the module. The consumer wiring in `commands/dispatch.md` and
  `commands/execute.md` is prose a lead follows; only the module's own contract is executed here.
- Concurrent writers are not tested. One lead owns the store, the same single-writer assumption
  `goal-registry.sh` makes, and nothing enforces it.
- No caller prunes `kit-attempts/`. `release <task>` exists and is unused.
