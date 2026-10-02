# Proof of done: board pane mod for Claude Code

## What changed

`integrations/claude-code/board-pane/` is an opt-in Claude Code mod (a function-hook plugin). `/board` opens a side pane with `bin/board board` for the session's repo. `/board all` shows `bin/board all next` across the consumer's registry. It is a display-only wrapper over the CLI, the same role as the Raycast and Warp integrations, and nothing installs it.

The pane parses the CLI output into rows. An item row is a button: digits 1 to 9 press it, and a press puts `Work on <ID>` (or `Work on <ID> in <repo>`) in the prompt box without submitting it, so a stray key never starts a turn. Refresh and Close sit at the top, and item labels are cut to the pane width. A stale repo shows dimmed with a trailing `?` in place of the `[STALE: ...]` tag. Repos with no queued item fold into one `+N idle` row. `r` refreshes, and a 60 second timer refreshes while the pane stays open.

A one-line summary band above the prompt counts queued and executing tasks, handoff files, worktrees and open PRs for the session's repo. It refreshes on session start and after each main-loop turn, caches the PR count for five minutes, and drops any segment whose source fails.

## Gate table

| Claim | Evidence |
|---|---|
| `/board` and `/board all` run the argv that `bin/board --help` documents | tests 1 and 2, run table below |
| a failing CLI shows its stderr, dimmed | test 3 |
| a press fills the prompt and never submits, in both modes | tests 5 and 6, second negative control |
| Close shuts the pane | test 12 |
| stale rows, the refresh time, the dropped trailer and the idle fold render | test 7 |
| the timer stops once the pane closes | test 9 |
| the band shows task, handoff, worktree and PR counts from their sources | band tests 1 |
| a failing source drops only its own segment, and an all-failing band draws nothing | band tests 2 to 4 |
| a survey takes the row and the band steps aside | band test 5 |
| the PR lookup runs once per five minutes | band test 6, third negative control |
| a subagent turn does not refresh the band | band test 7 |
| pressing `tasks` opens the pane in repo mode | band test 8 |
| the stale marker is load-bearing | negative control below |
| the manifest and module load as the engine reads them | validate run below |

## Run table

```
Command: claude plugin test integrations/claude-code/board-pane
Exit: 0
20 pass, 0 fail
Verdict: PASS
```

```
Command: claude plugin validate integrations/claude-code/board-pane
Exit: 0
Validation passed with warnings (author field only)
Verdict: PASS
```

## Negative control

Removed the `' ?'` stale marker from the all-mode row builder in `hooks/parse.ts`.

```
Command: claude plugin test integrations/claude-code/board-pane
(fail) all mode shows the refresh time, dims stale rows with ?, drops the trailer, folds idle repos
(fail) all rows parse items, stale tags and idle repos
10 pass, 2 fail
Verdict: RED as expected
```

Restored with `git checkout -- integrations/claude-code/board-pane/hooks/parse.ts`: 12 pass, 0 fail.

## Reproduce

```
claude plugin test integrations/claude-code/board-pane
```

`tests/test-meta.sh` carries one failure, `docs/FEATURES.md is fresh`, that main also shows at the base of this branch. This change does not touch it.

## Negative control: fill, never submit

Switched the item press from `$.prompt.fill` back to `$.prompt.submit` in `hooks/register.tsx`.

```
Command: claude plugin test integrations/claude-code/board-pane
(fail) pressing an item fills the prompt with Work on <ID> in repo mode, never submits
(fail) pressing an item fills the prompt with Work on <ID> in <repo> in all mode
10 pass, 2 fail
Verdict: RED as expected
```

Restored: 12 pass, 0 fail.

## Negative control: PR cache

Forced the PR staleness check in `hooks/register.tsx` to always true, so every refresh calls `gh`.

```
Command: claude plugin test integrations/claude-code/board-pane
(fail) the PR lookup is cached for five minutes across turns
  Expected: 1
  Received: 3
19 pass, 1 fail
Verdict: RED as expected
```

Restored: 20 pass, 0 fail.
