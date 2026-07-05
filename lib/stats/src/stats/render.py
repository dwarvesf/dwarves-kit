"""Pure formatting: turn an already-fetched row set into one of two human-facing
surfaces. Zero I/O, zero imports from `materialize`/`adapters`/`duckdb`; that absence is
structural (not just documented), so these two functions are trivially testable with a
hand-written/mocked `rows` object and can never re-read a source ledger.

Both functions take the EXACT same input shape: a list of dicts, the shape
`cli.py::_emit`'s `--json` output already produces. Calling both with the same `rows`
object is the single-data-path guarantee (SPEC-128 AC5): one fetched object, two
formatters, never a second read.
"""

from __future__ import annotations

import html as _html

# bot-reply-formatting §5c: cross-platform, mobile-target-unknown heuristic default.
TERMINAL_CELL_BUDGET = 32

_BAR_WIDTH = 10


def _cols(rows: list[dict]) -> list[str]:
    """Column order = first row's key order (matches DuckDB's SELECT * column order,
    which `_emit` already preserves)."""
    if not rows:
        return []
    return list(rows[0].keys())


def _is_numeric(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _cell_str(v) -> str:
    if v is None:
        return ""
    return str(v)


def _looks_like_pct_col(col: str, values: list) -> bool:
    """Heuristic for the bar-fill column (bot-reply-formatting §5e): a numeric column
    named like a percentage. Name-based only (not "all values happen to sit in
    [0, 100]") -- a small-integer count column (e.g. `gates_ran=4`) would otherwise
    false-positive as a bar, which is misleading, not helpful."""
    name = col.lower()
    if not any(k in name for k in ("pct", "percent", "_rate", "ratio")):
        return False
    numeric = [v for v in values if _is_numeric(v)]
    return bool(numeric) and all(0 <= v <= 100 for v in numeric)


def _bar(pct: float, width: int = _BAR_WIDTH) -> str:
    # bot-reply-formatting §5e: max(1, ...) floor on nonzero pct is load-bearing.
    filled = 0 if pct == 0 else max(1, round(pct * width / 100))
    filled = min(filled, width)
    return "▓" * filled + "░" * (width - filled)


def render_terminal(rows: list[dict], title: str | None = None) -> str:
    """A bot-reply-formatting-shaped code-block table: fenced, right-aligned numerics,
    a bar-fill column when a 0-100 numeric column is present. Phone-legible per the
    32-cell heuristic (widths are not force-truncated; a table that outgrows the
    heuristic is a signal to use --surface artifact instead, per the skill's
    surface-selection rule -- this function still renders it, just wider)."""
    lines: list[str] = []
    if title:
        lines.append(f"**{title}**")

    cols = _cols(rows)
    if not cols:
        lines.append("```\n(0 rows)\n```")
        return "\n".join(lines)

    col_values = {c: [r.get(c) for r in rows] for c in cols}
    bar_col = next((c for c in cols if _looks_like_pct_col(c, col_values[c])), None)

    display_cols = list(cols) + ([f"{bar_col} bar"] if bar_col else [])
    numeric_col = {c: all(_is_numeric(v) or v is None for v in col_values[c]) for c in cols}

    str_rows = []
    for r in rows:
        row_cells = [_cell_str(r.get(c)) for c in cols]
        if bar_col is not None:
            v = r.get(bar_col)
            row_cells.append(_bar(v) if _is_numeric(v) else "")
        str_rows.append(row_cells)

    widths = [len(c) for c in display_cols]
    for row_cells in str_rows:
        for i, cell in enumerate(row_cells):
            widths[i] = max(widths[i], len(cell))

    def _fmt_row(cells: list[str]) -> str:
        parts = []
        for i, cell in enumerate(cells):
            is_num = i < len(cols) and numeric_col.get(display_cols[i], False)
            parts.append(cell.rjust(widths[i]) if is_num else cell.ljust(widths[i]))
        return " | ".join(parts)

    bar = "-+-".join("-" * w for w in widths)
    table_lines = ["```"]
    table_lines.append(_fmt_row(display_cols))
    table_lines.append(bar)
    for row_cells in str_rows:
        table_lines.append(_fmt_row(row_cells))
    table_lines.append(f"({len(rows)} row{'s' if len(rows) != 1 else ''})")
    table_lines.append("```")
    lines.append("\n".join(table_lines))
    return "\n".join(lines)


_ARTIFACT_CSS = """
:root { color-scheme: light dark; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: #fafafa; color: #111827; margin: 2rem; line-height: 1.4;
}
h1 { font-size: 1.25rem; margin-bottom: 1rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
th, td { border: 1px solid #374151; padding: 0.4rem 0.6rem; text-align: left; }
th { background: #f0f0f0; font-weight: 600; }
tr:nth-child(even) { background: #f5f5f5; }
.empty { color: #6b7280; font-style: italic; }
@media (prefers-color-scheme: dark) {
  body { background: #111827; color: #f9fafb; }
  th { background: #1f2937; }
  tr:nth-child(even) { background: #1a2233; }
  th, td { border-color: #4b5563; }
}
""".strip()


def render_artifact(rows: list[dict], title: str | None = None) -> str:
    """A complete, self-contained, CSP-safe `<!doctype html>` document: inline <style>
    only, no external requests, light/dark aware. Every cell/title value is
    HTML-escaped before interpolation (a ledger value containing `<`/`&`/`"` must not
    break the table markup or inject a tag -- spec-validate Reviewer 1)."""
    safe_title = _html.escape(title or "ledger query")
    cols = _cols(rows)

    body: list[str]
    if not cols:
        body = ['<p class="empty">(0 rows)</p>']
    else:
        thead = "".join(f"<th>{_html.escape(c)}</th>" for c in cols)
        trs = []
        for r in rows:
            tds = "".join(f"<td>{_html.escape(_cell_str(r.get(c)))}</td>" for c in cols)
            trs.append(f"<tr>{tds}</tr>")
        body = [
            "<table>",
            f"<thead><tr>{thead}</tr></thead>",
            f"<tbody>{''.join(trs)}</tbody>",
            "</table>",
            f'<p class="empty">({len(rows)} row{"s" if len(rows) != 1 else ""})</p>',
        ]

    return (
        "<!doctype html>\n"
        "<html><head><meta charset=\"utf-8\">"
        f"<title>{safe_title}</title>"
        f"<style>{_ARTIFACT_CSS}</style>"
        "</head><body>"
        f"<h1>{safe_title}</h1>"
        + "".join(body)
        + "</body></html>"
    )
