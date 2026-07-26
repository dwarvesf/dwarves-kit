# Verification: GitHub Issues spoke + per-prefix boards in the sync mesh

Scope: `lib/sync/sources/github.py` (new spoke), prefix threading in
`sync_core.py` / `backlog_sync.py`, `[sync]` wiring in `lib/board/board.sh`.
Pilot board: `dwarvesf/whetstone` `_meta/BACKLOG.md` (WS- prefix), live issues.

## Run table

| Check | Command | Verdict |
|---|---|---|
| Unit suite (all spokes + core) | `uv run --with pytest python -m pytest lib/sync/tests/ -q` | PASS, 170 passed (163 pre-existing + 7 new: 5 github, 2 core-merge; also 5 prefix tests in test_prefix.py) |
| Cold link, no dupes | `board sync --dry-run` on whetstone (4 rows WS-1..4, 4 issues retitled `WS-N ·`) | PASS: "4 spoke items, 4 board rows, (nothing to do)" |
| Board row -> issue | add `WS-5` row, `board sync` | PASS: issue #12 created, title `WS-5 · ...`, body carries `bls: WS-5` idempotency marker |
| Row dropped -> issue closed | flip WS-5 to dropped, `board sync` | PASS: `~ spoke 12 -> dropped`, #12 CLOSED |
| Stability (the oscillation NC) | two further `board sync` runs | PASS: both "(nothing to do)"; row stays `dropped`, #12 stays CLOSED |
| Board wins after board edit | sed row status, one sync, one more | PASS: one `~ spoke` push, then quiet |

## Negative controls (defects this work FOUND live; each now pinned by a test)

1. **ID-hardwired mesh (parse leg).** Before the prefix threading, `board sync`
   on whetstone read "4 spoke items, **0 board rows**" and planned duplicate
   intake for every already-rowed issue. Every cockpit repo has a non-`ID`
   prefix by design, so the two-way mesh was ID-repos-only. Pinned by
   `test_strict_parse_sees_prefixed_rows` (asserts the 0-rows failure on the
   old default AND the fix).
2. **ID-hardwired `TITLE_RE` (link leg).** With parsing fixed, linking still
   failed: 4 rows + 4 matching issues planned 8 duplicates. `TITLE_RE` only
   matched `ID-` titles. Fixed with the generic token; a bid still only links
   when it exists in that board's rows, so boards cannot cross-link.
3. **Binary-spoke status oscillation (engine).** A dropped row with a closed
   issue flipped to `shipped` on EVERY sync: the engine re-derived `shipped`
   from `done=True` and compared keywords against the snapshot. Affects any
   open/done-only spoke (Reminders too), not just GitHub. Fix: when a spoke
   reports `status: None`, compare DONENESS against the snapshot's
   terminal-ness; a reopen flows back as `queued`. Pinned by
   `test_binary_spoke_dropped_row_closed_item_is_stable` and
   `test_binary_spoke_reopen_flows_to_board_as_queued`.

## Reproduce

```
cd <repo>            # gh remote + _meta/BACKLOG.md kanban, any prefix
printf '[sync]\napps = "github"\n' > .kit.toml
board sync --dry-run # inspect, then run without --dry-run
```

Adapter capability envelope is documented in `lib/sync/sources/github.py`'s
header (open/closed only; reopen supported; `sync_fields=False`).

## Second pass: `board init` + `board capture` (2026-07-27)

| Check | Command | Verdict |
|---|---|---|
| init idempotent | `board init` on whetstone (files exist) | PASS: "kept existing" both files, nothing touched |
| init scaffold | `board init` in a fresh scratch repo | PASS: BACKLOG.md header + executable shim created, [sync] hint printed |
| capture e2e | `board capture "<title>" -b "<notes>"` on whetstone | PASS: row WS-6 minted (prefix-aware, via sync_core), sync created issue #14, URL printed AND verified on the clipboard via pbpaste |
| capture without github | (code path) state snapshot missing rid | prints "row is on the board", never fails the filing |

`capture` composes what exists: sync_core mints the row, `cmd_sync` (in a
subshell, since it ends in exec) does the push, the state snapshot yields the
issue number. No second sync implementation.
