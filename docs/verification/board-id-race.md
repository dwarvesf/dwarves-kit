# Proof of done: fetch-before-mint and post-rebase duplicate hold (ID-835)

`next_id`'s history floor (`history_max_id`, `lib/sync/sync_core.py`) read
only the refs the clone already had fetched, so a lagging clone re-minted an
id another session had already pushed to origin. `cmd_publish` (`lib/board/board.sh`)
then committed, hit a non-ff push, ran `pull --rebase --autostash`, which
applied cleanly over the `merge=union` attribute consumer boards carry for
`BACKLOG.md`, and pushed the duplicate with no check. `parse_board` keeps
only the first row per id, so `parse_board`'s callers (the sync snapshot map)
silently pair the newer mint with the older row instead of surfacing a
second row. Live: ops-toolkit ID-871 was minted twice this way on 2026-09-11.

Fix: `history_max_id` fetches origin (best-effort, 10s timeout, deduped once
per repo per process via a module-level set, since `next_id` can call it once
per row minted in one sync) before scanning history. `cmd_publish` scans the
board file for duplicate row ids after a rebase succeeds and before the
second push; a duplicate refuses the push (commit stays local, exit 3) and
prints `WARN duplicate row ids after rebase: <ids>`. A clean ff push is not
scanned: it cannot introduce a collision the pre-push diff did not already
have.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-board-publish.sh` | 0 | PASS 26/26 (new AC8: two clones mint the same row id, second publish rebases over `merge=union`, no push, WARN names the id, remote keeps one row) |
| 2 | `uv run --no-project --with pytest -- pytest lib/sync/tests -q` | 0 | PASS 264/264 (new `test_history_max_id_fetches_origin_once_per_repo`, `test_history_max_id_survives_a_failed_fetch`) |
| 3 | `bash tests/run-all.sh` | 0 | PASS 136/136 suites, 1 skipped for missing tooling |
| 4 | `bash -n lib/board/board.sh` | 0 | PASS |

## Negative control

**Duplicate scan removed** (the `dup_ids` block deleted from `cmd_publish`,
restored via `git checkout --`): `bash tests/test-board-publish.sh` dropped
to 22/26, all 4 failures in the new AC8 case (`rc=0 (want 3)`, no WARN line,
remote gained a second publish commit, wrong ID-2 row count on remote).
Restored, reran 26/26.

**Fetch call removed** (the `_fetched_repos` guard block deleted from
`history_max_id`, restored via `git checkout --`):
`pytest lib/sync/tests/test_core.py -k history_max_id_fetch` failed
`test_history_max_id_fetches_origin_once_per_repo` with `assert 0 == 1` (no
fetch ever ran). Restored, reran the full `lib/sync/tests` suite: 264/264.

## Reproduce

```bash
bash tests/test-board-publish.sh
uv run --no-project --with pytest -- pytest lib/sync/tests -q
bash tests/run-all.sh
```
