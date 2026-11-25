# Hermes adapter

Two-way sync between the board and a Hermes kanban, over `hermes kanban` verbs only. The adapter name and the app name are both `hermes`. The contract it follows is `lib/adapters/README.md`.

## What it holds

| Field | Hermes |
|---|---|
| title `ID-NNN · item` | frozen at create (the CLI has no edit verb) |
| status | create = `todo`; `complete` maps to shipped, `archive` maps to dropped or parked; moves between active states are reported as skipped, not attempted |
| notes | `--body` at create, frozen |
| #tags | in the body text |

Hermes has no title or body edit verb and no reopen verb, so those cells say "frozen" and "n/a" by capability, not by choice. The reverse direction reads a task `done` as board shipped and `archived` as board dropped.

The store IS the board. A fresh `HERMES_HOME` initializes on first create. Writes go through `hermes kanban` verbs only, so compare-and-set, events and Discord notify stay intact; the sqlite file is never written directly. Seeds carry `--idempotency-key bls-ID-NNN`, so a repeated create is a no-op.

Instance selection is three separate axes: `hermes_target` says which machine and uid (an ssh host, `local`, or `sudo:<user>` for an instance owned by another uid on this host), `hermes_home` says which instance, and `hermes_board` says which board inside it. `hermes_assignee` and `hermes_workspace` shape what a create looks like: an unassigned task on a scratch workspace is inert for a consumer whose workers pick up by profile and whose deliverables must outlive completion. `{id}` in the workspace is the board id, so every relayed task gets its own directory.

## Config

```toml
[sync]
apps              = "hermes"
hermes_target     = "<ssh-host>"      # an ssh host, or "local", or "sudo:<user>"; no default
hermes_home       = "<HERMES_HOME>"   # the kanban store to sync against; no default
# optional, for an instance whose board, workers, and deliverables are shared:
# hermes_board     = "dw-ops"
# hermes_assignee  = "chief-of-staff"
# hermes_workspace = "dir:<HERMES_HOME>/outbox/backlog/{id}"
```

Flags: `--hermes-target`, `--hermes-home`, `--hermes-board`, `--hermes-assignee`, `--hermes-workspace` (also the `[sync]` keys above). Filter keys: `hermes_only_tags`, `hermes_skip_tags`, `hermes_intake`. State: `<sync state dir>/<board-slug>/hermes.state.json`.

Neither `hermes_target` nor `hermes_home` has a default: both name one operator's machine, so a guess would point the sync at someone else's instance. An unset one ends the run with a message that names the key.

## Task Board intake relay

When a task is created from a row that another adapter's intake wrote (the Notion intake), the adapter hands the row body to the `body_expander` hook, which any adapter may provide; the Notion adapter does. The hook fetches the page body once, at create, and the card carries it frozen like the rest of the body. With no adapter declaring the hook the card is created with the body as it is. An adapter that declares the hook and fails to import stops the run before any card is created, because a silent skip would create cards without bodies that are never recreated.

The relay order is intake, publish, relay, each its own invocation:

```
board sync --apps notion-taskboard-pull      # 1. intake
<commit + push the board>                    # 2. publish
board sync --apps hermes                     # 3. relay
```

Intake mints a board id and the create keys its idempotency on it, so the id must be published before the relay. Otherwise a rejected push discards the row while the kanban task survives, and the next tick mints a new id and creates a duplicate task.

## Install notes

- `hermes` must be on the target's `PATH` (over ssh, `local`, or `sudo -n -u <user> -H`). The `sudo:` form needs a NOPASSWD rule; `-n` keeps an unattended run from waiting on a password prompt.
- A `hermes_target` and `hermes_home` that your repo sets in a project `.kit.toml` are read as they are: treat a pull request that edits them like a change to a command line.

## One invocation

```bash
board sync --dry-run --apps hermes
```

## Tests

`lib/adapters/tests/test_hermes.py` runs against a fake ssh transport; `test_body_expander.py` checks the relay through the registry (the block transport is a fake, and the broken-provider cases run in a child interpreter that refuses every transport); `test_conformance.py` checks the adapter against the contract. None of them reaches a Hermes host.
