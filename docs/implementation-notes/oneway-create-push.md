# Implementation notes: one-way insert-only push (SPEC-003 / ID-138)

Delta from SPEC-003 only.

## 2026-07-18 create-only is a separate path, not a `plan_sync` flag

Context: the locked design is insert-only (never update after create). The
two-way `plan_sync` exists to MERGE, so bending it into strict create-only
would need a flag threaded through every branch, with blast radius on the four
live adapters.
Decision: added `plan_create_only` (pure) + `sync_create_only` (I/O) as a
parallel path, dispatched on `getattr(src, "create_only", False)`. The two-way
path is byte-for-byte unchanged.
Why: zero blast radius; the create-only planner is ~15 lines and trivially
proven with a negative control.
Alternatives: a `create_only` flag inside `plan_sync` (rejected: touches shared
merge logic used by 4 live adapters).
Impact: existing adapter tests unchanged; new logic is independently tested.

## 2026-07-18 the sink is write-only; `read()` returns `[]`

Context: truly one-way means we should not depend on reading the foreign team
board at all. The identity index is the local sync-state map (locked design).
Decision: `NotionTaskBoardSource.read()` returns `[]`; `plan_create_only`
consults `state["map"]` (not a read of the board) to know which rows are
already pushed. `ensure_binding()` still does ONE benign read to resolve the
data_source_id (required as the page-create parent), never a schema PATCH.
Impact: a team member deleting a card is NOT re-created (its bid stays in the
map); re-creating a deleted card is a v1.1 concern, out of the locked scope.

## 2026-07-18 status states the design left unmapped

Context: the locked field map names 5 states (queued/executing/parked/shipped
-> columns, dropped -> skip) but the board has 8 (claimed/speccing/validated
also exist).
Decision: NOT re-designed here. `skip_kw` defaults to `{"dropped"}` only; a
config `status_default` catches any state absent from the status map. If a row
in an unmapped state is reached with no default set, apply raises a guided
SystemExit rather than guessing a column.
Why: the kit ships no tenant policy; the consumer (dfoundation) decides where
claimed/speccing/validated land by setting `status_default` (or extending the
map). Honors "don't re-design" while never silently dropping active work.

## 2026-07-18 review findings applied (kit:code-reviewer + kit:advisor)

Two reviewers independently flagged the same landmines; fixes:
- **Partial-batch duplicates**: `apply()` now takes an `on_created(bid, rid)`
  callback; `sync_create_only` checkpoints state after EACH create. A mid-batch
  `ntn` failure no longer leaves created pages unrecorded (which would re-push
  duplicates on a team board). Plus a `preflight(plan)` validates the whole
  batch (status/priority/weight map + option existence) BEFORE any POST, so a
  config error can't fail a run part-way. Preflight also runs before the
  dry-run return, so `--dry-run` surfaces config errors with zero writes.
- **Select auto-create = silent schema mutation**: the "never mutate the team
  schema" claim was false for select-type props (Notion auto-creates unknown
  select options). Fixed by reading the schema in preflight and rejecting any
  mapped option name not already on the board. This also auto-detects prop
  TYPES from the schema (dropping the earlier "verify types manually" caveat).
- **Parser generalization was half-applied**: reverted `TITLE_RE` to `ID-`-only
  and gave `parse_board` a `strict_id` flag (default True = two-way, ID-only).
  The one-way path passes `strict_id=False`; `warn_duplicate_ids` gained the
  same flag so a `DF-` board still gets dup warnings. Net: the two-way mesh is
  byte-for-byte `ID-`-only again (its id-minting siblings stay consistent), and
  only the create-only READ view widened.
- **Stale binding**: `ensure_binding` discards a cached binding whose `db_id`
  differs from the configured target (a repointed `notion_taskboard_db` no
  longer keeps pushing to the old board).
- Minor: dropped the unused `skip_statuses` ctor param and the dead
  `notion_taskboard_intake` config key (a write-only sink has no intake path).

## 2026-07-18 tenant IDs stay in the consumer repo

Context: this repo (dwarves-kit) is public; the Task Board UUID and Han's
Notion person id are tenant identity.
Decision: the adapter takes db id / maps / owner as config; the dfoundation
`.kit.toml [sync]` carries the real values. No UUID in this repo (asserted by a
grep in the dfoundation PR, not here).
