# Proof of done: execute-flips-row

`/kit:execute` now flips a spec's board row to `executing` as the build starts, when the spec carries a `Board: <ID>` header. Before this, no command made the `validated` to `executing` flip; the board-row figure marked it as a manual step. The figure is re-rendered without that edge. The branch also corrects the plugin install id in living docs (`kit@dwarves-marketplace`) and frames the gauntlet in the README as a general artifact check.

## Green run

The verb the new instruction calls, run on a scratch copy of the kit board (never the real one):

```
Command: BACKLOG_FILE=<scratch copy of _meta/BACKLOG.md> bash lib/board/backlog.sh set ID-880 validated && BACKLOG_FILE=<same copy> bash lib/board/backlog.sh set ID-880 executing
Exit: 0
Output:
ID-880 -> validated
ID-880 -> executing
Verdict: PASS
```

```
Command: rg -q 'backlog.sh set <ID> executing' commands/execute.md && bash lib/system-design/doc-figures check && bash tests/test-doc-figures.sh
Exit: 0
Output:
doc-figures: ok (12 figures)
doc-figures: 25 passed, 0 failed (25 checks)
Verdict: PASS
```

## Negative control

Mutation: `git show origin/master:commands/execute.md > commands/execute.md` (the command text before this change), run by `lib/gate/negctl.sh` after the fix was committed.

- With the old text, `rg -q 'backlog.sh set <ID> executing' commands/execute.md` finds nothing and exits 1: no instruction flips the row.
- Restore: `git checkout HEAD -- commands/execute.md`, then green again. Exit: 0 (green after restore).

## Rollback

Revert the squash commit. `/kit:execute` stops flipping the row, the figure regains the manual edge on the next render, and the docs return to the wrong install id.

Verdict: PASS
