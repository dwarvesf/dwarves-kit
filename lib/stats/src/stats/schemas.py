"""Single source of truth for the three Python-sourced table schemas
(kit_runs, tg_dialogs, learned).

Bug this fixes: `adapters.py` used to define its own column-NAME list
(`KIT_COLUMNS` / `TG_COLUMNS` / `LEARNED_COLUMNS`) while `materialize.py`
independently hand-wrote the matching `CREATE TABLE` DDL (`_KIT_DDL` / `_TG_DDL` /
`_LEARNED_DDL`). Nothing checked the two agreed on column names/order, so a
same-length reordering of one without the other would silently mislabel every
column loaded into DuckDB -- exactly the kind of drift this tool exists to catch
in *other* ledgers.

Fix: each table has exactly ONE `(name, type)` spec here. `adapters.py` derives
its column-name list from `column_names()`; `materialize.py` derives its DDL
string from `ddl()`. There is no second place either can drift.
"""

from __future__ import annotations

# Each entry is (column_name, duckdb_type), in physical column order.

KIT_SCHEMA: list[tuple[str, str]] = [
    ("rid", "VARCHAR"),
    ("repo", "VARCHAR"),
    ("lane", "VARCHAR"),
    ("classified", "VARCHAR"),
    ("type", "VARCHAR"),
    ("ctype", "VARCHAR"),
    ("gates_ran", "INTEGER"),
    ("gates_skip", "INTEGER"),
    ("gates_ovr", "INTEGER"),
    ("lane_misroute", "INTEGER"),
    ("type_misroute", "INTEGER"),
    ("shipped", "INTEGER"),
    ("review", "VARCHAR"),
    ("first_ts", "VARCHAR"),
    ("last_ts", "VARCHAR"),
]

TG_SCHEMA: list[tuple[str, str]] = [
    ("source_file", "VARCHAR"),
    ("category", "VARCHAR"),
    ("dialog_id", "BIGINT"),
    ("title", "VARCHAR"),
    ("kind", "VARCHAR"),
    ("username", "VARCHAR"),
    ("member_count", "INTEGER"),
    ("last_message_date", "VARCHAR"),
    ("unread_count", "INTEGER"),
    ("muted", "BOOLEAN"),
    ("access_hash", "BIGINT"),
    ("verified", "BOOLEAN"),
    ("scam", "BOOLEAN"),
    ("fake", "BOOLEAN"),
]

LEARNED_SCHEMA: list[tuple[str, str]] = [
    ("date", "VARCHAR"),
    ("item", "VARCHAR"),
    ("kind", "VARCHAR"),
    ("home", "VARCHAR"),
    ("status", "VARCHAR"),
]

# One row per `| GATE |` kit run-ledger line (SPEC-131). `caught`/`start_ts`/`end_ts` come
# from a SEPARATE, additive `| OUTCOME |` start/end bracket (kit's own SPEC-129), paired by
# phase name; NULL when no bracket exists (true for 100% of the real corpus as of writing --
# see adapters.py `read_kit_gates` docstring). `cost` is the same pairing extended to a
# phase-scoped `| TOKENS |` line (`phase=<gate>`, the rung-4 cost-checkpoint gap-close):
# NULL for every gate whose caller never passed `phase=` to `gate-ledger.sh tokens`, which
# today is every gate except `redteam` (lib/gate/redteam-gate.sh). DOUBLE (not VARCHAR, unlike
# the timestamp columns) because the rung-4 cost checkpoint's whole point is arithmetic over
# it (sum/avg per rid, as a share of the mega's total cost) -- an unparseable TOKENS cost=
# value lands as NULL, never a fabricated 0, so a malformed round is excluded from the
# average rather than silently deflating it.
KIT_GATES_SCHEMA: list[tuple[str, str]] = [
    ("rid", "VARCHAR"),
    ("gate", "VARCHAR"),
    ("outcome", "VARCHAR"),
    ("caught", "BOOLEAN"),
    ("reason", "VARCHAR"),
    ("start_ts", "VARCHAR"),
    ("end_ts", "VARCHAR"),
    ("cost", "DOUBLE"),
]

# The tool's FIRST git-sourced table (SPEC-132). One row per (commit, file-touched) pair
# across a repo's `git log` history -- despite the name (kept literal to the goal file's
# "git_fixes: sha, files, ts, subject"), this stores EVERY commit, not just fix()-typed ones:
# fix-classification is a query-time predicate (`defect-correlation`'s `subject ~ '^fix...'`),
# the same convention `gate-yield` already uses (GROUP BY + CASE WHEN in SQL, not in the
# adapter). Storing the full history is what lets one table answer BOTH sides of the
# correlation: which commit shipped a given kit run (any commit) and which later commit fixed
# it (a fix-typed commit) -- see SPEC-132 DEC-001.
GIT_FIXES_SCHEMA: list[tuple[str, str]] = [
    ("sha", "VARCHAR"),
    ("files", "VARCHAR"),
    ("ts", "VARCHAR"),
    ("subject", "VARCHAR"),
]

# The upstream half of the benchmark (SPEC-133): one row per hook-enforced
# `docs/implementation-notes/<slug>.md` file (NOT per commit -- `file` here is the note file's
# OWN relative path). `deviation-rate` JOINs this against `git_fixes` by bridging `slug` to a
# commit subject the same way SPEC-132 bridges `rid` (two-stage: name-match once, then
# file-equality against the anchor commit's own files), see SPEC-133 DEC-001.
IMPL_NOTES_SCHEMA: list[tuple[str, str]] = [
    ("repo", "VARCHAR"),
    ("slug", "VARCHAR"),
    ("file", "VARCHAR"),
    ("n_deviations", "INTEGER"),
    ("zero_marker", "BOOLEAN"),
    ("first_ts", "VARCHAR"),
    ("last_ts", "VARCHAR"),
]


# The tool's FIRST numeric-only telemetry table (SPEC-135). One row per Claude Code session
# transcript file (`~/.claude/projects/<project-slug>/*.jsonl`). Every column here is a number,
# a timestamp, or a short filesystem-derived slug -- by design, NO column can ever hold message
# text, a tool input/output, or a path from inside a conversation (the privacy boundary this
# sub-goal's whole Proof is built around; see adapters.py `_parse_session_file` docstring and
# `_meta/megagoals/harness-observatory/DECISIONS.md` for the exact field whitelist enforced at
# parse time, not here).
SESSIONS_SCHEMA: list[tuple[str, str]] = [
    ("session_id", "VARCHAR"),
    ("project_slug", "VARCHAR"),
    ("first_ts", "VARCHAR"),
    ("last_ts", "VARCHAR"),
    ("duration_s", "INTEGER"),
    ("input_tokens", "BIGINT"),
    ("output_tokens", "BIGINT"),
    ("cache_read_tokens", "BIGINT"),
    ("cache_creation_tokens", "BIGINT"),
    ("tool_call_count", "INTEGER"),
    ("error_count", "INTEGER"),
    ("compaction_count", "INTEGER"),
    ("canary_drop_count", "INTEGER"),
]

# The safety-posture counter (SPEC-135): one row per secret-guard audit-log line, parsed via a
# fixed leading-bracket regex ONLY (`adapters.read_safety`); the log's free-text remainder
# (confirmed to sometimes carry a real file path) is never captured into any column here.
SAFETY_SCHEMA: list[tuple[str, str]] = [
    ("ts", "VARCHAR"),
    ("status", "VARCHAR"),
    ("session", "VARCHAR"),
    ("tool", "VARCHAR"),
    ("rule", "VARCHAR"),
]


# The tool's SECOND markdown-table adapter (after `learned`): one row per (repo, lens) pair
# aggregated from a repo's `docs/verification/rejected-findings.md` "## Rows" table
# (SPEC-137, gate-review-absorptions mega-goal SG-04; the file format itself is SPEC-144 in
# dwarves-kit's own numbering). NUMBERS ONLY -- `finding-key`/`reason` cell text is read only
# to validate a row's shape, never stored in any column here (see adapters.py
# `read_rejected_findings` docstring for the exact fields never captured).
REJECTED_FINDINGS_SCHEMA: list[tuple[str, str]] = [
    ("repo", "VARCHAR"),
    ("lens", "VARCHAR"),
    ("n_rejected", "INTEGER"),
    ("first_ts", "VARCHAR"),
    ("last_ts", "VARCHAR"),
]

# The tool's first cross-machine hygiene table (SPEC-136): one row per memory FILE (a note or
# its store's own MEMORY.md index) across every memory STORE `memory_lens.scan()` walks (repo
# `.claude/memory/`, builtin `~/.claude/projects/*/memory/`). `written` is the file's most
# recent modification signal (a git commit ts for the git-tracked repo store, else mtime for
# the non-git builtin store -- see `memory_lens.written_ts`); `last_verified` is THIS rebuild's
# own timestamp (the lens has no persisted cross-run state, matching every table's
# delete-and-rematerialize contract). `dead_ref_count` is the number of conservatively
# extracted path/command/index-link references this sweep could NOT confirm live -- see
# `memory_lens.py` for the never-write, conservative-extraction contract.
MEMORY_SCHEMA: list[tuple[str, str]] = [
    ("store", "VARCHAR"),
    ("slug", "VARCHAR"),
    ("written", "VARCHAR"),
    ("last_verified", "VARCHAR"),
    ("dead_ref_count", "INTEGER"),
]


def column_names(schema: list[tuple[str, str]]) -> list[str]:
    """The column-name list an adapter returns, in DDL order."""
    return [name for name, _ in schema]


def ddl(schema: list[tuple[str, str]]) -> str:
    """The `CREATE TABLE` column-def fragment for a schema spec."""
    return ", ".join(f"{name} {type_}" for name, type_ in schema)


def assert_parity(columns: list[str], table_ddl: str) -> None:
    """Defense-in-depth load-time check: even though the column list and the DDL
    both derive from the same spec above, assert they still name the same columns
    in the same order right before a table load. This is a belt-and-suspenders
    guard against a future edit that re-forks the two representations (e.g. someone
    hand-edits one call site's DDL string without going through `ddl()`); it is not
    the primary fix, single-sourcing above is.
    """
    ddl_names = [part.strip().split()[0] for part in table_ddl.split(",") if part.strip()]
    if ddl_names != list(columns):
        raise AssertionError(
            f"schema drift: adapter columns {list(columns)!r} != DDL columns {ddl_names!r}"
        )
