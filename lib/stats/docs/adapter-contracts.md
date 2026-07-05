# Outlier adapter contracts

The 3 stores that do **not** share the kit's ledger-event envelope
(`ledger-event-schema.md`). Each section is a field-map (source field -> the name +
type `ledger-observatory` exposes it under) plus one real-shaped sample record. **These
are contracts, not code**, SG-02 implements the actual adapter; this spec only pins
what each adapter must produce.

## 1. `learned-ledger.md` (markdown table)

**Store:** `ops-toolkit/_meta/learned-ledger.md`, a single markdown table under its
`## Ledger` heading, one row per learning, newest row at the top (per the file's own
`## Schema` section).

**Field-map:**

| Source column | Observatory field | Type | Note |
|---|---|---|---|
| `date` | `date` | `DATE` (`YYYY-MM-DD`) | |
| `item` | `item` | `TEXT` | short concept name or one-line insight |
| `kind` | `kind` | `TEXT` enum | `concept` \| `insight` \| `decision` |
| `home` | `home` | `TEXT` | `glossary:<track>` \| `til` \| `research` \| `drop` |
| `status` | `status` | `TEXT` | `queued` \| `flushed:<ref>` |

**Sample record** (real row, copied from the live file 2026-07-04):

```markdown
| 2026-07-03 | kill-resilient-delegation | decision | research | flushed:research/2026-07-03-megagoal-execution-hygiene.md#7 |
```

Parses to: `date=2026-07-03 item=kill-resilient-delegation kind=decision home=research
status=flushed:research/2026-07-03-megagoal-execution-hygiene.md#7`.

**Adapter note:** rows are removed once flushed (the file's own doc: "the ledger stays
small by construction"), so this store is a transient queue, not a growing history, an
adapter reading it gets a snapshot, never a full historical log the way Tier A's `runs/`
ledgers are.

## 2. tide `state.sqlite` (SQLite, DuckDB-native)

**Store:** `ops-toolkit/tools/tide/`'s per-machine SQLite database (default path
`state.sqlite`, schema defined in `tools/tide/src/tide/state.py::ensure_schema()`).
DuckDB reads SQLite natively (`ATTACH ... (TYPE sqlite)`), so this "adapter" is a
pointer at the existing table shapes, not a transform.

**Field-map** (5 tables; column list copied verbatim from `ensure_schema()`):

| Table | Columns (verbatim from `CREATE TABLE`) |
|---|---|
| `moves` | `id, ts, source_path, target_path, content_sha, size_bytes, route, confidence, ai_response_json, undone_at` |
| `meta` | `key, value` |
| `tier_b_calls` | `id, ts, cost_usd, input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens, status, backend` |
| `review_queue` | `id, ts, path, peek_json, llm_response_json, reason, resolved_at, resolution` |
| `learned_verdicts` | `id, ts, path, fingerprint_hash, verdict, destination, reason, pattern` |

Observatory-facing field names are the column names unchanged (no rename needed, DuckDB's native SQLite scan exposes them as-is).

**Sample record** (shape only, matching `moves`' column list, a move that has not been
undone):

```
id=1  ts=2026-07-04T09:00:00Z  source_path=~/Downloads/invoice.pdf
target_path=~/Documents/Finance/invoice.pdf  content_sha=<64-hex-sha256>
size_bytes=48213  route=auto:cheap  confidence=0.91  ai_response_json={"category":"finance"}
undone_at=NULL
```

**Adapter note:** `undone_at IS NULL` is the tool's own "active" filter (see the
`idx_moves_active` partial index), the observatory should treat a non-null `undone_at`
row as historical, not current state, mirroring `tide`'s own query pattern rather than
inventing a new one.

## 3. tg-cleanup `*.json` (JSON snapshots, DuckDB-native)

**Store:** `ops-toolkit/tools/tg-cleanup/{review,keep-auto,kill-auto}.json`. DuckDB
reads JSON natively (`read_json_auto`). **These files carry real personal Telegram
contact/group data** (per this repo's privacy rule: never commit personal data
harvested by tools), the sample record below is entirely synthetic; no value was
copied from the live files.

**Two distinct shapes** (edge case 3 in `ledger-event-schema.md`):

- `review.json`: a flat JSON **array** of dialog objects.
- `keep-auto.json` / `kill-auto.json`: a JSON **object** keyed by category name
  (e.g. `keep_personal`, `kill_...`) mapping to an **array** of dialog objects.

**Field-map** (dialog object, same shape in both forms above):

| Source field | Observatory field | Type |
|---|---|---|
| `id` | `dialog_id` | `BIGINT` |
| `title` | `title` | `TEXT` |
| `kind` | `kind` | `TEXT` enum: `basic_group` \| `supergroup` \| `channel` \| ... |
| `username` | `username` | `TEXT` (nullable) |
| `member_count` | `member_count` | `INTEGER` |
| `last_message_date` | `last_message_date` | `TIMESTAMP` (ISO8601 with offset) |
| `unread_count` | `unread_count` | `INTEGER` |
| `muted` | `muted` | `BOOLEAN` |
| `access_hash` | `access_hash` | `BIGINT` (nullable) |
| `verified` / `scam` / `fake` | `verified` / `scam` / `fake` | `BOOLEAN` |
| *(for keep-auto/kill-auto only)* category key | `category` | `TEXT` |

**Sample record** (synthetic, placeholder values only, shape matches the real fields
listed above):

```json
{
  "id": -1000000001,
  "title": "Example Group",
  "kind": "basic_group",
  "username": null,
  "member_count": 3,
  "last_message_date": "2026-01-01T00:00:00+00:00",
  "unread_count": 0,
  "muted": false,
  "access_hash": null,
  "verified": false,
  "scam": false,
  "fake": false
}
```

**Adapter note:** for `keep-auto.json`/`kill-auto.json`, the adapter must carry the
enclosing category key forward as a `category` column (it is not a field on the dialog
object itself, it's the map key) so a query can distinguish "why was this dialog kept
or killed" without losing the object-of-arrays shape's grouping.
