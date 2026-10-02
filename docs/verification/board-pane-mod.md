# Proof of done: board pane mod for Claude Code

## What changed

`integrations/claude-code/board-pane/` is an opt-in Claude Code mod (a function-hook plugin). `/board` opens a side pane over every repo in the consumer's board registry (`$BOARD_REGISTRY`, else `<cwd>/_meta/boards.txt`), fed by one `bin/board all board` call. It is a display-only wrapper over the CLI, the same role as the Raycast and Warp integrations, and nothing installs it.

The overview groups repos by rail, marks and leads with the current repo, shows active and queued counts and `↓N` for a stale checkout, and folds idle repos into one row. Pressing a repo opens its view: in-flight work first with glyphs, then the first eight queued items and `+ N more`. A press on an item puts `Work on <ID> in <repo>` in the prompt box without submitting, so a stray key never starts a turn. Digits 1 to 9, `b`, `r` and `q` are hotkeys, a filter box narrows repos or items, and a 60 second timer refreshes while the pane stays open. Without a readable registry the pane falls back to the current repo alone. `/board here` and `/board <name>` open a repo view directly.

A one-line summary band above the prompt counts queued and executing tasks, handoff files, worktrees and open PRs for the session's repo. It refreshes on session start and after each main-loop turn, caches the PR count for five minutes, and drops any segment whose source fails. Pressing `tasks` opens the current repo's view.

## Gate table

| Claim | Evidence |
|---|---|
| `/board` runs `all board` with `--registry` and `--repo-root`, and `BOARD_REGISTRY` wins with `~` expanded | pane tests 1 and 2 |
| the overview groups by rail, leads with the current repo, totals the header, shows `↓N` | pane test 3, parse tests |
| idle repos fold into one row | pane test 4, second negative control |
| a narrow pane drops the trailing column and the state word | pane tests 5 and 8 |
| a repo press opens the view and `back` returns | pane test 6 |
| in-flight work lists in order with glyphs and tones | pane test 7, first negative control |
| shipped items stay hidden, `+ N more` reveals the rest | pane tests 9 and 10 |
| the filter narrows repos and items | pane test 11 |
| a press fills the prompt and never submits, with the repo named when it is not the current one | pane test 12 |
| `/board <name>` and an unknown name resolve as described | pane test 13 |
| Refresh, Close and the 60 second timer behave, and the timer stops once the pane closes | pane tests 14 to 16 |
| no registry, or a failing `all board`, falls back to the session repo; a failing fallback shows stderr dimmed | pane tests 17 to 19 |
| the band shows task, handoff, worktree and PR counts from their sources | band tests 1 |
| a failing source drops only its own segment, and an all-failing band draws nothing | band tests 2 to 4 |
| a survey takes the row and the band steps aside | band test 5 |
| the PR lookup runs once per five minutes | band test 6, third negative control |
| a subagent turn does not refresh the band | band test 7 |
| pressing `tasks` opens the pane | band test 8 |
| the manifest and module load as the engine reads them | validate run below |

## Run table

```
Command: claude plugin test integrations/claude-code/board-pane
Exit: 0
31 pass, 0 fail
Verdict: PASS
```

```
Command: claude plugin validate integrations/claude-code/board-pane
Exit: 0
Validation passed with warnings (author field only)
Verdict: PASS
```

## Negative controls

Reversed the in-flight order in `hooks/parse.ts` (`IN_FLIGHT` as claimed, speccing, validated, executing).

```
Command: claude plugin test integrations/claude-code/board-pane
27 pass, 4 fail
(fail) the overview groups repos by rail, leads with the current repo and totals the header
(fail) the repo view shows the stale part, lists in-flight work first with glyphs and tones
(fail) a narrow repo view drops the state word
(fail) pressing an item fills the prompt, never submits
Verdict: RED as expected
```

Made `isIdle` always false, so no repo folds into the idle row.

```
Command: claude plugin test integrations/claude-code/board-pane
28 pass, 3 fail
(fail) the overview groups repos by rail, leads with the current repo and totals the header
(fail) idle repos fold into one dim row at the end
(fail) the overview builder groups, orders and folds idle repos
Verdict: RED as expected
```

Restored both: 31 pass, 0 fail.

## Reproduce

```
claude plugin test integrations/claude-code/board-pane
```

`tests/test-meta.sh` carries one failure, `docs/FEATURES.md is fresh`, that main also shows at the base of this branch. This change does not touch it.

## Negative control: PR cache

Forced the PR staleness check in `hooks/register.tsx` to always true, so every refresh calls `gh`.

```
Command: claude plugin test integrations/claude-code/board-pane
(fail) the PR lookup is cached for five minutes across turns
  Expected: 1
  Received: 3
30 pass, 1 fail
Verdict: RED as expected
```

Restored: 31 pass, 0 fail.
