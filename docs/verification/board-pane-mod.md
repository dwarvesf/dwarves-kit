# Proof of done: board pane mod for Claude Code

## What changed

`integrations/claude-code/board-pane/` is an opt-in Claude Code mod (a function-hook plugin). `/board` opens a side pane with `bin/board board` for the session's repo. `/board all` shows `bin/board all next` across the consumer's registry. It is a display-only wrapper over the CLI, the same role as the Raycast and Warp integrations, and nothing installs it.

The pane parses the CLI output into rows. An item row is a button: digits 1 to 9 press it, and a press submits `Work on <ID>` (or `Work on <ID> in <repo>`) as a prompt. A stale repo shows dimmed with a trailing `?` in place of the `[STALE: ...]` tag. Repos with no queued item fold into one `+N idle` row. `r` refreshes, and a 60 second timer refreshes while the pane stays open.

## Gate table

| Claim | Evidence |
|---|---|
| `/board` and `/board all` run the argv that `bin/board --help` documents | tests 1 and 2, run table below |
| a failing CLI shows its stderr, dimmed | test 3 |
| a press submits the right prompt in both modes | tests 5 and 6 |
| stale rows, the refresh time, the dropped trailer and the idle fold render | test 7 |
| the timer stops once the pane closes | test 9 |
| the stale marker is load-bearing | negative control below |
| the manifest and module load as the engine reads them | validate run below |

## Run table

```
Command: claude plugin test integrations/claude-code/board-pane
Exit: 0
11 pass, 0 fail
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
9 pass, 2 fail
Verdict: RED as expected
```

Restored with `git checkout -- integrations/claude-code/board-pane/hooks/parse.ts`: 11 pass, 0 fail.

## Reproduce

```
claude plugin test integrations/claude-code/board-pane
```

`tests/test-meta.sh` carries one failure, `docs/FEATURES.md is fresh`, that main also shows at the base of this branch. This change does not touch it.
