"""The agent-callable `ledger` CLI. Read-only by contract. Structured output
(`--json` default, `--table` for a human glance)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import typer

from . import anomalies as anomalies_mod, materialize, memory_lens as memory_lens_mod, render as render_mod

app = typer.Typer(
    add_completion=False,
    help="Read-only DuckDB lens over the kit/tide/tg-cleanup/learned ledgers. "
    "The files are canonical; the db is a disposable lens (delete-and-rematerialize).",
)


def _jsonable(v):
    if v is None or isinstance(v, (str, int, float, bool)):
        return v
    return str(v)


def _emit(cols, rows, as_json: bool):
    if as_json:
        out = [{c: _jsonable(v) for c, v in zip(cols, r)} for r in rows]
        typer.echo(json.dumps(out, ensure_ascii=False, indent=2))
        return
    # --table: a minimal box render (no dependency).
    scols = [str(c) for c in cols]
    srows = [[("" if v is None else str(v)) for v in r] for r in rows]
    widths = [len(c) for c in scols]
    for r in srows:
        for i, cell in enumerate(r):
            widths[i] = max(widths[i], len(cell))
    bar = "+" + "+".join("-" * (w + 2) for w in widths) + "+"
    typer.echo(bar)
    typer.echo("| " + " | ".join(c.ljust(widths[i]) for i, c in enumerate(scols)) + " |")
    typer.echo(bar)
    for r in srows:
        typer.echo("| " + " | ".join(cell.ljust(widths[i]) for i, cell in enumerate(r)) + " |")
    typer.echo(bar)
    typer.echo(f"({len(srows)} row{'s' if len(srows) != 1 else ''})")


_FMT = typer.Option(True, "--json/--table", help="output format (json is the default)")


@app.command()
def rebuild():
    """Delete + re-materialize the DuckDB lens from the canonical files."""
    counts = materialize.rebuild()
    typer.echo(json.dumps(counts, indent=2))


@app.command()
def tables(as_json: bool = _FMT):
    """List materialized tables + their row counts."""
    names = materialize.table_names()
    cols = ["table", "rows"]
    rows = [[n, len(materialize.show(n)[1])] for n in names]
    _emit(cols, rows, as_json)


@app.command()
def show(
    name: str = typer.Argument(..., help="a materialized table name"),
    limit: int = typer.Option(None, "--limit", help="cap the number of rows"),
    as_json: bool = _FMT,
):
    """Dump a named table's rows (deterministic order)."""
    try:
        cols, rows = materialize.show(name, limit)
    except ValueError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(2)
    _emit(cols, rows, as_json)


@app.command()
def query(
    sql: str = typer.Argument(..., help="read-only SQL (incl. cross-ledger JOINs)"),
    as_json: bool = _FMT,
):
    """Run arbitrary READ-ONLY SQL over the lens. Write-shaped statements are refused."""
    try:
        cols, rows = materialize.query(sql)
    except PermissionError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(3)
    except Exception as e:  # noqa: BLE001 -- surface DuckDB errors cleanly to the agent
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(4)
    _emit(cols, rows, as_json)


@app.command()
def render(
    name: str = typer.Argument(None, help="a materialized table name (mutually exclusive with --query)"),
    sql: str = typer.Option(None, "--query", help="read-only SQL (mutually exclusive with NAME)"),
    surface: str = typer.Option(..., "--surface", help="terminal | artifact"),
    title: str = typer.Option(None, "--title", help="defaults to the table name or 'ledger query'"),
    limit: int = typer.Option(None, "--limit", help="cap the number of rows (NAME form only)"),
    out: Path = typer.Option(None, "--out", help="also write the rendered surface to this file"),
):
    """Query via the SAME read path as `show`/`query` (no new read), then render ONE
    surface from that one result: --surface terminal (a bot-reply-formatting code-block
    reply) or --surface artifact (a self-contained HTML file for the Artifact tool)."""
    if bool(name) == bool(sql):
        typer.echo("error: give exactly one of NAME or --query", err=True)
        raise typer.Exit(2)
    if surface not in ("terminal", "artifact"):
        typer.echo("error: --surface must be 'terminal' or 'artifact'", err=True)
        raise typer.Exit(2)

    try:
        if name:
            cols, rows = materialize.show(name, limit)
        else:
            cols, rows = materialize.query(sql)
    except ValueError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(2)
    except PermissionError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(3)

    # The ONE data object both surfaces render from (SPEC-128 single-data-path NC):
    # same coercion `_emit`'s --json already uses, built once, passed to one formatter.
    row_dicts = [{c: _jsonable(v) for c, v in zip(cols, r)} for r in rows]
    surface_title = title or (name if name else "ledger query")

    if surface == "terminal":
        output = render_mod.render_terminal(row_dicts, surface_title)
    else:
        output = render_mod.render_artifact(row_dicts, surface_title)

    typer.echo(output)
    if out is not None:
        out.write_text(output, encoding="utf-8")


@app.command(name="gate-yield")
def gate_yield(as_json: bool = _FMT):
    """Per-gate ceremony detector over `kit_gates`: ran/override/skipped/caught + override_pct.
    High `ran` + zero `caught` over many runs is the ceremony signal (a gate that structurally
    cannot fail); this turns that hand probe into a query. Read-only: goes through the SAME
    `materialize.query()` path `show`/`query` already use, no new duckdb connection."""
    cols, rows = materialize.query(
        "SELECT gate, "
        "sum(CASE WHEN outcome = 'ran' THEN 1 ELSE 0 END) AS ran, "
        "sum(CASE WHEN outcome = 'override' THEN 1 ELSE 0 END) AS override, "
        "sum(CASE WHEN outcome = 'skipped' THEN 1 ELSE 0 END) AS skipped, "
        "sum(CASE WHEN caught THEN 1 ELSE 0 END) AS caught, "
        "count(*) AS total, "
        "round(100.0 * sum(CASE WHEN outcome = 'override' THEN 1 ELSE 0 END) "
        "/ count(*), 1) AS override_pct "
        "FROM kit_gates GROUP BY gate ORDER BY gate"
    )
    _emit(cols, rows, as_json)


# conventional-commit fix() subject: `fix:`, `fix(scope):`, `fix(scope)!:`, `fix!:`.
_FIX_SUBJECT_RE = r"^fix(\(.*\))?!?:"


@app.command(name="defect-correlation")
def defect_correlation(
    window_days: int = typer.Option(
        30, "--window-days",
        help="a later fix() commit counts as fix-followed only within this many days of the "
        "rid's first git mention (the coarser join's anchor; see SPEC-132)",
    ),
    as_json: bool = _FMT,
):
    """Retrospective control arm (zero new runs): for each SHIPPED `kit_gates` rid (gate='ship',
    outcome ran/override), bridge it to git history by rid-substring match against a commit
    subject (kit_gates carries no per-file/repo column in v1, so this is the documented coarser
    join, SPEC-132 DEC-001) to find its earliest mentioning commit's OWN files, then check
    whether a LATER fix()-typed commit (within --window-days) touches any of those same files.
    Labeled 'fix-followed', never 'gate-failed': this is correlation, not proof of causation.
    Read-only, same `materialize.query()` path every other command uses."""
    sql = f"""
    WITH shipped AS (
        SELECT DISTINCT rid FROM kit_gates WHERE gate = 'ship' AND outcome IN ('ran', 'override')
    ),
    mentions AS (
        SELECT DISTINCT s.rid, g.sha, g.ts, g.files
        FROM shipped s
        JOIN git_fixes g ON contains(lower(g.subject), lower(s.rid))
    ),
    ship_first AS (
        SELECT rid, min(ts) AS ship_ts FROM mentions GROUP BY rid
    ),
    ship_files AS (
        SELECT m.rid, sf.ship_ts, m.files AS file
        FROM mentions m JOIN ship_first sf ON sf.rid = m.rid AND m.ts = sf.ship_ts
    ),
    later_fix AS (
        SELECT sha, ts, files AS file, subject
        FROM git_fixes WHERE regexp_matches(subject, '{_FIX_SUBJECT_RE}')
    )
    SELECT sfl.rid, sfl.ship_ts, sfl.file,
           CASE WHEN lf.sha IS NOT NULL THEN 'fix-followed' ELSE 'clean' END AS label,
           lf.sha AS fix_sha, lf.ts AS fix_ts, lf.subject AS fix_subject
    FROM ship_files sfl
    LEFT JOIN later_fix lf
        ON lf.file = sfl.file
        AND CAST(lf.ts AS TIMESTAMPTZ) > CAST(sfl.ship_ts AS TIMESTAMPTZ)
        AND CAST(lf.ts AS TIMESTAMPTZ) <= CAST(sfl.ship_ts AS TIMESTAMPTZ) + INTERVAL ({window_days}) DAY
    ORDER BY sfl.rid, sfl.file, lf.ts
    """
    cols, rows = materialize.query(sql)
    _emit(cols, rows, as_json)


@app.command(name="deviation-rate")
def deviation_rate(
    under_specced_min: int = typer.Option(
        3, "--under-specced-min",
        help="n_deviations at or above this count classifies UNDER-SPECCED (named tunable, "
        "SPEC-133)",
    ),
    window_days: int = typer.Option(
        30, "--window-days",
        help="a later fix() commit counts toward SUSPECT only within this many days of the "
        "slug's first git mention (same bridge-anchor semantics as defect-correlation's "
        "--window-days; see SPEC-133 DEC-001)",
    ),
    as_json: bool = _FMT,
):
    """The upstream half of the benchmark: per hook-enforced implementation-notes file
    (`impl_notes`), classify UNDER-SPECCED (n_deviations >= --under-specced-min), CLEAN
    (zero_marker set, no later fix() on the bridge-anchor's own files), SUSPECT (zero_marker
    set AND a later fix() commit on those files), or OTHER (neither: e.g. 1-2 logged
    deviations with no marker, or a file predating the hook's entry-header convention
    entirely). The slug-to-git bridge mirrors defect-correlation's rid-to-git bridge exactly
    (name-match once via `contains(lower(subject), lower(slug))`, then genuine file-equality
    for the actual correlation; SPEC-133 DEC-001). Read-only, same `materialize.query()` path
    every other command uses."""
    sql = f"""
    WITH bridge AS (
        SELECT i.repo, i.file AS note_file, i.slug, g.ts AS anchor_ts, g.files AS anchor_file
        FROM impl_notes i
        JOIN git_fixes g ON contains(lower(g.subject), lower(i.slug))
    ),
    anchor_first AS (
        SELECT repo, note_file, min(anchor_ts) AS anchor_ts FROM bridge GROUP BY repo, note_file
    ),
    anchor_files AS (
        SELECT b.repo, b.note_file, af.anchor_ts, b.anchor_file AS file
        FROM bridge b
        JOIN anchor_first af ON af.repo = b.repo AND af.note_file = b.note_file
            AND b.anchor_ts = af.anchor_ts
    ),
    later_fix AS (
        SELECT sha, ts, files AS file FROM git_fixes
        WHERE regexp_matches(subject, '{_FIX_SUBJECT_RE}')
    ),
    suspect AS (
        SELECT DISTINCT af.repo, af.note_file
        FROM anchor_files af
        JOIN later_fix lf
            ON lf.file = af.file
            AND CAST(lf.ts AS TIMESTAMPTZ) > CAST(af.anchor_ts AS TIMESTAMPTZ)
            AND CAST(lf.ts AS TIMESTAMPTZ) <= CAST(af.anchor_ts AS TIMESTAMPTZ)
                + INTERVAL ({window_days}) DAY
    )
    SELECT i.repo, i.slug, i.file, i.n_deviations, i.zero_marker, i.first_ts, i.last_ts,
        CASE
            WHEN i.n_deviations >= {under_specced_min} THEN 'UNDER-SPECCED'
            WHEN i.zero_marker AND s.note_file IS NOT NULL THEN 'SUSPECT'
            WHEN i.zero_marker THEN 'CLEAN'
            ELSE 'OTHER'
        END AS class
    FROM impl_notes i
    LEFT JOIN suspect s ON s.repo = i.repo AND s.note_file = i.file
    ORDER BY i.repo, i.slug
    """
    cols, rows = materialize.query(sql)
    _emit(cols, rows, as_json)


@app.command(name="review-yield")
def review_yield(
    min_n: int = typer.Option(
        5, "--min-n",
        help="low-n floor (SPEC-137): a (repo, lens) row whose OWN n_rejected, OR the global "
        "raised denominator, is under this count is flagged low_n (never hidden, just labeled)",
    ),
    as_json: bool = _FMT,
):
    """FP-rate per review lens: rejected/raised, beside the review gate's existing catch data
    (gate-yield-style ran/caught). GROUND TRUTH (verified against the real corpus, do not
    re-litigate): `kit_gates` carries no lens or repo column and no findings/rejected columns
    -- `reason` is ONE opaque VARCHAR, and the `review` gate's emit is a WHOLE-REVIEW
    aggregate, never per-lens. THEREFORE this regex-extracts `findings=`/`rejected=` out of
    `reason` itself at query time (`kit_gates`'s own parser is UNTOUCHED, SPEC-131); the raise
    denominator (`raised`) is summed across every `gate='review'` row, GLOBALLY, not per lens.

    The per-lens FP-rate is therefore a deliberate APPROXIMATION (a per-lens numerator over a
    per-run, not per-lens, denominator) -- every row carries a constant `approx=true` column
    so this is never presented as more precise than it is (SPEC-137 DEC-002). `suppressed=`
    (SPEC-081's confidence-gate auto-suppression) is a DIFFERENT axis from a human `rejected=`
    decision and is NEVER added into `raised` (SPEC-137 DEC-003).

    Honest-zero (SPEC-137 DEC's failure-mode table): a repo with no rejected-findings.md file
    contributes NO row, ever (never a fabricated 0-rejected row); if `rejected_findings` has
    ZERO rows overall, this returns ZERO rows (never a fabricated all-NULL row); if `raised`
    is 0, `fp_rate_approx` is NULL for every row (never 0.0). `n_rejected` can legitimately
    exceed `raised` (a numerator/denominator time-scope mismatch inherent to the
    approximation); the resulting rate is reported exactly, never clamped (DEC-004).

    Read-only: goes through the SAME `materialize.query()` path every other command uses, no
    new duckdb connection."""
    sql = f"""
    WITH review_rows AS (
        SELECT
            try_cast(regexp_extract(reason, 'findings=(-?[0-9]+)', 1) AS INTEGER) AS findings,
            try_cast(regexp_extract(reason, 'rejected=(-?[0-9]+)', 1) AS INTEGER) AS rejected,
            caught
        FROM kit_gates
        WHERE gate = 'review' AND outcome IN ('ran', 'override')
    ),
    review_agg AS (
        SELECT
            count(*) AS review_ran,
            count(*) FILTER (WHERE caught) AS review_caught,
            COALESCE(sum(findings), 0) AS sum_findings,
            COALESCE(sum(rejected), 0) AS sum_rejected
        FROM review_rows
    )
    SELECT
        rf.repo, rf.lens, rf.n_rejected, rf.first_ts, rf.last_ts,
        ra.review_ran, ra.review_caught,
        (ra.sum_findings + ra.sum_rejected) AS raised,
        TRUE AS approx,
        CASE WHEN (ra.sum_findings + ra.sum_rejected) > 0
             THEN round(rf.n_rejected * 1.0 / (ra.sum_findings + ra.sum_rejected), 3)
             ELSE NULL END AS fp_rate_approx,
        (rf.n_rejected < {min_n} OR (ra.sum_findings + ra.sum_rejected) < {min_n}) AS low_n
    FROM rejected_findings rf
    CROSS JOIN review_agg ra
    ORDER BY rf.repo, rf.lens
    """
    cols, rows = materialize.query(sql)
    _emit(cols, rows, as_json)


@app.command(name="memory-sweep")
def memory_sweep(as_json: bool = _FMT):
    """Memory-verify sweep (SPEC-136, manual-first, no daemon): walk every memory store (repo
    `.claude/memory/`, built-in `~/.claude/projects/*/memory/`), conservatively extract
    inline-code path/command references, test them against the LIVE environment, and emit the
    paydown table (dead refs + notes stale >180d). PROPOSE-ONLY: calls `memory_lens.scan()`
    directly (a read-only filesystem scan, not the `memories` DuckDB table -- this command
    needs the rich per-reference detail `rebuild`'s compact lens row does not carry); NEVER
    edits or deletes a memory file."""
    units = memory_lens_mod.scan()
    cols = ["store", "slug", "kind", "written", "stale", "dead_ref_count", "dead_refs"]
    rows = []
    for u in units:
        dead = [f"{r.kind}:{r.token}" for r in u.refs if not r.live]
        rows.append([
            u.store, u.slug, u.kind, u.written, memory_lens_mod.is_stale(u.written),
            u.dead_ref_count, "; ".join(dead),
        ])
    _emit(cols, rows, as_json)


@app.command()
def anomalies(
    threshold: list[str] = typer.Option(
        None, "--threshold",
        help="override a default threshold: KEY=VALUE (repeatable). Keys: "
        + ", ".join(sorted(anomalies_mod.DEFAULTS)),
    ),
    propose: bool = typer.Option(
        False, "--propose",
        help="STAGE a proposed backlog row (append to the cc-backlog staging buffer) per "
        "fired anomaly; the operator reviews via `add-backlog`. Never writes a board.",
    ),
    as_json: bool = _FMT,
):
    """Detect anomalies over the SG-02/03/04/05 lenses (READ-ONLY: unpaid-debt count, token-cost
    spike vs rolling median, gate/proof misfire-rate, implementation-notes deviation density,
    gate ceremony via caught/fix-correlation, dep-independent serial-when-parallel runs, and
    (SPEC-135, ARMED) a per-session token-runaway check over the `sessions` table). With
    --propose, STAGE a proposal per fired anomaly into the cc-backlog staging buffer
    (`add-backlog` is the human gate). This tool NEVER auto-files a board row and never mutates
    a ledger."""
    try:
        th = anomalies_mod.parse_thresholds(threshold or [])
    except ValueError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(2)

    fired = anomalies_mod.detect(th)

    if not propose:
        cols = ["key", "title", "metric", "intent"]
        rows = [[a.key, a.title, a.metric, a.intent] for a in fired]
        _emit(cols, rows, as_json)
        return

    staged, skipped = anomalies_mod.stage_proposals(
        fired, anomalies_mod.staging_path(), anomalies_mod.backlog_path()
    )
    cols = ["key", "title", "action"]
    rows = [[a.key, a.title, "staged"] for a in staged]
    rows += [[a.key, a.title, "duplicate"] for a in skipped]
    _emit(cols, rows, as_json)


# The north-star scorecard SQL (SPEC-135): sessions x kit_gates bridged the SAME way
# defect-correlation/ceremony/serial-when-parallel already bridge rid-to-git (name-match once,
# then a genuine shared fact thereafter), here substituting TIME containment for file equality
# since `sessions` carries no file list (SPEC-135 DEC-002). Every "empty" branch (no shipped
# rids, no bridged session) resolves to NULL via an explicit CASE, never a crash, never a
# fabricated number.
_DIGEST_SQL = """
WITH shipped AS (
    SELECT DISTINCT rid FROM kit_gates WHERE gate = 'ship' AND outcome IN ('ran', 'override')
),
mentions AS (
    SELECT DISTINCT s.rid, g.ts
    FROM shipped s
    JOIN git_fixes g ON contains(lower(g.subject), lower(s.rid))
),
ship_first AS (
    SELECT rid, min(ts) AS ship_ts FROM mentions GROUP BY rid
),
bridge AS (
    -- A shipped rid can fall inside MORE THAN ONE session's [first_ts, last_ts] window at once
    -- (parallel worktrees/subagents run concurrent sessions -- the NORM in this repo, not an
    -- edge case). Attributing an outcome's cost to ALL overlapping sessions double-counts the
    -- headline metric (a `kit:code-reviewer` MAJOR finding, SPEC-135 DEC-010). Pick exactly ONE
    -- session per rid -- the CLOSEST-PRECEDING one (greatest `first_ts` still <= `ship_ts`) --
    -- so cost AND time-to-done are both attributed to the SAME single session, one consistent
    -- model. `QUALIFY` filters the window function inline (DuckDB-native).
    SELECT sf.rid, sf.ship_ts, sess.session_id, sess.first_ts AS sess_first,
           sess.input_tokens + sess.output_tokens + sess.cache_read_tokens
               + sess.cache_creation_tokens AS sess_tokens
    FROM ship_first sf
    JOIN sessions sess
      ON CAST(sess.first_ts AS TIMESTAMPTZ) <= CAST(sf.ship_ts AS TIMESTAMPTZ)
     AND CAST(sess.last_ts  AS TIMESTAMPTZ) >= CAST(sf.ship_ts AS TIMESTAMPTZ)
    QUALIFY row_number() OVER (
        PARTITION BY sf.rid
        ORDER BY CAST(sess.first_ts AS TIMESTAMPTZ) DESC, sess.session_id
    ) = 1
),
per_rid AS (
    SELECT rid, ship_ts, sess_first AS start_ts, sess_tokens AS cost_tokens
    FROM bridge
)
SELECT
  (SELECT count(*) FROM sessions) AS total_sessions,
  (SELECT COALESCE(sum(input_tokens), 0) FROM sessions) AS total_input_tokens,
  (SELECT COALESCE(sum(output_tokens), 0) FROM sessions) AS total_output_tokens,
  (SELECT COALESCE(sum(cache_read_tokens), 0) FROM sessions) AS total_cache_read_tokens,
  (SELECT COALESCE(sum(cache_creation_tokens), 0) FROM sessions) AS total_cache_creation_tokens,
  (SELECT COALESCE(sum(tool_call_count), 0) FROM sessions) AS total_tool_calls,
  (SELECT COALESCE(sum(error_count), 0) FROM sessions) AS total_errors,
  (SELECT COALESCE(sum(compaction_count), 0) FROM sessions) AS total_compactions,
  (SELECT COALESCE(sum(canary_drop_count), 0) FROM sessions) AS total_canary_drops,
  (SELECT count(*) FROM shipped) AS shipped_rids,
  (SELECT count(*) FROM per_rid) AS bridged_rids,
  CASE WHEN (SELECT count(*) FROM shipped) = 0 THEN NULL
       ELSE round(100.0 * (SELECT count(*) FROM per_rid) / (SELECT count(*) FROM shipped), 1)
  END AS coverage_pct,
  (SELECT CASE WHEN count(*) = 0 THEN NULL
               ELSE round(sum(cost_tokens) * 1.0 / count(*), 1) END
   FROM per_rid) AS cost_per_verified_outcome_tokens,
  (SELECT CASE WHEN count(*) = 0 THEN NULL
               ELSE round(avg(date_diff('second', CAST(start_ts AS TIMESTAMPTZ),
                                        CAST(ship_ts AS TIMESTAMPTZ))) / 60.0, 1) END
   FROM per_rid) AS avg_time_to_done_min
"""


@app.command()
def digest(
    threshold: list[str] = typer.Option(
        None, "--threshold",
        help="override a default anomaly threshold: KEY=VALUE (repeatable). Keys: "
        + ", ".join(sorted(anomalies_mod.DEFAULTS)),
    ),
    propose: bool = typer.Option(
        False, "--propose",
        help="STAGE fired anomalies into the cc-backlog staging buffer (SAME path "
        "`anomalies --propose` uses; the operator reviews via `add-backlog`).",
    ),
    as_json: bool = _FMT,
):
    """The weekly north-star scorecard (SPEC-135): token efficiency incl.
    cost-per-verified-outcome (a `sessions` x `kit_gates` JOIN, bridged by the SAME
    rid-to-git-subject technique defect-correlation/ceremony/serial-when-parallel already use,
    here bridged further by TIME containment against a session's `[first_ts, last_ts]` window
    since `sessions` carries no file list to compare -- SPEC-135 DEC-002), time-to-done, and
    bridge coverage -- PLUS `anomalies --propose` folded into the ONE command (the SAME
    `anomalies_mod.detect()`/`stage_proposals()` path the `anomalies` command uses, never a
    second detection path). Read-only, same `materialize.query()` path every other command
    uses."""
    try:
        th = anomalies_mod.parse_thresholds(threshold or [])
    except ValueError as e:
        typer.echo(f"error: {e}", err=True)
        raise typer.Exit(2)

    score_cols, score_rows = materialize.query(_DIGEST_SQL)
    fired = anomalies_mod.detect(th)

    if as_json:
        out = {
            "scorecard": [{c: _jsonable(v) for c, v in zip(score_cols, r)} for r in score_rows],
            "anomalies": [{"key": a.key, "title": a.title, "metric": a.metric} for a in fired],
        }
        if propose:
            staged, skipped = anomalies_mod.stage_proposals(
                fired, anomalies_mod.staging_path(), anomalies_mod.backlog_path()
            )
            out["staged"] = [a.key for a in staged]
            out["skipped_duplicate"] = [a.key for a in skipped]
        typer.echo(json.dumps(out, ensure_ascii=False, indent=2))
        return

    typer.echo("== north-star scorecard ==")
    _emit(score_cols, score_rows, False)
    typer.echo("")
    typer.echo("== anomalies ==")
    a_cols = ["key", "title", "metric"]
    a_rows = [[a.key, a.title, a.metric] for a in fired]
    _emit(a_cols, a_rows, False)
    if propose:
        staged, skipped = anomalies_mod.stage_proposals(
            fired, anomalies_mod.staging_path(), anomalies_mod.backlog_path()
        )
        typer.echo("")
        typer.echo("== staged ==")
        p_cols = ["key", "title", "action"]
        p_rows = [[a.key, a.title, "staged"] for a in staged]
        p_rows += [[a.key, a.title, "duplicate"] for a in skipped]
        _emit(p_cols, p_rows, False)


def main():
    app()


if __name__ == "__main__":
    main()
