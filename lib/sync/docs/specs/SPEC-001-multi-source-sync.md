# SPEC-001, Multi-source backlog sync (Reminders + Notion + Hermes kanban)

Status: shipped 2026-07-16 (all acceptance criteria proven; see
docs/proof-of-done.md). Owner: the kit `sync` module. Supersedes the
single-source backlog-reminders-sync design (kept as the Reminders adapter).

Amended 2026-07-16 (modularization pass): engine graduated from
ops-toolkit/tools/ into dwarves-kit as registered module `sync` (leg Specify)
at `lib/sync/`, verb `board sync`. Config moved from `_meta/sync.toml` to the
ADR-0034 layer: per-repo `.kit.toml [sync]` keys (declared in kit.toml,
registered in `lib/config/module-registry.md`), resolved in `board.sh
cmd_sync` via `kit-config.sh` and passed to the engine as flags, the engine
reads no TOML (single-reader fence). Boundary with `bridge` (SPEC-147 one-way
cockpit mirror) recorded in the module registry.

## Problem

`_meta/BACKLOG.md` is the source of truth (hub). Han wants it mirrored, two-way,
into three spokes: Apple Reminders (shipped), a Notion board, and the Hermes
kanban DB, with full row data (title, status, notes/desc, #tags) where the spoke
can hold it, and a working bootstrap whether or not a spoke board already exists.

## Design

Hub-and-spoke, one sync run per spoke, three-way merge per spoke against a
per-spoke snapshot (`~/.cache/backlog-sync/<source>.state.json`).

```
                       +----------------------+
                       |  _meta/BACKLOG.md    |  hub / source of truth
                       +----------+-----------+
                                  |  sync_core.py (pure planner)
            +---------------------+----------------------+
            |                     |                      |
   sources/reminders.py   sources/notion.py      sources/hermes.py
   (osascript JXA)        (ntn CLI, Dwarves ws)  (ssh <hermes-host> +
                                                  hermes kanban CLI)
```

### Normalized item (what every adapter returns from `read()`)

`{rid, title, done, body, status}`, `status` is a board keyword
(`queued/…/shipped/…`) when the adapter can state it definitively, else `None`
(then `done=True` reads as a `shipped` proposal). Identity = `ID-NNN` title
prefix (uniform across spokes) + per-spoke rid in the snapshot.

### Adapter contract

```
read() -> list[item]                    # bootstraps the container if missing
apply(plan, assigned, rows_after) -> {board_id: rid}   # created ids
sync_fields: bool                       # title/body updates supported?
name: str
```

Planner emits: `src_create(bid,title,body,status)`, `src_set_title`,
`src_set_body`, `src_set_status(rid, board_kw)`, `board_set_status`,
`board_edit_item`, `board_add(rid,title,body,status)`, `tombstone`.
`src_set_title/body` are only emitted when `sync_fields` (prevents the
stale-echo ping-pong on spokes that cannot edit). `src_set_status` is always
emitted on board-side change; the adapter maps it natively (possibly a no-op
for active-state moves it cannot represent).

### Status semantics (three-way per field)

- Snapshot stores board-keyword status at last sync. Board changed → push to
  spoke. Spoke changed (definitive `status` differs from snapshot) → flip the
  board row. Both → board wins + conflict report.
- Fresh adoption (no snapshot entry): board wins, push board state to spoke.
- New spoke item without ID prefix → new queued board row (spoke's status kept
  when it maps to a board keyword), body captured into Notes cell, then the
  spoke item is retitled/keyed with the assigned ID.
- Deletion on the spoke → tombstone (stop mirroring, never touch the board).
- Only ACTIVE rows are seeded; rows that go inactive while mirrored get their
  spoke item moved to the terminal state (not deleted).

### Per-spoke mapping

| Board | Reminders | Notion (created board) | Hermes kanban |
|---|---|---|---|
| queued/claimed/speccing/validated/executing | open reminder | Status select = exact keyword | `todo` (create); active-state moves not representable → no-op |
| shipped / done / resolved | completed | select = keyword | `complete` → `done` |
| dropped | completed | select = keyword | `archive` → `archived` |
| parked | completed | select = keyword | `archive` |
| reverse (spoke→board) | completed → `shipped` | select keyword verbatim | `done`→`shipped`, `archived`→`dropped`, else no opinion |
| title/notes | bisync (board wins) | bisync (board wins) | frozen at create (no edit verb) |
| #tags | in body text | `Tags` multi_select (derived from Notes) + in Notes | in body text |
| desc / full notes | body | `Notes` rich_text (chunked ≤2000/element) | `--body` at create |

### Bootstrap (has board / has no board)

- **Notion, no board**: create a database under `--notion-parent` (default: US
  Operating page) with `Name` (title), `Status` (select, all board states),
  `Tags` (multi_select), `Notes` (rich_text); resolve its data source; persist
  the binding in the snapshot. **Has board**: `--notion-db <id>` → introspect
  schema, find the title prop + a `Status` select/status prop + optional
  Notes/Tags props; select-type gets missing options added (lossless);
  status-type maps by group (complete-group → shipped; lossy, reverse maps only
  the complete group). Existing foreign pages become board rows (inbox flow).
- **Hermes, no board**: the store IS the board (`hermes kanban create` on a
  fresh HOME initializes it); nothing to create. **Has board**: existing tasks
  without the ID prefix become board rows (inbox flow); `--idempotency-key
  bls-ID-NNN` guards duplicate seeds.
- **Reminders**: list auto-created (shipped behavior).

### Constraints honored

- Notion writes via `ntn` only (Han's rule); keychain auth; Dwarves-workspace
  binding is a flagged caveat (no personal workspace connected).
- Hermes writes via `hermes kanban` verbs only (CAS/event/notify integrity);
  reads via `list --json`; store: `~/hermes-personal/home` (restic-covered);
  no direct sqlite writes; ssh batched into one call per apply.
- Board file writes stay line-targeted; untouched rows byte-identical.

## Acceptance criteria

| # | Criterion |
|---|---|
| 1 | Core planner is source-agnostic; Reminders behavior unchanged (existing suite green after port) |
| 2 | Notion no-board bootstrap creates the DB + seeds every active row with full data (title, status select, tags, notes) |
| 3 | Notion has-board case binds to an arbitrary existing DB (title prop discovery, select vs status handling, foreign-page → inbox row), proven by tests with a fake transport + live re-bind to the created DB |
| 4 | Notion reverse: select change → board status flip; page edits → board (board wins on conflict) |
| 5 | Hermes no-board/empty case seeds via `hermes kanban create --idempotency-key`; `complete`/`archive` map done/dropped both ways; fields frozen (no stale-echo) |
| 6 | Second run per spoke is a no-op (idempotence, negative control) |
| 7 | All adapters covered by tests with fake transports (no network in pytest); live runs recorded in proof-of-done |
| 8 | Docs: README, architecture, this spec; MANIFEST/INVENTORY updated for the rename |

## Test plan

- **Core** (ported + extended): parser, next-id, per-field three-way (status
  push/pull/conflict, adoption board-wins), tombstone, inbox, idempotence
  round-trips, sync_fields=False emits no field actions and imports no stale
  titles.
- **Notion adapter**: fake `ntn` transport asserting exact API bodies, bootstrap create-db, schema introspection (select vs status vs missing
  props), rich_text chunking >2000 chars, tag derivation, query pagination,
  reverse status mapping, option-add on unknown select value.
- **Hermes adapter**: fake ssh transport, list parsing, create batching with
  idempotency keys, complete/archive routing, done/archived reverse mapping,
  no title/body actions.
- **Live** (proof-of-done): Notion bootstrap + seed + idempotence + reverse
  status flip; Hermes seed + idempotence + complete→shipped round trip;
  Reminders regression no-op.
