# board sync (backlog-sync)

Two-way sync between an adopted repo's kanban `BACKLOG.md` (the hub, source
of truth) and its spokes: **Apple Reminders**, a **Notion board**, the
**Hermes kanban**, and a **Multica board** (the self-hosted team pilot, see
ops-toolkit `tools/multica-deploy/`). Registered kit module `sync` (leg: Specify) at `lib/sync/`;
front door is the `board sync` verb, so every adopted repo's `_meta/board`
shim already reaches it. Design: `docs/specs/SPEC-001-multi-source-sync.md`
(subsystem-local). Spokes plug in per repo via the `[sync]` section of
`.kit.toml` (see below); no `sources` entry, no sync, that's the whole plugin
mechanism. Boundary with the one-way `bridge` cockpit mirror is recorded in
`lib/config/module-registry.md`.

```
                      _meta/BACKLOG.md  (hub)
                
        Apple Reminders   Notion DB   Hermes kanban   Multica project
        (osascript JXA)   (ntn CLI)   (ssh + hermes)  (REST + PAT)
```

Each app syncs independently: three-way merge against a per-spoke snapshot
in `~/.cache/backlog-sync/<source>.state.json`. On conflict the board wins.
A spoke-side deletion tombstones the row (mirroring stops; the board is never
touched). New spoke items without an `ID-` prefix become queued rows in a
`### Reminders inbox` section and get retitled/keyed with their assigned ID.

## What each app can hold

| Field | Reminders | Notion | Hermes | Multica |
|---|---|---|---|---|
| title `ID-NNN · item` | ✓ bisync | ✓ bisync | ✓ frozen at create (no edit verb) | ✓ bisync |
| status | open/completed only (completed ⇄ shipped) | full: `Status` select bisyncs every board state | create=`todo`; `complete` ⇄ shipped, `archive` ⇄ dropped/parked; active moves n/a | full bisync via a fixed-enum map + a `<!-- board:kw -->` description marker (see below) |
| notes/desc | body (board wins, lazy) | `Notes` rich_text (board wins, lazy) | `--body` at create, frozen | description (board wins, lazy); marker appended |
| #tags | in body text (Reminders exposes NO tag API, sdef has zero tag surface) | `Tags` multi_select only; stripped out of the Notes text | in body text | in body text |

Reminders tags have no AppleScript surface; Hermes has no title/body edit or
reopen verb, those cells say "frozen"/"n/a" by capability, not by choice.

Multica's status enum is one notch coarser than the board's state machine
(`speccing`/`claimed` both land on `todo`), so each issue carries its exact
board state in a trailing `<!-- board:kw -->` description marker; the marker
is trusted while the Multica status still equals its forward image, and the
reverse map speaks the moment someone moves the issue on the Multica board.
Issues are always created UNASSIGNED (assigning an agent is what dispatches
execution in Multica; that stays a human act on the Multica UI).

## Run

```
_meta/board sync                     # from any adopted repo: all configured spokes
_meta/board sync --dry-run --apps notion
```

Configure spokes in the repo's `.kit.toml` `[sync]` section (the ADR-0034
config layer; keys declared kit-wide in `kit.toml`, registered in
`lib/config/module-registry.md`). An app plugs in by appearing in `apps` (legacy aliases: `surfaces`, `sources`)
and filling its `<spoke>_*` keys; CLI flags override:

```toml
[sync]
apps              = "reminders,notion,hermes,multica"
reminders_list    = "Backlog"
notion_db         = "<database_id>"   # or notion_parent = "<page_id>" to bootstrap
hermes_target     = "mini-tieubao"
hermes_home       = "/Users/tieubao/hermes-personal/home"
multica_url       = "https://multica.d.foundation"
multica_workspace = "<workspace_uuid>"
multica_project   = "<project_uuid>"
multica_token_ref = "op://Toolkit/multica-sync-bot/credential"
```

Resolution happens in `board.sh cmd_sync` via `kit-config.sh` (the one TOML
reader); the python engine takes flags only and reads no config file. Flags:
`--apps a,b` · `--backlog PATH` · `--state-root PATH` · `--dry-run` ·
`--list` · `--notion-db` / `--notion-parent` · `--hermes-target` /
`--hermes-home`. State snapshots live per board at
`~/.cache/backlog-sync/<board-slug>/<source>.state.json`.

### Bootstrap per app

- **Reminders**: list auto-created on first run.
- **Notion, no board**: `--notion-parent <page_id>` creates a database
  (Name / Status select with every board state / Tags / Notes) and persists
  the binding in the snapshot. **Has board**: `--notion-db <id>` discovers the
  title prop and a `Status` select/status prop, adds missing Notes/Tags/Status
  to the schema, and adopts foreign pages through the inbox flow. Status-type
  props (API can't add options) map by group: Complete ⇄ shipped.
- **Hermes**: the store IS the board; a fresh `HERMES_HOME` initializes on
  first create. Writes go through `hermes kanban` verbs only (CAS + events +
  Discord notify stay intact); seeds carry `--idempotency-key bls-ID-NNN`.
- **Multica**: no auto-bootstrap; point `multica_workspace`/`multica_project`
  at an existing project (the pilot's sync-bot account, workspace, and
  project ids live in `op://Toolkit/multica-sync-bot`). The token resolves
  from `multica_token_ref` at invocation (Keychain-cached `secret-cache-read`,
  raw `op read` fallback) and reaches the engine via the `MULTICA_TOKEN` env
  var, never argv.

Live wiring (2026-07-16): Notion DB `612f123c-7476-4a78-90e2-e1465c0a0df6`
("ops-toolkit Backlog" under US Operating, **Dwarves workspace**, the only
workspace `ntn` is logged into; move it if a personal workspace gets
connected). Hermes: `mini-tieubao`, `~/hermes-personal/home` (restic-covered).

## Tests

```
tests/test-sync.sh    # kit wrapper: pytest over lib/board/sync/tests
```

No network in pytest; the live proofs (bootstrap, reverse flips, inbox,
idempotence, per spoke) are recorded in `docs/proof-of-done.md`.
