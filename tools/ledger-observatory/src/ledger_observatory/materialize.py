"""Build the DuckDB lens from the canonical files, and query it read-only.

The db is derivable + disposable: `rebuild()` deletes + recreates it; deleting the file
loses nothing. Materialization is the ONLY write, and it writes only the derivable db,
never a source ledger. Queries open the db `read_only=True`.
"""

from __future__ import annotations

import re
from pathlib import Path

import duckdb

from . import adapters, config, schemas

# Python-sourced tables: typed DDL columns, derived from the same `schemas.py`
# `(name, type)` spec that `adapters.py`'s column-name lists derive from. This
# used to be a second, hand-synced definition (the drift bug schemas.py's
# docstring describes); now there is exactly one spec per table.
_KIT_DDL = schemas.ddl(schemas.KIT_SCHEMA)
_TG_DDL = schemas.ddl(schemas.TG_SCHEMA)
_LEARNED_DDL = schemas.ddl(schemas.LEARNED_SCHEMA)
_KIT_GATES_DDL = schemas.ddl(schemas.KIT_GATES_SCHEMA)
_GIT_FIXES_DDL = schemas.ddl(schemas.GIT_FIXES_SCHEMA)
_IMPL_NOTES_DDL = schemas.ddl(schemas.IMPL_NOTES_SCHEMA)
_SESSIONS_DDL = schemas.ddl(schemas.SESSIONS_SCHEMA)
_SAFETY_DDL = schemas.ddl(schemas.SAFETY_SCHEMA)
_MEMORY_DDL = schemas.ddl(schemas.MEMORY_SCHEMA)
_REJECTED_FINDINGS_DDL = schemas.ddl(schemas.REJECTED_FINDINGS_SCHEMA)

# tide tables materialized (2 of the 5 documented; the rest intentionally omitted, see spec).
_TIDE_MOVES_COLS = (
    "id, ts, source_path, target_path, content_sha, size_bytes, route, confidence, "
    "ai_response_json, undone_at"
)
_TIDE_TIER_B_COLS = (
    "id, ts, cost_usd, input_tokens, output_tokens, cache_creation_tokens, "
    "cache_read_tokens, status, backend"
)

# Deterministic ORDER BY per table (spec-validate item 1): makes `show` output stable so
# the delete-and-rematerialize proof is contractual, not incidental on this host.
SHOW_ORDER = {
    "kit_runs": "rid",
    "kit_gates": "rid, gate",
    "git_fixes": "ts, sha, files",
    "impl_notes": "repo, file",
    "tide_moves": "id",
    "tide_tier_b_calls": "id",
    "tg_dialogs": "source_file, dialog_id",
    "learned": "date DESC, item, kind, home, status",
    "sessions": "first_ts, session_id",
    "safety": "ts, status",
    "memories": "store, slug",
    "rejected_findings": "repo, lens",
}

# Read-only query guard (layer 1). `pragma` is deliberately NOT allowlisted: DuckDB's
# assignment PRAGMAs (e.g. `PRAGMA profiling_output='...'`) write a FILE, which a
# read_only=True connection alone does not block. DESCRIBE/SHOW cover read introspection.
_READ_FIRST = {"select", "with", "from", "values", "table", "describe", "show",
               "explain", "summarize"}
_MUTATORS = re.compile(
    r"\b(insert|update|delete|drop|create|alter|attach|detach|copy|replace|truncate|"
    r"install|load|export|import|call|set|begin|commit|rollback|checkpoint|vacuum|"
    r"reset|use)\b",
    re.IGNORECASE,
)


def _load_python_table(con, name: str, ddl: str, cols, rows):
    # Belt-and-suspenders (schemas.assert_parity): cols and ddl both derive from the
    # same schemas.py spec, so this should never fire; it guards against a future edit
    # re-forking the two representations. See schemas.py docstring.
    schemas.assert_parity(cols, ddl)
    con.execute(f"CREATE TABLE {name} ({ddl})")
    if rows:
        placeholders = ", ".join(["?"] * len(cols))
        con.executemany(f"INSERT INTO {name} VALUES ({placeholders})", rows)


def _empty_tide_table(con, name: str, cols: str):
    con.execute(f"DROP TABLE IF EXISTS {name}")
    con.execute(f"CREATE TABLE {name} ({', '.join(c + ' VARCHAR' for c in cols.split(', '))})")


def _load_tide(con):
    """Copy tide's tables via a READ_ONLY sqlite ATTACH. Each table is copied
    INDEPENDENTLY (MED-3): a missing/older-schema table falls back to an empty table on
    its own, never discarding a sibling that copied fine.
    """
    tide_db = config.tide_db_path()
    attached = False
    if tide_db.exists():
        try:
            con.execute(f"ATTACH '{tide_db}' AS tide_src (TYPE sqlite, READ_ONLY)")
            attached = True
        except duckdb.Error:
            attached = False
    for name, cols in (("tide_moves", _TIDE_MOVES_COLS),
                       ("tide_tier_b_calls", _TIDE_TIER_B_COLS)):
        src = "moves" if name == "tide_moves" else "tier_b_calls"
        copied = False
        if attached:
            try:
                con.execute(f"CREATE TABLE {name} AS SELECT * FROM tide_src.{src}")
                copied = True
            except duckdb.Error:
                copied = False
        if not copied:
            _empty_tide_table(con, name, cols)
    if attached:
        try:
            con.execute("DETACH tide_src")
        except duckdb.Error:
            pass


def rebuild() -> dict[str, int]:
    """Delete the db + re-materialize every table from the canonical files.
    Returns a {table: row_count} map.
    """
    path = config.db_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    for p in (path, Path(str(path) + ".wal")):
        if p.exists():
            p.unlink()
    con = duckdb.connect(str(path))
    try:
        cols, rows = adapters.read_kit()
        _load_python_table(con, "kit_runs", _KIT_DDL, cols, rows)
        cols, rows = adapters.read_kit_gates()
        _load_python_table(con, "kit_gates", _KIT_GATES_DDL, cols, rows)
        cols, rows = adapters.read_git_fixes()
        _load_python_table(con, "git_fixes", _GIT_FIXES_DDL, cols, rows)
        cols, rows = adapters.read_impl_notes()
        _load_python_table(con, "impl_notes", _IMPL_NOTES_DDL, cols, rows)
        cols, rows = adapters.read_tgcleanup()
        _load_python_table(con, "tg_dialogs", _TG_DDL, cols, rows)
        cols, rows = adapters.read_learned()
        _load_python_table(con, "learned", _LEARNED_DDL, cols, rows)
        cols, rows = adapters.read_sessions()
        _load_python_table(con, "sessions", _SESSIONS_DDL, cols, rows)
        cols, rows = adapters.read_safety()
        _load_python_table(con, "safety", _SAFETY_DDL, cols, rows)
        cols, rows = adapters.read_memories()
        _load_python_table(con, "memories", _MEMORY_DDL, cols, rows)
        cols, rows = adapters.read_rejected_findings()
        _load_python_table(con, "rejected_findings", _REJECTED_FINDINGS_DDL, cols, rows)
        _load_tide(con)
        counts = {}
        for t in ("kit_runs", "kit_gates", "git_fixes", "impl_notes", "tide_moves",
                  "tide_tier_b_calls", "tg_dialogs", "learned", "sessions", "safety",
                  "memories", "rejected_findings"):
            counts[t] = con.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
        return counts
    finally:
        con.close()


def _ensure_db():
    """Lazy rebuild-on-missing: on-demand refresh (fork 2)."""
    if not config.db_path().exists():
        rebuild()


def _read_conn():
    """A read-only query connection with THREE guarantees stacked:
    - `read_only=True`   : cannot mutate the lens db's catalog/rows.
    - `enable_external_access=False` : cannot touch the FILESYSTEM (no COPY TO, no
      `PRAGMA profiling_output` file write, no `read_csv`/ATTACH of another db). This is
      the real backstop against a write-shaped statement escaping the guard.
    The statement guard (`is_read_only`) is the early, explicit refusal on top.
    """
    _ensure_db()
    return duckdb.connect(
        str(config.db_path()),
        read_only=True,
        config={"enable_external_access": False},
    )


def table_names() -> list[str]:
    con = _read_conn()
    try:
        return [r[0] for r in con.execute("SHOW TABLES").fetchall()]
    finally:
        con.close()


def show(name: str, limit: int | None = None):
    """Return (columns, rows) for a named table, in the pinned deterministic order."""
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError(f"invalid table name: {name!r}")
    con = _read_conn()
    try:
        existing = {r[0] for r in con.execute("SHOW TABLES").fetchall()}
        if name not in existing:
            raise ValueError(f"no such table: {name} (have: {', '.join(sorted(existing))})")
        order = SHOW_ORDER.get(name)
        sql = f"SELECT * FROM {name}"
        if order:
            sql += f" ORDER BY {order}"
        if limit is not None:
            sql += f" LIMIT {int(limit)}"
        rel = con.execute(sql)
        cols = [d[0] for d in rel.description]
        return cols, rel.fetchall()
    finally:
        con.close()


def is_read_only(sql: str) -> bool:
    """The statement guard: a read-only query starts with a read verb AND contains no
    mutating keyword. The read_only=True connection is the hard backstop; this is the
    early, explicit refusal (better error, refuses before touching DuckDB)."""
    stripped = re.sub(r"--[^\n]*", " ", sql)
    stripped = re.sub(r"/\*.*?\*/", " ", stripped, flags=re.DOTALL).strip().rstrip(";")
    if not stripped:
        return False
    # Reject multi-statement input: DuckDB executes every `;`-separated statement in one
    # call, so a read-verb FIRST statement cannot vouch for the rest. A read query is a
    # single statement (one trailing `;` already stripped above).
    if ";" in stripped:
        return False
    first = re.split(r"\s+", stripped, maxsplit=1)[0].lower()
    if first not in _READ_FIRST:
        return False
    return _MUTATORS.search(stripped) is None


def query(sql: str):
    """Run arbitrary READ-ONLY SQL (incl. cross-ledger JOINs). Read-only three ways:
    the statement guard (single read-verb statement, no mutator, no PRAGMA) refuses
    before execution; the connection is `read_only=True`; and `enable_external_access`
    is off so no statement can write the filesystem."""
    if not is_read_only(sql):
        raise PermissionError(
            "refused: read-only lens accepts only a single read query "
            "(SELECT/WITH/FROM/DESCRIBE/SHOW/EXPLAIN/SUMMARIZE), no mutating statements, "
            "no PRAGMA, no multi-statement"
        )
    con = _read_conn()
    try:
        rel = con.execute(sql)
        cols = [d[0] for d in rel.description]
        return cols, rel.fetchall()
    finally:
        con.close()
