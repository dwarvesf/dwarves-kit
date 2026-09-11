# Proof of done: remove a locked worktree instead of declining

`wrap apply --worktrees` ran a bare `git worktree remove`, which leaves a LOCKED worktree in place
and only prints a hint. The Agent tool locks every worktree it creates, so the tidy silently failed
on exactly the worktrees it exists to clean.

## Green run

| | |
|---|---|
| Command | `bash tests/test-wrap.sh` |
| Exit | 0 |
| Result | `test-wrap: all 319 passed` |
| Verdict | PASS |

The regression proof is in the fixture, not a new assertion: `make_clone` now locks the clean
worktree it builds, so the existing "apply --apply removed the clean worktree only" assertion
covers the locked case. Test count went 317 to 319 with no assertion rewritten.

## Negative control

Revert the fix, confirm RED, restore, confirm the restore by an EMPTY diff rather than an exit code.

| Step | Command | Result |
|---|---|---|
| Baseline | `git status --porcelain` | empty, committed tree clean |
| Mutate | `worktree remove -f -f "$wt"` back to `worktree remove "$wt"` | 1 insertion, 1 deletion |
| Red run | `bash tests/test-wrap.sh` | `test-wrap: 317 passed, 2 FAILED of 319` |
| Restore | `git checkout -- lib/wrap/wrap.sh` | |
| Postcondition | `git diff --stat` | **empty**, restored |
| Green again | `bash tests/test-wrap.sh` | `test-wrap: all 319 passed` |

Verdict: PASS. Two assertions fail without the fix and both pass with it, so the test is not
vacuous. The failures are the clean-worktree removal check and the `apply --apply exits 0` check,
which is the `run()` helper reporting the refused removal.

## Reproducible

`bash tests/test-wrap.sh` from the branch root. The negative control is the five steps above in
order; the mutation is one word in `lib/wrap/wrap.sh`.

## Scope left alone

The three best-effort `worktree remove --force ... || true` prunes in `lib/board/board-writeback.sh`
and `lib/queue/orchestrate.sh` drop scratch worktrees the kit creates itself without a lock, and
they already tolerate failure. Changing them would widen the diff without fixing a live failure.

## How it was found

By hand, cleaning up after subagent worktrees about fifteen times in one session. The no-op once
preserved an agent's later commits and once stranded a branch behind a
`cannot delete branch ... used by worktree` error that read as an unrelated second problem.
