# SPEC-003, One-way insert-only push to a foreign team board

Status: DRAFT 2026-07-18. Implements ops-toolkit board row ID-138 (design
locked 2026-06-16). Extends the SPEC-001 engine with a third posture that sits
alongside the two-way mesh, it does not modify it.

## Problem

ID-138 asks for the DISTRIBUTE half of the work-radar: push a repo's classified
`BACKLOG.md` rows OUT to a per-group sink so a team can see the work. The v1
sink is the Dwarves **Notion Task Board**, a foreign, team-OWNED database with
its own schema (`Task` / `Status` / `Priority` / `Weight` / `Owner` / `Notes`)
and team members who edit the cards after they land.

The existing `NotionSource` (SPEC-001) cannot serve this:

- it is **two-way** (hub-wins), so it would revert a team member's status edit
  on the next run;
- it **mutates the target schema** (`_bind_existing` PATCHes in board-keyword
  `Status`/`Notes`/`Tags` props), which is destructive on a team board;
- it maps status to **board keywords** (`queued`, `executing`, ...), not the
  team board's own option names (`Backlog`, `In progress`, ...);
- it has no `Priority`/`Weight`/`Owner` mapping.

## Locked design (2026-06-16, honored verbatim)

- **One-way**: the board is the source of truth; the sink is never read for
  merge and the board file is never written.
- **Insert-only**: fields are set ONLY on page-create; a row already pushed
  (recorded in the local sync-state map) is never touched again, so team edits
  are never overwritten.
- **Identity map** = a local sync-state file (the Task Board's own ID column is
  a read-only auto-increment, it cannot hold `DF-NN`).
- **Field map**: `title -> Task`, `status -> Status`
  (`queued->Backlog`, `executing->In progress`, `parked->Waiting`,
  `shipped->Done`, `dropped->skip`), `#u-* -> Priority`
  (`hi->P0`, `mid->P1`, `lo->P2`), `#f-* -> Weight`
  (`hi->2`, `mid->5`, `lo->13`, optional), `notes -> Notes`, `Owner = Han`.
- **Trigger**: a manual full-reconcile command (a hook on `board set` is a
  later deploy step, not v1 machinery).
- **Notify**: Discord webhook on `shipped` is deferred to v1.1 (it needs
  update-detection, which insert-only v1 deliberately does not do).
- **Out of v1**: family group, Apple Reminders, Hermes board, two-way sync.

## Design

A source declares `create_only = True`. The engine then runs a dedicated
planner, `plan_create_only`, instead of the two-way `plan_sync`, and a
dedicated apply path, `sync_create_only`, that never writes the board file.
The two-way path and its four live adapters (Reminders/Notion/Hermes/Multica)
are untouched: `create_only` defaults absent, so their behavior and tests are
unchanged.

### `plan_create_only(rows, state, skip_kw, filt)` (pure)

For each board row: skip if its `bid` is already in `state["map"]` (already
pushed), skip if its status is in `skip_kw` (default `{"dropped"}`), skip if it
fails the audience filter (`in_scope`). Everything else becomes one
`src_create`. No `src_set_*`, `board_*`, or `tombstone` is ever produced.

### `NotionTaskBoardSource` (adapter)

- `create_only = True`, `sync_fields = False`, `name = "notion-taskboard"`.
- `read()` returns `[]`: the sink is write-only, we never read the team board.
- `ensure_binding()` resolves the target database's `data_source_id` (a benign
  read, needed as the page-create parent); it NEVER PATCHes the schema. A
  cached binding for a different `db_id` is discarded (a repointed target never
  keeps pushing to the old board).
- `preflight(plan)` reads the schema ONCE (read, never PATCH) to learn each
  prop's type and to validate that every mapped option name (status, priority,
  and select-type weight) already EXISTS on the board. An unknown option is a
  hard error, not a silent auto-create, so the "never mutate the team schema"
  invariant holds even for select-type props (which Notion would otherwise
  auto-extend). Preflight runs before the dry-run return too, so `--dry-run`
  surfaces every config error with zero writes.
- `apply()` handles only `plan.src_create`: it POSTs one page per row and calls
  an `on_created(bid, rid)` callback after each success. The engine checkpoints
  state on that callback, so a mid-batch failure (rate limit, network) never
  leaves a created page unrecorded, i.e. never re-pushes a duplicate next run.
- `skip_kw` = `{"dropped"}`; a `status_default` (config) catches any board
  state not in the status map, else it is a hard, guided error (never a guess).

### Parser scope (`strict_id`)

`parse_board(strict_id=True)` (the two-way mesh) recognizes ONLY `ID-NNN`, so
its id-minting siblings (`next_id`, `apply_board`, `warn_duplicate_ids`) stay
consistent and the two-way path is byte-for-byte unchanged. The one-way push
reads with `strict_id=False` (any `[A-Z]+-NNN`, e.g. `DF-NN`) but never mints
or writes ids; `warn_duplicate_ids` is called with the matching prefix so a
`DF-` board still gets its duplicate/malformed-row warnings.

### Config (`.kit.toml [sync]`, resolved in `board.sh cmd_sync`)

`apps` includes `notion-taskboard`; keys: `notion_taskboard_db` (required),
`notion_taskboard_status_map` (required), `notion_taskboard_status_default`,
`notion_taskboard_priority_map`, `notion_taskboard_weight_map`,
`notion_taskboard_owner`, and per-prop name/type overrides. Tenant IDs (the
Task Board UUID, Han's Notion person id) live ONLY in the consumer repo's
`.kit.toml`, never in this (public) repo.

## Test plan

Fake-`ntn` transport, no network, no live writes.

| # | Case | Assert |
|---|---|---|
| 1 | create pushes mapped fields | Task/Status/Notes/Priority set to the mapped option names; parent is the resolved data_source_id |
| 2 | negative: `dropped` never pushed | a `dropped` row yields no `src_create` |
| 3 | negative: already-pushed row frozen | a `bid` in `state["map"]` yields no `src_create` (idempotent re-run) |
| 4 | `#u-*`/`#f-*` -> Priority/Weight | priority/weight options derived from tags |
| 5 | skip-tag down-filter | a row carrying a skip tag is not pushed |
| 6 | unmapped status + no default | hard SystemExit with guidance |
| 7 | status_default catches unmapped | maps to the default option |
| 8 | board file never written | create-only path performs no board write |
| 9 | missing required config | build_source SystemExit naming the missing key |
| 10 | unknown mapped option | preflight raises (no auto-created team option) |
| 11 | dry-run validates | unmapped status fails on `--dry-run` before any write |
| 12 | partial-batch failure | first create checkpointed; re-run pushes only the rest, never duplicates |
| 13 | repointed target db | cached binding for a stale db_id is rediscarded |
| 14 | `DF-` duplicate row | `warn_duplicate_ids(strict_id=False)` catches it |

## Verification

`bash tests/test-sync.sh` (adds the new adapter + planner cases). Live
activation against the real Task Board is an operator step (dfoundation
`.kit.toml` + a dry-run then real `board sync --apps notion-taskboard`), not
run here (no live team-board writes during build).
