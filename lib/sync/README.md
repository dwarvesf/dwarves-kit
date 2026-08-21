# board sync (backlog-sync)

Two-way sync between an adopted repo's kanban `BACKLOG.md` (the hub, source
of truth) and its spokes: **Apple Reminders**, a **Notion board**, the
**Hermes kanban**, and a **Multica board** (the self-hosted team pilot, see
ops-toolkit `tools/multica-deploy/`). Registered kit module `sync` (stage: Shape, formerly Specify) at `lib/sync/`;
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
hermes_target     = "<ssh-host>"      # an ssh host, or "local", or "sudo:<user>"; no default
hermes_home       = "<HERMES_HOME>"   # the kanban store to sync against; no default
# optional, for an instance whose board, workers, and deliverables are shared:
# hermes_board     = "dw-ops"
# hermes_assignee  = "chief-of-staff"
# hermes_workspace = "dir:<HERMES_HOME>/outbox/backlog/{id}"
multica_url       = "https://multica.d.foundation"
multica_workspace = "<workspace_uuid>"
multica_project   = "<project_uuid>"
multica_token_ref = "op://Toolkit/multica-sync-bot/credential"
```

Resolution happens in `board.sh cmd_sync` via `kit-config.sh` (the one TOML
reader); the python engine takes flags only and reads no config file. Flags:
`--apps a,b` · `--backlog PATH` · `--state-root PATH` · `--dry-run` ·
`--list` · `--notion-db` / `--notion-parent` · `--hermes-target` /
`--hermes-home` / `--hermes-board` / `--hermes-assignee` /
`--hermes-workspace`. State snapshots live per board at
`~/.cache/backlog-sync/<board-slug>/<source>.state.json`.

### Scheduled runs (cron)

`board sync` is manual by default. Set `mode = "cron"` in a repo's own
`.kit.toml [sync]` section and install a per-repo LaunchAgent via
`lib/sync/deploy/macos/install` (macOS; kit board ID-289) so it runs
unattended:

```toml
[sync]
apps = "reminders,notion"
mode = "cron"
interval_secs = 3600   # optional; default 3600 (hourly)
```

```
bash lib/sync/deploy/macos/install --repo <this repo>            # dry-run
bash lib/sync/deploy/macos/install --repo <this repo> --apply     # loads it
```

The installed job re-checks `mode` on every scheduled run, so flipping it
back to `"manual"` makes the next run skip cleanly rather than keep syncing.
See `lib/sync/deploy/macos/README.md` for the gate (`mode` must be exactly
`cron`, refused otherwise), the service graph, log shape, and BTM/TCC
details.

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
connected). Hermes: the operator sets `hermes_target` + `hermes_home` per machine; neither
key has a default, so an unset one aborts the run instead of guessing a host.

## One-way push to a foreign team board (`notion-taskboard`, SPEC-003)

A fifth app, `notion-taskboard`, is NOT part of the two-way mesh: it is a
one-way, **insert-only** push of a repo's board rows to a foreign, team-OWNED
Notion board (implements ops-toolkit ID-138, design locked 2026-06-16). This push direction (BACKLOG.md rows UP) complements the opposite intake, now served by `notion-taskboard-pull` below (SPEC-004), which absorbs the standalone dfoundation cron that used to pull Task Board rows straight into Hermes. Both apps target the same database by design; they never run in the same invocation, and the engine refuses a run that aims a write-capable app at the pull app's database. The board is the source of truth; the sink is never read for merge and the board
file is never written. Fields are set ONLY on page-create, so a team member's
later edits on the card are never overwritten. The local sync-state map is the
identity index (a `bid` already pushed is never re-pushed), because the team
board's own ID column is a read-only auto-increment that cannot hold `DF-NN`.

Status / Priority / Weight are mapped to the team board's OWN option names via
config, so the sink never mutates the team schema: it reads the schema (never
PATCHes it) and validates every mapped option name exists BEFORE any create, so
a typo'd map value is a hard error instead of a silently auto-created select
option. `dropped` rows are skipped; a state absent from the map uses
`status_default` or, if unset, is a hard guided error. Validation runs at
preflight, so `--dry-run` surfaces config errors with zero writes, and state is
checkpointed after each create so a mid-batch failure never re-pushes a page.

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

Manual full-reconcile (the v1 trigger; a `board set` hook and Discord-on-shipped
are deferred, the latter needs update-detection insert-only v1 does not do):

```
_meta/board sync --apps notion-taskboard --dry-run    # preview, no writes
_meta/board sync --apps notion-taskboard              # push new rows
```

Prop NAMES/TYPES are overridable via `notion_taskboard_props` /
`notion_taskboard_types` (JSON); defaults are Task/Status/Priority/Weight/
Owner/Notes and status/select/number/people.

## Read-only intake from a foreign team board (`notion-taskboard-pull`, SPEC-004)

A sixth app, `notion-taskboard-pull`, is the mirror image of the push above and
absorbs dfoundation's standalone `infra/hermes-kanban-sync` cron (kit ID-479).
It READS the same foreign, team-OWNED Notion board and turns approved rows into
queued hub rows; the existing `hermes` spoke then relays them to the Hermes
kanban, so one engine owns both directions. Rows qualify exactly as the cron
selected them: the `Agent Queue` checkbox is checked and `Status` is not `Done`.
A human ticking that checkbox is the whole gate.

Pull-only by SHAPE: the adapter has a `read()` and no write method, no
page-create, no schema PATCH. Nothing to configure, nothing to flip. It also
writes no state file, because identity lives in the board itself: each intake
row carries the Notion page id in its notes cell, matched against the raw board
text, so a run is a pure function of (board, query result) and safe to
recompute after a lost git push.

Everything the Task Board hands over is untrusted, title as much as notes. Both
ride inside a per-item nonce-delimited fence (a fixed sentinel is forgeable
with a doubled space or a homoglyph), and five token classes are defanged: the
fence sentinel, a page id, a board id (`next_id` scans the whole board text), a
`#tag` (it decides which apps the row reaches), and credential shapes. Notes
clip at 2000 characters and a run intakes at most 25 rows.

```toml
[sync]
notion_taskboard_pull_db          = "<database_id>"   # tenant id: consumer repo only
notion_taskboard_pull_props       = '{"queue": "Agent Queue"}'   # optional
notion_taskboard_pull_done_option = "Done"            # optional
```

The app is NOT listed in `apps`. It runs alone, on one clone, in its own
invocation, and the engine refuses anything else:

```
board sync --apps notion-taskboard-pull      # 1. intake
<commit + push the board>                    # 2. publish
board sync --apps hermes                     # 3. relay
```

That ordering is load-bearing, not stylistic. Intake mints a board id and the
Hermes spoke keys its create on it, so the id must be published before anything
keys on it; otherwise a rejected push discards the row while the kanban task
survives, and the next tick mints a new id and creates a duplicate task. The
engine also refuses a run where `notion_db` or `notion_taskboard_db` points at
the same database, since those apps write. Design, including the git model and
the honest residuals: `docs/specs/SPEC-004-pull-mode-intake.md`.

## Cockpit channel (SPEC-002 P2, ID-290)

`cockpit.py` is the sync-engine re-landing of the legacy `board mirror` bridge:
a MANY-source -> ONE-cockpit channel, distinct from the per-repo two-way spoke
sync above. It reads a `boards.txt` registry (every opted-in repo's BACKLOG.md
plus its active `_meta/megagoals/*/ROADMAP.md`) and keys every item by ORIGIN
(`<repo>:<id>`, `megagoals:<repo>/<slug>`) so many repos pool onto one board
without ID collisions. It honors the legacy `[A-Z]+-[0-9]+` id pattern
(`BACKLOG_ID_RE` override), so prefixed boards (`BK-`, `DS-`, `DF-`, ...) pool
correctly, NOT just bare `ID-`. The diff is `row_hash`-keyed and the board
always wins (the git-wins conflict rule); the git board keyword maps to the
Hermes reachable-state set `{triage, ready, blocked, done}`.

This slice ports the two DETERMINISTIC legs (multi-source extract + the keyed
diff/plan) and is reachable in dry-run:

```
python3 cockpit.py extract --registry _meta/boards.txt          # origin-keyed TSV
python3 cockpit.py plan    --registry _meta/boards.txt [--snapshot F] [--json]
board mirror --engine sync --dry-run                            # same, via the verb
```

The extract (and thus the `row_hash`) is byte-identical to the legacy
`board-mirror.sh` engine, verified with `cmp` on a fixture carrying prefixed
ids, so the existing bridge snapshot is a format-compatible bearing interface
for a later cutover. DEFERRED to
a later slice (still served by the legacy `mirror`/`status`/`writeback` verbs,
which keep working and print a legacy banner): the live Hermes LOAD leg, two-way
status writeback (SPEC-149), snapshot state-shape migration, and retiring those
verbs to thin aliases. Design: `docs/specs/SPEC-002-sync-mesh.md` "P2".

## Tests

```
tests/test-sync.sh    # kit wrapper: pytest over lib/sync/tests (incl. test_cockpit.py)
```

No network in pytest; the live proofs (bootstrap, reverse flips, inbox,
idempotence, per spoke) are recorded in `docs/proof-of-done.md`.
