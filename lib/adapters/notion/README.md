# Notion adapter

Three apps behind one adapter directory: `notion` (two-way sync with a Notion database), `notion-taskboard` (a one-way, insert-only push to a foreign team board) and `notion-taskboard-pull` (a read-only intake from the same team board). All three drive the `ntn` CLI (keychain auth). The contract the adapter follows is `lib/adapters/README.md`.

| App | Mode | Source module |
|---|---|---|
| `notion` | two-way | `notion.py` |
| `notion-taskboard` | create-only | `notion_taskboard.py` |
| `notion-taskboard-pull` | pull-only | `notion_taskboard_pull.py` |

`ntn.py` is the one `ntn` runner the three share (retries a transient failure, never a write that may have landed). `adapter.py` builds the three sources with their missing-flag messages, refuses a run that aims a write-capable app at the intake database (the `guard` hook), and exports the page-body expander (the `body_expander` hook) that another adapter's card creation can use.

## Notion, two-way (`notion`)

| Field | Notion |
|---|---|
| title `ID-NNN · item` | bisync |
| status | full: the `Status` select bisyncs every board state |
| notes | `Notes` rich_text (board wins, lazy) |
| #tags | `Tags` multi_select only; stripped out of the Notes text |

Bootstrap: with no board, `--notion-parent <page_id>` creates a database (Name / Status select with every board state / Tags / Notes) and persists the binding in the snapshot. With a board, `--notion-db <id>` discovers the title prop and a `Status` select or status prop, adds missing Notes, Tags and Status to the schema, and adopts foreign pages through the inbox flow. Status-type props (the API cannot add options) map by group: Complete maps to shipped.

With no binding in the state file and neither `notion_db` nor `notion_parent` set, the app prints `notion: skipped (no binding; ...)` and the run goes on.

```toml
[sync]
apps          = "notion"
notion_db     = "<database_id>"   # or notion_parent = "<page_id>" to bootstrap
notion_title  = "Backlog"         # title of a board created at bootstrap
```

Flags: `--notion-db`, `--notion-parent`, `--notion-title`. Filter keys: `notion_only_tags`, `notion_skip_tags`, `notion_intake`. State: `<sync state dir>/<board-slug>/notion.state.json`.

## One-way push to a foreign team board (`notion-taskboard`)

A one-way, **insert-only** push of a repo's board rows to a foreign, team-OWNED Notion board. The board is the source of truth; the sink is never read for merge and the board file is never written. Fields are set only on page-create, so a team member's later edits on the card are never overwritten. The local sync-state map is the identity index (a board id already pushed is never re-pushed), because the team board's own ID column is a read-only auto-increment that cannot hold `DF-NN`.

Status, Priority and Weight map to the team board's OWN option names via config, so the sink never mutates the team schema: it reads the schema (never PATCHes it) and validates every mapped option name exists BEFORE any create, so a typo in a map value is a hard error instead of a silently auto-created select option. `dropped` rows are skipped; a state absent from the map uses `status_default` or, if unset, is a guided error. Validation runs at preflight, so `--dry-run` surfaces config errors with zero writes, and state is checkpointed after each create so a mid-batch failure never re-pushes a page.

A row whose notes already carry `notion-page:<32-hex>` (the identity marker `notion-taskboard-pull` writes on intake) is never pushed as a create, whatever its tags: the planner binds it into the state map instead (`{"rid": pid, "via": "pull-marker"}`), with no network call. The source declares the marker through its `bound_marker_re` attribute. This stops a team-approved intake row from minting a second, title-prefixed copy of the page it came from the moment triage strips its `#inbox` quarantine tag. `describe()` prints one line per adoption (`= spoke DF-412 bound to an existing remote item (pull marker), not created`).

```toml
[sync]
apps                             = "notion-taskboard"
notion_taskboard_db              = "<database_id>"      # tenant id: consumer repo only
notion_taskboard_status_map      = "queued=Backlog,executing=In progress,parked=Waiting,shipped=Done"
notion_taskboard_status_default  = "Backlog"            # claimed/speccing/validated land here
notion_taskboard_priority_map    = "u-hi=P0,u-mid=P1,u-lo=P2"
notion_taskboard_weight_map      = "f-hi=2,f-mid=5,f-lo=13"   # optional
notion_taskboard_owner           = "<notion_person_id>"      # optional (people prop)
```

Prop names and types are overridable through `notion_taskboard_props` and `notion_taskboard_types` (JSON); the defaults are Task/Status/Priority/Weight/Owner/Notes and status/select/number/people. Filter keys: `notion_taskboard_only_tags`, `notion_taskboard_skip_tags` (a write-only sink has no intake path). Flags: `--notion-taskboard-db`, `--notion-taskboard-status-map`, `--notion-taskboard-status-default`, `--notion-taskboard-priority-map`, `--notion-taskboard-weight-map`, `--notion-taskboard-owner`, `--notion-taskboard-props`, `--notion-taskboard-types`.

```bash
board sync --apps notion-taskboard --dry-run    # preview, no writes
board sync --apps notion-taskboard              # push new rows
```

## Read-only intake from a foreign team board (`notion-taskboard-pull`)

The mirror image of the push above. It READS the same foreign, team-OWNED Notion board and turns approved rows into queued hub rows; an adapter that creates cards from board rows (the Hermes adapter) then relays them onward. Rows qualify when the `Agent Queue` checkbox is checked and `Status` is not `Done`. A human ticking that checkbox is the whole gate.

Pull-only by shape: the source has a `read()` and no write method, no page-create, no schema PATCH. It writes no state file, because identity lives in the board itself: each intake row carries the Notion page id in its notes cell, matched against the raw board text, so a run is a pure function of (board, query result) and safe to recompute after a lost git push.

Everything the Task Board hands over is untrusted, title as much as notes. Both ride inside a per-item nonce-delimited fence (a fixed sentinel is forgeable with a doubled space or a homoglyph), and five token classes are defanged: the fence sentinel, a page id, a board id, a `#tag` (it decides which apps the row reaches), and credential shapes. Notes clip at 2000 characters and a run intakes at most 25 rows.

The page body (the card's block children) never rides the board row, which must stay one line. The `body_expander` hook fetches it when another adapter creates a task from an intake row, through `ntn` (paragraph, heading, list, to-do, callout and quote text, one level of nesting, paginated), and splices it into the row's fence under `Page body:`. It clips at 8000 characters and passes the same defang and redaction as the other fields. A failed read still creates the task, and the fence says `(page body unavailable)`.

```toml
[sync]
notion_taskboard_pull_db          = "<database_id>"   # tenant id: consumer repo only
notion_taskboard_pull_props       = '{"queue": "Agent Queue"}'   # optional
notion_taskboard_pull_done_option = "Done"            # optional
```

Flags: `--notion-taskboard-pull-db`, `--notion-taskboard-pull-props`, `--notion-taskboard-pull-done-option`. No filter key: the source board's own Agent Queue checkbox is the gate, and the engine refuses `--filter` for this app.

The app is NOT listed beside others in `apps`. It runs alone, on one clone, in its own invocation, and the engine refuses anything else:

```
board sync --apps notion-taskboard-pull      # 1. intake
<commit + push the board>                    # 2. publish
board sync --apps <relay app>                # 3. relay
```

That order is load-bearing. Intake mints a board id and the relay keys its create on it, so the id must be published before anything keys on it; otherwise a rejected push discards the row while the relayed task survives, and the next tick mints a new id and creates a duplicate task.

The `guard` hook refuses a run that names a Notion app when `notion_db` or `notion_taskboard_db` points at the intake database (ids compared with dashes stripped), since those apps write.

## Install notes

- `ntn` must be on `PATH` and logged in (keychain auth). Nothing here stores a Notion token.
- A tenant database id belongs in the consumer repo's `.kit.toml`, never in the kit.

## One invocation

```bash
board sync --dry-run --apps notion
```

## Tests

`test_notion.py`, `test_notion_taskboard.py`, `test_notion_taskboard_pull.py` and `test_ntn.py` in `lib/adapters/tests/` run against a fake `ntn` runner; `test_conformance.py` checks each app against the contract. `fixture-opts.json` holds the map and JSON option values the conformance run needs, because those options reject placeholder strings. No test reaches Notion.
