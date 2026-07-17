# Proof of done, backlog-sync (multi-source, SPEC-001)

## Acceptance criteria

SPEC-001 §Acceptance criteria (8 rows) is the contract; this file is the run
evidence. Short form: source-agnostic core with the Reminders behavior
preserved; Notion + Hermes adapters with both bootstrap cases; full-data
mapping per spoke capability; idempotence per spoke; fake-transport test
coverage; live wiring to Han's data.

## Implementation

`sync_core.py` (pure planner: per-field three-way on status/title/notes,
board wins on conflict) + `sources/{reminders,notion,hermes}.py` adapters +
`backlog_sync.py` CLI. Tests: `tests/test_core.py` + one suite per adapter
with fake transports (no network in pytest).

## Confirmation run-table

| When | Command | Exit | Verdict |
|---|---|---|---|
| 2026-07-16 | `uv run pytest tests/ -q` | 0 | 39 passed (core + 3 adapter suites) |
| 2026-07-16 | `backlog_sync.py --sources reminders --dry-run` | 0 | regression: legacy state migrated, 180 items, `(nothing to do)`, refactor preserved Reminders behavior (criterion 1) |
| 2026-07-16 | `--sources notion --notion-db 612f123c…` (has-board bind) | 0 | criterion 3: discovered title prop, PATCHed missing Status/Notes/Tags into the schema, seeded 180 pages in 2m36s |
| 2026-07-16 | `--sources notion` second run | 0 | NEGATIVE CONTROL: 180 items read back, `(nothing to do)` (criterion 6) |
| 2026-07-16 | e2e sandbox: `--notion-parent` on temp board | 0 | criterion 2: fresh DB created via `initial_data_source` (2025-09 API), rows seeded |
| 2026-07-16 | e2e sandbox: select→shipped + foreign card, then sync ×2 | 0 | criterion 4: board row flipped shipped; foreign card became `ID-4` (kept its `claimed` status), retitled in Notion (verified by query); third sync `(nothing to do)`; sandbox DB trashed after |
| 2026-07-16 | e2e sandbox: hermes fresh `HERMES_HOME=/tmp/bls-e2e-home` | 0 | criterion 5: store self-initialized, 2 seeds; `complete` by "bot" → board shipped; foreign task → inbox row; third sync `(nothing to do)` |
| 2026-07-16 | `--sources hermes` live seed + second run | 0 | 180 tasks created in `~/hermes-personal/home` (batched ssh, 24s, `--idempotency-key bls-*`); read-back on Mini: 180 tasks; second run `(nothing to do)` |
| 2026-07-16 | `backlog_sync.py` (all three spokes) | 0 | triple `(nothing to do)`, the wired steady state |
| 2026-07-16 | kit:advisor review + fixes, then `uv run pytest tests/ -q` | 0 | 42 passed; fixes landed: atomic board/state writes + flock single-writer lock, Hermes skip-notes visible in dry-run, duplicate-board-ID warning (immediately caught 7 real dups on the live board), newline-title flattening, subprocess timeouts, pyproject rename; crash-retry duplicate-create risk disproven by `test_crash_retry_does_not_duplicate_creates` (title-prefix adoption re-links) |
| 2026-07-16 | post-fix `backlog_sync.py` (all three spokes, live) | 0 | dup-ID warning printed + triple `(nothing to do)` |
| 2026-07-16 | kit move: `tests/test-sync.sh` + `_meta/board sync` from ops-toolkit | 0 | engine relocated to dwarves-kit `lib/board/sync/`, front door = `board sync` verb + per-repo `_meta/sync.toml`; per-board state slugs with flat-state migration; 44 pytest green via the kit wrapper; live chain (shim → bin/board → engine + config) verified |
| 2026-07-16 | tags-to-field policy + backfill (`board sync` after clearing notes snapshots) | 0 | Notion Notes text stripped of `#tags`, Tags multi_select carries them (spot-check ID-244: tags=[cloudflare,f-mid,saas,u-mid], notes has zero `#` tokens); Reminders/Hermes keep tags in body, Reminders sdef has ZERO tag surface (verified), Hermes has no tag field |
| 2026-07-16 | board repair + resync (7 dup IDs renumbered → ID-345..351; malformed rows ID-291/292 missing status cell, ID-217/247/250 raw pipes escaped; stale ID-291/292 spoke duplicates purged on all 3 spokes) | 0 | new malformed-row warning caught ID-217/247/250; after repair all rows mirror; steady state 187 items / 350 rows, triple `(nothing to do)` |
| 2026-07-16 | modularization pass: `tests/test-config-registry.sh` + `tests/test-sync.sh` + `tests/test-sync-dispatch.sh` + live `_meta/board sync` | 0 | registered module `sync` (leg Specify), engine at `lib/sync/`, config on the ADR-0034 layer (`.kit.toml [sync]`, resolved in `cmd_sync`, engine reads no TOML); registry lint 19/19, engine suite 44/44, dispatcher suite 5/5 (both board conventions: `_meta/` and root-level BACKLOG.md, user-flag-wins, exit-2 paths), live triple `(nothing to do)` |
| 2026-07-16 | kit:advisor pass 2 (modularization) | 0 | 4 findings, all fixed: repo-root derivation now `_repo_root_for` (root-level-BACKLOG repos resolved `.kit.toml` one dir too high, caught before any fleet adoption), missing-backlog clean exit 2, README module/leg tables gained `sync`, ops-toolkit tombstones updated to `lib/sync` + `.kit.toml`; adopt.sh's stale local module list widened 9-vs-13 (pre-existing tracked gap, noted) |
| 2026-07-16 | Reminders native-tag probe | 0 | NEGATIVE RESULT, title-hashtag idea disproven: JXA-created reminder with `#blstest` in title stays literal text; Reminders store `ZREMCDHASHTAGLABEL` count = 0 after create (read-only sqlite check); tag conversion is a UI input-field parse only, no API/EventKit/Shortcuts surface |

| 2026-07-16 | SPEC-002 P1 audience filters: suites (60 engine + 5 dispatcher + 19 registry) + live rollout | 0 | only_tags/skip_tags down-filter, intake all/tagged/none up-filter, frozen scope-exit/re-enter with scoped_out state, #inbox quarantine on intake rows, scope_exit_cap + --allow-scope-exit; live: notion_skip_tags=family,inbox previewed 3 exits (ID-216/322/323), applied, steady state notion 184 / reminders 187 / hermes 187, triple `(nothing to do)` |

## Run detail

Notion e2e (sandbox, recorded 2026-07-16; sandbox DB trashed after):

```
sync 1: + spoke ID-2 · E2E beta task ...        (bootstrap + seed)
user:   PATCH Status select -> shipped; POST foreign card (claimed, notes)
sync 2: ✓ board ID-2 -> shipped
        + board ID-4 (claimed) <- 'notion inbox test card'
sync 3: (nothing to do)
query:  "ID-4 · notion inbox test card"          (retitle confirmed)
```

Hermes e2e (sandbox HOME on the Mini, recorded 2026-07-16):

```
sync 1: + spoke ID-1 · Hermes e2e alpha, + spoke ID-2 · Hermes e2e beta
user:   hermes kanban complete t_f56e89d0; create 'hermes inbox test task'
sync 2: ✓ board ID-1 -> shipped
        + board ID-3 (queued) <- 'hermes inbox test task'
sync 3: (nothing to do)
```

Multica e2e (live pilot instance multica.d.foundation, sync-bot PAT, temp
fixture board + throwaway state root, recorded 2026-07-16):

```
Command: backlog_sync.py --sources multica --backlog <fixture> --dry-run
  + spoke ID-1 · Prove the multica spoke live, + spoke ID-2 · Row that is already executing
Command: same, real run                       Exit: 0 (both created, backlog/in_progress statuses)
user:    PUT /api/issues/<ID-1 rid> {"status":"done"} on the Multica side
Command: re-sync                              Exit: 0 -> ✓ board ID-1 -> shipped
Command: re-sync (idempotence)                Exit: 0 -> (nothing to do)
board:   flip ID-2 executing -> shipped in the fixture
Command: re-sync (forward)                    Exit: 0 -> ~ spoke <rid> -> shipped (done on Multica)
Verdict: PASS
```

NEGATIVE CONTROLS: every spoke's post-change re-run prints `(nothing to do)`
(criterion 6); `tests/test_core.py::test_deleted_spoke_item_tombstones_never_touches_board`
proves a spoke deletion yields only a tombstone (no board mutation, no
re-create); `tests/test_hermes.py::test_apply_missing_created_id_fails_loud`
proves a silent create failure exits non-zero instead of recording success;
`tests/test_multica.py::test_missing_config_or_token_fails_closed` proves a
missing token exits before any network call, and
`test_read_trusts_marker_until_multica_status_moves` pins the marker rule
that stops the coarser Multica enum from misreporting status changes.

rollback: per spoke, delete the Reminders list / trash the Notion DB /
`hermes kanban archive` the seeded tasks / DELETE the Multica proof issues
(done live: both 204, project back to total=0); then delete
`~/.cache/backlog-sync/<source>.state.json`. The board file is only modified
by reverse-flow events.

## Reproduce

```
cd tools/backlog-sync
uv run pytest tests/ -q
uv run python backlog_sync.py --dry-run                      # all spokes
# sandbox e2e (no real data): temp board + --notion-parent / temp --hermes-home
```
