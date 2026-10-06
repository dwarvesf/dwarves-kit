---
name: kit-board
description: >
  Read the state of the boards and explain the daily brief, using the dwarves-kit `board`
  command. Triggers: "how are the boards", "how many boards are over threshold", "what is
  waiting in triage", "what needs my decision", "explain the brief", "is board sync healthy",
  "what did the bots do". Read-only: it runs a dry run and never posts, never moves a card,
  never edits a board.
version: 0.1.0
metadata:
  hermes:
    tags: [kit, board, backlog, health, brief]
    related_skills: [kit-precedent]
---

# kit-board

The kit owns the logic. This skill only says which command answers which question. Run it in the terminal, read the output, answer in plain words. Do not recompute anything the command already printed.

```
 question                           command (all read-only)
 ---------------------------------  ------------------------------------------------------
 how are the boards / over limit    ~/.claude/dwarves-kit/bin/board health run --dry-run --force
 what needs my decision, the brief  ~/.claude/dwarves-kit/bin/board brief run --dry-run --force --show-boards
 backlog rows across repos          ~/.claude/dwarves-kit/bin/board status
 what is the sweep doing            ~/.claude/dwarves-kit/bin/board sweep verify --last-tick
```

## When to use

- A question about board counts, stale or waiting cards, sync health, or what the daily brief says.
- A request to explain one line of a brief you were shown.

## How to answer

1. Run the command from the table. The operator's flags come from the kit config file (`$DWARVES_BOARD_CONFIG`, else `~/.config/dwarves-kit/board.json`), so no flags beyond the ones shown are needed.
2. Each output line is one JSON payload per cluster. The lines you read are in `.fields[].value`; `brief` payloads also carry `.details`.
3. A board over its threshold is a field that reads `<board>: N waiting in triage, oldest Nd`, and a line `+N more boards over threshold` when there are more than three. Count those. No such field means no board is over threshold.
4. A `needs your decision` block lists questions for the operator. Repeat them as asked. Never answer one yourself.
5. Say what you ran in one short line, then the answer.

## Never

- Never run `board brief run` or `board health run` without `--dry-run`: a real run posts to a channel and stamps state.
- Never edit `_meta/BACKLOG.md`, a kanban card, or the config file from here.
- Never print a token or a webhook if one shows in an error. Say the command failed and quote the first line with the secret removed.
