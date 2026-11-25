# Reminders adapter

Two-way sync between the board and an Apple Reminders list, over `osascript` (JXA), two bulk calls per sync. The adapter name and the app name are both `reminders`. The contract it follows is `lib/adapters/README.md`.

## What it holds

| Field | Reminders |
|---|---|
| title `ID-NNN · item` | two-way |
| status | open or completed only (completed is shipped; any inactive board state completes the reminder; reopening a row un-completes it) |
| notes | body (the board wins, lazy) |
| #tags | in the body text; Reminders exposes no tag API (the sdef has no tag surface), so tags ride at the end of the title text and the adapter strips and rebuilds them |

Tags a board item carries in its own cell are dropped from the title text first, so the suffix never doubles and never reads as drift. A title whose tag suffix drifted from its body is rewritten on the next sync.

## Config

```toml
[sync]
apps           = "reminders"
reminders_list = "Backlog"      # the list name; created on first run
```

Flag: `--list` (also `[sync] reminders_list`). Filter keys: `reminders_only_tags`, `reminders_skip_tags`, `reminders_intake`. State: `<sync state dir>/<board-slug>/reminders.state.json`.

New items in the list that carry no `ID-` prefix become queued rows in the `### Reminders inbox` section of the board and are retitled with their assigned ID.

## Install notes

- macOS only. The first run needs `osascript` allowed to control Reminders (System Settings, Privacy and Security, Automation); a denied run ends with that hint.
- The list is created on first run.
- A one-time copy: when `reminders.state.json` does not exist yet and `~/.cache/backlog-reminders-sync/state.json` does, the adapter copies it and prints `migrated legacy reminders state -> <path>`. It runs only when `reminders` is a named app, and never overwrites an existing state file.

## One invocation

```bash
board sync --dry-run --apps reminders
```

## Tests

`lib/adapters/tests/test_reminders.py` runs against a fake `osascript` runner; `test_conformance.py` checks the adapter against the contract. Neither reaches Reminders.
