"""The source readers. Each returns (columns, rows); each is skip-safe on a
missing source (returns its known columns + an empty row list). None writes back.

- kit        : REUSES lane-telemetry.sh `_rows()` (the SPEC-061 pipe-log parser). No re-parse.
- kit_gates  : a NEW per-line parser over the same run-ledger files (SPEC-131).
- git_fixes  : `git log` over a repo's full history (SPEC-132), the tool's first git-sourced read.
- impl_notes : a filesystem walk over hook-enforced `docs/implementation-notes/*.md` files
  (SPEC-133), the upstream-unknowns half of the benchmark bridge.
- tide       : DuckDB-native ATTACH (TYPE sqlite), read-only.
- tg         : tg-cleanup *.json, both shapes (array / object-of-arrays), category carried.
- learned    : a small markdown-table adapter over learned-ledger.md.
- sessions   : Claude Code transcript jsonl (SPEC-135), a per-line field ALLOWLIST returning
  NUMBERS/timestamps/short-slugs only -- see `_parse_session_file`'s docstring for the exact
  privacy boundary this adapter enforces.
- safety     : the secret-guard audit log (SPEC-135), a bracket-prefix regex parser; the log's
  free-text remainder is never captured.
- memories   : memory-verify sweep (SPEC-136) over `.claude/memory/` + built-in auto-memory
  stores, via `memory_lens.scan()`; conservative reference extraction, NEVER writes back to a
  memory file -- see `memory_lens.py` for the full contract.
- rejected_findings : per-(repo, lens) aggregate over each configured repo's `docs/
  verification/rejected-findings.md` `## Rows` table (SPEC-137), a NUMBERS-ONLY markdown-table
  adapter (like `learned`); the tool's first genuinely multi-repo-in-one-materialization
  adapter -- see `config.rejected_findings_repos()`.
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import re
import subprocess
import sys
from pathlib import Path

from . import config, memory_lens, schemas

# ---- kit corpus (mandated reuse of lane-telemetry) -------------------------

# lane-telemetry `_rows()` emits a 15-field TSV per run ledger, in this order.
# Column names/order come from `schemas.KIT_SCHEMA`, the single source of truth
# shared with materialize.py's DDL (see schemas.py docstring for the drift bug
# this structurally prevents).
KIT_COLUMNS = schemas.column_names(schemas.KIT_SCHEMA)
_KIT_INT_IDX = {6, 7, 8, 9, 10, 11}  # count/bool columns -> int


def read_kit(lib_dir: Path | None = None):
    """Reuse lane-telemetry's own parser. We source the script and call its private
    `_rows` function; we do NOT re-implement the `ISO8601 | VERB | payload` parse.

    The `|| true; set +e` shape is required because lane-telemetry.sh has no
    `[[ ${BASH_SOURCE} == $0 ]]` guard: sourcing runs `main "$@"` (returns 64 with no
    subcommand) and re-arms `set -euo pipefail`, which would abort the subshell before
    `_rows` is callable. See impl-notes.
    """
    lib = lib_dir or config.kit_lib_dir()
    # Post-restructure (SPEC-182/SG-01): lane-telemetry.sh lives in the telemetry subsystem,
    # not flat at lib/ root. Fall back to the flat path for a pre-restructure kit copy.
    script = lib / "telemetry" / "lane-telemetry.sh"
    if not script.exists():
        script = lib / "lane-telemetry.sh"
    if not script.exists():
        return KIT_COLUMNS, []
    # The script path is passed as an ARGV param ($1), never string-interpolated into the
    # bash body (LOW-2 hardening): a path with quotes/`$(...)` cannot inject.
    cmd = 'source "$1" >/dev/null 2>&1 || true; set +e; _rows'
    try:
        out = subprocess.run(
            ["bash", "-c", cmd, "_", str(script)],
            capture_output=True, text=True, timeout=120,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return KIT_COLUMNS, []
    rows = []
    for line in out.splitlines():
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < len(KIT_COLUMNS):
            fields += [""] * (len(KIT_COLUMNS) - len(fields))
        fields = fields[: len(KIT_COLUMNS)]
        row = []
        for i, v in enumerate(fields):
            if i in _KIT_INT_IDX:
                try:
                    row.append(int(v))
                except ValueError:
                    row.append(0)
            else:
                row.append(v)
        rows.append(row)
    rows.sort(key=lambda r: r[0])  # deterministic: by rid
    return KIT_COLUMNS, rows


# ---- kit gate ledger, per-GATE-line (SPEC-131) -----------------------------

# Column names/order come from `schemas.KIT_GATES_SCHEMA` (single source of truth, see above).
KIT_GATES_COLUMNS = schemas.column_names(schemas.KIT_GATES_SCHEMA)


def _outcome_kv(field: str) -> dict[str, str]:
    """Split an `| OUTCOME |` line's trailing field ("at=123 caught=true dur_s=4") into a
    dict. Tolerant: a token with no '=' is ignored; never raises."""
    out: dict[str, str] = {}
    for tok in field.split():
        if "=" in tok:
            k, _, v = tok.partition("=")
            out[k] = v
    return out


def read_kit_gates(runs_dir: Path | None = None):
    """One row per `| GATE |` ledger line: `(rid, gate, outcome, caught, reason, start_ts,
    end_ts, cost)`. A direct line-level parse of the SAME run-ledger files lane-telemetry.sh's
    `_rows()` aggregates (kit grammar: `TS | GATE | <phase> | ran|skipped|override |
    <reason>`); `_rows()` has no per-line output mode, so this is a NEW small parser, not a
    second copy of an existing one (see impl-notes / SPEC-131 DEC-001).

    `caught` / `start_ts` / `end_ts` come from a SEPARATE, additive `| OUTCOME |` start/end
    bracket (kit's own SPEC-129: `TS | OUTCOME | <phase> | start | at=<epoch>` then `... | end
    | at=<epoch> caught=<bool> dur_s=<N>`), paired to a `GATE` row by matching phase name,
    FIFO per (rid, gate) in file order (SPEC-131 DEC-002).

    `cost` is the SAME FIFO-by-phase pairing extended to a phase-scoped `| TOKENS |` line
    (`TS | TOKENS | in=N out=N cache_read=N cache_create=N cost=<dollars> phase=<gate>`, the
    rung-4 cost checkpoint's gap-close: `lib/gate/redteam-gate.sh` is the one caller that emits
    a `phase=` token today). A bare `| TOKENS |` line with no `phase=` key (every pre-existing
    caller) is invisible to this pairing -- it still feeds lane-telemetry's own rid-wide
    `_token_agg`, untouched by this change. An unparseable `cost=` value (or a phase-tagged
    TOKENS line with none at all) lands as `cost=None`, never a fabricated 0.0.

    Tolerant of: a GATE line with fewer than 4 pipe-fields (skipped, never raises); a GATE line
    missing its reason field (4 cols, not 5; reason -> None); a malformed `at=`/`caught=` token
    (kept/ignored raw, never raises); and a repeated gate name within one rid (each GATE line is
    its own row, never deduped).
    """
    d = runs_dir or (config.kit_log_dir() / "runs")
    if not d.exists():
        return KIT_GATES_COLUMNS, []
    rows = []
    for f in sorted(d.glob("*.log")):
        rid = f.stem
        try:
            text = f.read_text()
        except OSError:
            continue
        pending_start: dict[str, str] = {}
        # phase -> FIFO queue of completed (start_ts, end_ts, caught) brackets.
        brackets: dict[str, list[tuple[str | None, str | None, bool | None]]] = {}
        # phase -> FIFO queue of cost values, from `| TOKENS | ... phase=<phase>` lines only.
        costs: dict[str, list[float | None]] = {}
        gate_lines: list[tuple[str, str, str | None]] = []  # (gate, outcome, reason)
        for line in text.splitlines():
            parts = line.split(" | ")
            if len(parts) < 2:
                continue
            marker = parts[1].strip()
            if marker == "GATE":
                if len(parts) < 4:
                    continue  # too malformed to even name gate+outcome; skip, don't crash
                gate = parts[2].strip()
                outcome = parts[3].strip()
                reason = parts[4].strip() if len(parts) > 4 else None
                gate_lines.append((gate, outcome, reason))
            elif marker == "OUTCOME":
                if len(parts) < 4:
                    continue
                phase = parts[2].strip()
                event = parts[3].strip()
                kv = _outcome_kv(parts[4]) if len(parts) > 4 else {}
                if event == "start":
                    pending_start[phase] = kv.get("at", "")
                elif event == "end":
                    start_ts = pending_start.pop(phase, None)
                    end_ts = kv.get("at")
                    caught = {"true": True, "false": False}.get((kv.get("caught") or "").lower())
                    brackets.setdefault(phase, []).append((start_ts, end_ts, caught))
            elif marker == "TOKENS":
                if len(parts) < 3:
                    continue
                kv = _outcome_kv(parts[2])
                phase = kv.get("phase")
                if not phase:
                    continue  # unscoped TOKENS line: not this table's concern (see docstring)
                raw_cost = kv.get("cost")
                cost: float | None
                try:
                    cost = float(raw_cost) if raw_cost else None
                except ValueError:
                    cost = None  # malformed cost=: excluded from averages, never a fake 0.0
                costs.setdefault(phase, []).append(cost)
        for gate, outcome, reason in gate_lines:
            queue = brackets.get(gate)
            start_ts = end_ts = caught = None
            if queue:
                start_ts, end_ts, caught = queue.pop(0)
            cost_queue = costs.get(gate)
            cost = cost_queue.pop(0) if cost_queue else None
            rows.append([rid, gate, outcome, caught, reason, start_ts, end_ts, cost])
    return KIT_GATES_COLUMNS, rows


# ---- tg-cleanup json (both shapes) -----------------------------------------

# Column names/order come from `schemas.TG_SCHEMA` (single source of truth, see above).
TG_COLUMNS = schemas.column_names(schemas.TG_SCHEMA)


def _tg_dialog_row(source_file: str, category, d: dict):
    return [
        source_file,
        category,
        d.get("id"),
        d.get("title"),
        d.get("kind"),
        d.get("username"),
        d.get("member_count"),
        d.get("last_message_date"),
        d.get("unread_count"),
        d.get("muted"),
        d.get("access_hash"),
        d.get("verified"),
        d.get("scam"),
        d.get("fake"),
    ]


def read_tgcleanup(directory: Path | None = None):
    """Normalize both documented shapes (array vs object-of-arrays). The category key
    of the object-of-arrays form is carried onto each dialog row (adapter-contracts §3).

    `config.tgcleanup_dir()` is None when `STATS_TGCLEANUP_DIR` is unset
    (ops-toolkit-specific source, no default post-05K-move): treated identically to a
    directory that does not exist, never a crash.
    """
    d = directory or config.tgcleanup_dir()
    if d is None or not d.exists():
        return TG_COLUMNS, []
    rows = []
    for f in sorted(d.glob("*.json")):
        try:
            data = json.loads(f.read_text())
        except (OSError, ValueError):
            continue
        if isinstance(data, list):  # review.json: flat array
            for dlg in data:
                if isinstance(dlg, dict):
                    rows.append(_tg_dialog_row(f.name, None, dlg))
        elif isinstance(data, dict):  # keep-auto/kill-auto: object of arrays
            for cat, arr in data.items():
                if isinstance(arr, list):
                    for dlg in arr:
                        if isinstance(dlg, dict):
                            rows.append(_tg_dialog_row(f.name, cat, dlg))
    rows.sort(key=lambda r: (r[0], (r[2] if r[2] is not None else 0)))
    return TG_COLUMNS, rows


# ---- git commit history (SPEC-132, the tool's first git-sourced adapter) --

# Column names/order come from `schemas.GIT_FIXES_SCHEMA` (single source of truth, see above).
GIT_FIXES_COLUMNS = schemas.column_names(schemas.GIT_FIXES_SCHEMA)

# \x1e (record separator) opens each commit's header; \x1f (unit separator) splits the
# header's 3 fields. Both are non-printable control chars that never occur in a real commit
# subject, so no ambiguity with `--name-only`'s newline-delimited file list underneath.
_GIT_LOG_FORMAT = "%x1e%H%x1f%aI%x1f%s"


def read_git_fixes(repo_path: Path | None = None):
    """One row per (commit, file-touched) pair across a repo's FULL `git log` history
    (`--no-merges`: this repo's merges are GitHub squash-merges producing one linear
    conventional commit already, so a true 2+-parent merge carries no file list worth
    reading; SPEC-132 over-test proves one is excluded, not crashed on).

    Read-only: no git WRITE subcommand is ever invoked. Skip-safe: a missing directory, a
    directory with no `.git`, or `git` itself failing/missing all return (columns, []),
    never raise (matches every other adapter's missing-source contract).

    Despite the table name (kept literal to the goal spec), this does NOT pre-filter to
    fix()-typed commits: it is a full commit index. `defect-correlation` classifies
    fix-ness at query time (`subject ~ '^fix(\\(.*\\))?!?:'`), the same convention
    `gate-yield` already uses for its ran/override/skipped classification. See SPEC-132
    DEC-001 for why: one table has to answer BOTH sides of the correlation (which commit
    shipped a run, which later commit fixed it), and pre-filtering to fix-only would lose
    the first side entirely.
    """
    repo = repo_path or config.git_repo_dir()
    if not repo.exists() or not (repo / ".git").exists():
        return GIT_FIXES_COLUMNS, []
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), "log", f"--format={_GIT_LOG_FORMAT}",
             "--name-only", "--no-merges"],
            capture_output=True, text=True, timeout=120,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return GIT_FIXES_COLUMNS, []
    rows = []
    for block in out.split("\x1e"):
        if not block.strip():
            continue
        lines = block.split("\n")
        header = lines[0].split("\x1f")
        if len(header) < 3:
            continue  # malformed header (should not happen with a fixed --format); skip, no crash
        sha, ts, subject = header[0], header[1], header[2]
        for f in lines[1:]:
            f = f.strip()
            if f:
                rows.append([sha, f, ts, subject])
    rows.sort(key=lambda r: (r[2], r[0], r[1]))  # deterministic: by ts, then sha, then file
    return GIT_FIXES_COLUMNS, rows


# ---- implementation-notes files (SPEC-133, the upstream-unknowns bridge) --------------------

# Column names/order come from `schemas.IMPL_NOTES_SCHEMA` (single source of truth, see above).
IMPL_NOTES_COLUMNS = schemas.column_names(schemas.IMPL_NOTES_SCHEMA)

# The hook-enforced entry header (global CLAUDE.md: "## YYYY-MM-DD HH:MM <title>"). Tolerant of
# real prose drift confirmed across the corpus (208 ops-toolkit + 76 dwarves-kit files surveyed
# at design time): the HH:MM time component is frequently dropped entirely (e.g. "## 2026-06-14
# Shipping mechanics ..."), so it is OPTIONAL here, never required to count as an entry.
_ENTRY_HEADER_RE = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2})(?:\s+(\d{2}:\d{2}))?\s+\S")

# The hook-enforced zero-deviation marker line (global CLAUDE.md: one line reading "No
# deviations; matches <spec> verbatim"). Tolerant of real prose drift confirmed across the
# corpus (e.g. "No deviations from spec; no reconcile bug found."): only the leading "No
# deviation(s)" phrase is load-bearing (an optional leading bullet is stripped first), the rest
# is free text. A `## `-prefixed entry header line can never match this (it starts with "#",
# not "no"), so a TITLE merely mentioning "no deviation" as prose (e.g. "## 2026-06-14 Shipping
# mechanics (no deviation from spec, two host quirks)", confirmed present in the real corpus) is
# correctly counted as a real logged entry, never mistaken for the marker (SPEC-133 DEC-002).
_ZERO_MARKER_RE = re.compile(r"^\s*[-*]?\s*no deviations?\b", re.IGNORECASE)

# Directory names never descended into while walking for impl-notes files: hidden dirs (this
# also prunes `.git`, `.venv`, and any nested `.claude/worktrees/<x>` copy of the SAME repo,
# which would otherwise double-count every file underneath it, confirmed a real risk in
# dwarves-kit at design time) plus the usual vendor noise.
_PRUNE_DIR_NAMES = {"node_modules", "dist", "build"}


def _parse_impl_notes_file(path: Path) -> tuple[int, bool, str | None, str | None]:
    """Parse one implementation-notes file's CONTENT only (never filesystem mtime -- the
    schema has no such column by design). Returns `(n_deviations, zero_marker, first_ts,
    last_ts)`; `first_ts`/`last_ts` are `None` when there is no real entry (the marker-only
    case never has one).

    Malformed-file policy (SPEC-133 DEC-003, an explicit over-test case): a file carrying BOTH
    a zero-marker line AND one or more real entry headers is malformed -- the marker's claim
    ("no deviations") directly contradicts the file's own logged content. It is counted as
    entries (`n_deviations` = the real header count) with `zero_marker` forced `False` (a file
    that logged real deviations is never treated as the honest-zero case), and LOGGED (a
    stderr warning), never silently trusted at face value.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return 0, False, None, None

    entries: list[tuple[str, str | None]] = []  # (date, time|None), file order
    marker_line_found = False
    for line in text.splitlines():
        m = _ENTRY_HEADER_RE.match(line)
        if m:
            entries.append((m.group(1), m.group(2)))
            continue
        if _ZERO_MARKER_RE.match(line):
            marker_line_found = True

    n_deviations = len(entries)
    if marker_line_found and n_deviations > 0:
        print(
            f"warning: malformed impl-notes file (zero-marker line AND {n_deviations} real "
            f"entry header(s), contradictory): {path} -- counted as entries, zero_marker "
            "forced False",
            file=sys.stderr,
        )
        zero_marker = False
    else:
        zero_marker = marker_line_found and n_deviations == 0

    if not entries:
        return n_deviations, zero_marker, None, None

    def _key(e: tuple[str, str | None]) -> str:
        date, time = e
        return f"{date} {time}" if time else f"{date} 00:00"

    ordered = sorted(entries, key=_key)
    return n_deviations, zero_marker, _key(ordered[0]), _key(ordered[-1])


def read_impl_notes(repo_path: Path | None = None):
    """One row per hook-enforced `docs/implementation-notes/<slug>.md` file found anywhere
    under a repo root (SPEC-133): `(repo, slug, file, n_deviations, zero_marker, first_ts,
    last_ts)`.

    Shares `config.git_repo_dir()` with `read_git_fixes` rather than a second env knob
    (SPEC-133 DEC-001): `deviation-rate`'s SUSPECT/CLEAN classification JOINs the two tables,
    and both must describe the SAME repo or the join silently drifts apart per-invocation.

    Read-only: no write, ever. Skip-safe: a missing repo path returns (columns, []), matching
    every other adapter's contract. The directory walk PRUNES hidden dirs (`.git`, `.venv`,
    and any nested `.claude/worktrees/<x>` copy of this same repo) plus `node_modules`/`dist`/
    `build`, so a repo containing its own git worktrees never double-counts a file.
    """
    repo = repo_path or config.git_repo_dir()
    if not repo.exists():
        return IMPL_NOTES_COLUMNS, []
    repo_label = repo.name

    rows = []
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in _PRUNE_DIR_NAMES]
        dp = Path(dirpath)
        if dp.name != "implementation-notes" or dp.parent.name != "docs":
            continue
        for fname in sorted(filenames):
            if not fname.endswith(".md"):
                continue
            fpath = dp / fname
            slug = fpath.stem
            try:
                rel = str(fpath.relative_to(repo))
            except ValueError:
                rel = str(fpath)
            n_dev, zero_marker, first_ts, last_ts = _parse_impl_notes_file(fpath)
            rows.append([repo_label, slug, rel, n_dev, zero_marker, first_ts, last_ts])
    rows.sort(key=lambda r: (r[0], r[2]))  # deterministic: by repo, then file path
    return IMPL_NOTES_COLUMNS, rows


# ---- learned-ledger.md (markdown table) ------------------------------------

# Column names/order come from `schemas.LEARNED_SCHEMA` (single source of truth, see above).
LEARNED_COLUMNS = schemas.column_names(schemas.LEARNED_SCHEMA)


def read_learned(md_path: Path | None = None):
    """Parse the markdown table under the `## Ledger` heading (adapter-contracts §1).
    Rows are removed on flush, so this is a snapshot (possibly 0 rows), never an error.

    `config.learned_md_path()` is None when `STATS_LEARNED_MD` is unset
    (ops-toolkit-specific source, no default post-05K-move): treated identically to a
    file that does not exist, never a crash.
    """
    p = md_path or config.learned_md_path()
    if p is None or not p.exists():
        return LEARNED_COLUMNS, []
    rows = []
    in_ledger = False
    seen_header = False
    for line in p.read_text().splitlines():
        s = line.strip()
        if s.startswith("## "):
            in_ledger = s.lower().startswith("## ledger")
            seen_header = False
            continue
        if not in_ledger or not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if not seen_header:  # the header row `| date | item | ... |`
            seen_header = True
            continue
        if set("".join(cells)) <= set("-: "):  # the `|---|---|` separator
            continue
        if len(cells) < len(LEARNED_COLUMNS):
            cells += [""] * (len(LEARNED_COLUMNS) - len(cells))
        rows.append(cells[: len(LEARNED_COLUMNS)])
    return LEARNED_COLUMNS, rows


# ---- rejected-findings ledger, per-(repo, lens) aggregate (SPEC-137) ----------------------

# Column names/order come from `schemas.REJECTED_FINDINGS_SCHEMA` (single source of truth).
REJECTED_FINDINGS_COLUMNS = schemas.column_names(schemas.REJECTED_FINDINGS_SCHEMA)

# The `## Rows` heading only (SPEC-144's format: a `## Format` section carries a TEMPLATE row
# with placeholder cells like `\<lens...\>` earlier in the same file -- that section is a
# different heading and must never be read as data; see `learned`'s own "## Ledger"-only
# heading-scope precedent, generalized to a second heading name here).
_REJECTED_ROWS_HEADING_RE = re.compile(r"^##\s+rows\s*$", re.IGNORECASE)

# The ONE accepted-verbatim field (`date`), a light ISO8601-date shape-gate (SPEC-137 edge
# case 4): a row whose date cell does not match this is skipped, counted, never persisted raw.
_REJECTED_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def _parse_rejected_findings_file(path: Path, repo_label: str) -> tuple[dict[str, list[str]], int]:
    """Parse ONE repo's `docs/verification/rejected-findings.md`, `## Rows` heading only:
    `| date | lens | finding-key | verdict | reason |`. Returns `({lens: [date, ...]},
    skipped_count)`. `finding-key`/`reason` cells are read only to confirm the row has 5
    cells; neither is ever added to the returned dict (SPEC-137's numbers-only contract).

    Skipped-and-counted, never raised: a row with fewer than 5 cells (edge case 2), a row
    whose `verdict` cell is not (case-insensitively) `rejected` (edge case 3 -- the file's own
    contract says only a human rejection ever appends a row here, so anything else is
    unexpected, not silently trusted), a row whose `date` cell is not `YYYY-MM-DD` (edge case
    4). The `## Format` section's own template row is never reached (different heading).
    """
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}, 0
    in_rows = False
    seen_header = False
    per_lens: dict[str, list[str]] = {}
    skipped = 0
    for line in text.splitlines():
        s = line.strip()
        if s.startswith("## "):
            in_rows = bool(_REJECTED_ROWS_HEADING_RE.match(s))
            seen_header = False
            continue
        if not in_rows or not s.startswith("|"):
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if not seen_header:  # the header row `| date | lens | ... |`
            seen_header = True
            continue
        if set("".join(cells)) <= set("-: "):  # the `|---|---|` separator
            continue
        if len(cells) < 5:
            skipped += 1
            continue
        date, lens, _finding_key, verdict, _reason = cells[0], cells[1], cells[2], cells[3], cells[4]
        if verdict.strip().lower() != "rejected":
            skipped += 1
            continue
        if not _REJECTED_DATE_RE.match(date):
            skipped += 1
            continue
        per_lens.setdefault(lens, []).append(date)
    return per_lens, skipped


def read_rejected_findings(repos: list[Path] | None = None):
    """One row per (repo, lens) pair with `>= 1` rejected finding, across every repo in
    `repos` (default `config.rejected_findings_repos()`, SPEC-137 DEC-001): `(repo, lens,
    n_rejected, first_ts, last_ts)`.

    Skip-safe PER REPO: a repo whose `docs/verification/rejected-findings.md` does not exist
    contributes ZERO rows for that repo (never an exception, never a fabricated 0-rejected
    placeholder -- edge case 1); a repo whose ledger file exists but has zero real rows in its
    `## Rows` table likewise contributes zero rows. Malformed rows are skipped-and-counted
    (see `_parse_rejected_findings_file`); the total skip count across all repos is logged
    once as a single stderr warning (never raised, matching every other adapter's tolerant
    contract), naming the count so a silent mass-skip is at least visible.

    Read-only: only ever `Path.read_text`s a file, never writes. NUMBERS ONLY: `finding-key`
    and `reason` cell text is read only inside `_parse_rejected_findings_file` to validate a
    row's shape and is never returned in any column (SPEC-137's stated contract: "finding TEXT
    stays in the repo file").
    """
    repo_list = repos if repos is not None else config.rejected_findings_repos()
    rows: list[list] = []
    total_skipped = 0
    for repo in repo_list:
        f = repo / "docs" / "verification" / "rejected-findings.md"
        if not f.exists():
            continue
        per_lens, skipped = _parse_rejected_findings_file(f, repo.name)
        total_skipped += skipped
        for lens, dates in per_lens.items():
            dates_sorted = sorted(dates)
            rows.append([repo.name, lens, len(dates_sorted), dates_sorted[0], dates_sorted[-1]])
    if total_skipped:
        print(
            f"warning: rejected_findings skipped {total_skipped} malformed row(s) across "
            f"{len(repo_list)} configured repo(s)",
            file=sys.stderr,
        )
    rows.sort(key=lambda r: (r[0], r[1]))  # deterministic: by repo, then lens
    return REJECTED_FINDINGS_COLUMNS, rows


# ---- Claude Code session transcripts (SPEC-135, numeric-only) --------------------------------

# Column names/order come from `schemas.SESSIONS_SCHEMA` (single source of truth, see above).
SESSIONS_COLUMNS = schemas.column_names(schemas.SESSIONS_SCHEMA)

# The exact trailing line the global `~/.claude/CLAUDE.md` adherence canary mandates on every
# assistant reply. Checked ONLY to derive a per-turn boolean (see `_parse_session_file` below);
# the text itself is never persisted, matching every other text block this adapter touches
# (SPEC-135 DEC-003).
_CANARY_LINE = "\U0001f431 Neko-san"  # the cat-emoji + "Neko-san" canary line

# A light ISO8601 shape-gate for the ONE accepted-verbatim field (`timestamp`). Defense in
# depth (SPEC-135 DEC-009): `timestamp` is harness-synthesized, not conversation-derived, so
# this is not a real leak surface, but the adapter's stated principle is a strict allowlist that
# never trusts a transcript field's shape -- a non-ISO8601 string is dropped (that line's ts
# contribution only, not the whole line) rather than persisted raw into first_ts/last_ts.
_TS_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T")


def _safe_int(v) -> int:
    """Coerce a whitelisted numeric field to int, returning 0 on anything non-numeric (never
    raises). A bare `int(x)` on a valid-JSON-but-non-numeric field raises a ValueError whose
    message embeds `x` verbatim; this helper is the privacy-safe coercion the parse loop uses so
    such a value can never reach a CLI traceback (mirrors `_duration_seconds`'s own never-raise
    contract; a `kit:code-reviewer` CRITICAL finding, SPEC-135 DEC-008)."""
    try:
        return int(v or 0)
    except (ValueError, TypeError):
        return 0


def _parse_session_file(path: Path) -> list | None:
    """Parse ONE session `*.jsonl` file into one row of NUMBERS/timestamps/short-slugs ONLY --
    the field whitelist named in SPEC-135's Technical Design and copied verbatim into
    `_meta/megagoals/harness-observatory/DECISIONS.md` for review. Per line, this function reads
    ONLY: `type`, `subtype` (system lines), `timestamp`, `message.usage.{input_tokens,
    output_tokens,cache_read_input_tokens,cache_creation_input_tokens}`, `message.stop_reason`,
    `message.content[].type`, `message.content[].is_error` (tool_result items),
    `message.content[].text` (text items, read TRANSIENTLY -- see below). It NEVER reads `cwd`,
    `sessionId`, `gitBranch`, `model`, `uuid`, `tool_use.input`, `tool_result.content` (confirmed
    during design-time probing to carry raw file text verbatim), `custom-title`, `last-prompt`,
    `agent-name`, `attachment`, or any other key -- those are simply never assigned to a local
    variable, so there is no return path by which they could leak into a row.

    The one `text` field this function DOES read is handled transiently: on a terminal assistant
    turn (`stop_reason != "tool_use"`), the LAST text block is glanced at ONLY to test whether it
    ends with the adherence-canary marker, producing a single boolean (`canary_drops += 1` on a
    miss); the string itself is reassigned to `None` immediately after the check and is never
    appended to any accumulator, logged, or returned. This applies to every text block
    encountered, not only ones near the canary check, so even a real secret pasted into a
    message is only ever glanced at in memory, never captured (SPEC-135 DEC-003/DEC-006).

    Confirmed during design-time AND real-corpus smoke-testing: `tool_result` blocks (and their
    `is_error` flag) live under a `type == "user"` line (the tool-result turn Claude Code
    synthesizes back to the model), NEVER under the `type == "assistant"` line that emitted the
    matching `tool_use` block. `error_count` therefore ALSO scans `type == "user"` lines -- but
    ONLY for `content[].type == "tool_result"` / `.is_error`; a `type == "user"` line's `text`
    content (Han's own raw prompt) is never even inspected, let alone read transiently the way
    assistant text is (a stricter rule than the assistant-text case, since this text was never
    meant to be machine-classified at all).

    Sidechain (subagent, `isSidechain: true`) turns are interleaved inline in the SAME file and
    are NOT filtered out: every assistant-typed line in a file contributes to that one file's row
    (SPEC-135 DEC-006 -- one file is one session, whether or not it dispatched subagents).

    Tolerant: a malformed/truncated JSON line is skipped, never raises; a file with zero
    timestamped lines returns `None` (no row -- an empty/junk file is not a counted session).
    """
    first_ts = last_ts = None
    input_tokens = output_tokens = cache_read = cache_creation = 0
    tool_calls = errors = compactions = canary_drops = 0
    try:
        with path.open(encoding="utf-8") as fh:
            for line in fh:
                # The WHOLE per-line body is wrapped in a broad `except Exception: continue`
                # (not just json.loads). This is a privacy guard, not only a robustness one: a
                # bare `int(usage_field)` on a valid-JSON-but-non-numeric value raises a
                # ValueError whose message embeds the offending value VERBATIM; if that
                # propagated out of rebuild() into a CLI traceback it would print transcript-
                # sourced content in the clear (a `kit:code-reviewer` CRITICAL finding on the
                # finished diff, SPEC-135 DEC-008). One malformed line is skipped, never crashes
                # the whole file's parse and never surfaces its content in an exception string.
                try:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        d = json.loads(line)
                    except (ValueError, TypeError):
                        continue  # malformed/truncated line: skip, never crash the file's parse
                    if not isinstance(d, dict):
                        continue
                    ts = d.get("timestamp")
                    if isinstance(ts, str) and _TS_RE.match(ts):
                        if first_ts is None or ts < first_ts:
                            first_ts = ts
                        if last_ts is None or ts > last_ts:
                            last_ts = ts
                    dtype = d.get("type")
                    if dtype == "system":
                        if d.get("subtype") == "compact_boundary":
                            compactions += 1
                        continue
                    if dtype == "user":
                        # ONLY the tool_result/is_error shape is ever inspected here -- a user
                        # line's own text content (a real prompt) is never read, not even
                        # transiently (stricter than the assistant-text case above).
                        msg = d.get("message")
                        content = msg.get("content") if isinstance(msg, dict) else None
                        if isinstance(content, list):
                            for c in content:
                                if (isinstance(c, dict) and c.get("type") == "tool_result"
                                        and c.get("is_error")):
                                    errors += 1
                        continue
                    if dtype != "assistant":
                        continue
                    msg = d.get("message")
                    if not isinstance(msg, dict):
                        continue
                    usage = msg.get("usage")
                    if isinstance(usage, dict):
                        input_tokens += _safe_int(usage.get("input_tokens"))
                        output_tokens += _safe_int(usage.get("output_tokens"))
                        cache_read += _safe_int(usage.get("cache_read_input_tokens"))
                        cache_creation += _safe_int(usage.get("cache_creation_input_tokens"))
                    content = msg.get("content")
                    last_text = None  # transient only; never accumulated, never returned
                    if isinstance(content, list):
                        for c in content:
                            if not isinstance(c, dict):
                                continue
                            ctype = c.get("type")
                            if ctype == "tool_use":
                                tool_calls += 1
                            elif ctype == "text":
                                t = c.get("text")
                                if isinstance(t, str):
                                    last_text = t
                    if msg.get("stop_reason") != "tool_use" and last_text is not None:
                        if not last_text.rstrip().endswith(_CANARY_LINE):
                            canary_drops += 1
                    last_text = None  # drop the reference before the next line is parsed
                except Exception:  # noqa: BLE001 -- privacy: a raise here could leak line content
                    continue
    except OSError:
        return None
    if first_ts is None:
        return None  # zero timestamped lines: not a counted session
    return [
        path.stem, path.parent.name, first_ts, last_ts,
        _duration_seconds(first_ts, last_ts),
        input_tokens, output_tokens, cache_read, cache_creation,
        tool_calls, errors, compactions, canary_drops,
    ]


def _duration_seconds(first_ts: str, last_ts: str) -> int:
    """ISO8601 -> whole-second duration. Returns 0 on anything unparsable (never raises) --
    a malformed timestamp pair yields a 0-duration row, not a crash."""
    try:
        a = _dt.datetime.fromisoformat(str(first_ts).replace("Z", "+00:00"))
        b = _dt.datetime.fromisoformat(str(last_ts).replace("Z", "+00:00"))
    except (ValueError, AttributeError, TypeError):
        return 0
    return max(0, int((b - a).total_seconds()))


def read_sessions(root: Path | None = None):
    """One row per `*.jsonl` session file under `root` (default `config.sessions_dir()`, one
    subdirectory per project-cwd slug). Skip-safe on a missing root; each file is parsed
    independently (one bad file never drops a sibling's row)."""
    d = root or config.sessions_dir()
    if not d.exists():
        return SESSIONS_COLUMNS, []
    rows = []
    for proj_dir in sorted(p for p in d.iterdir() if p.is_dir()):
        for f in sorted(proj_dir.glob("*.jsonl")):
            row = _parse_session_file(f)
            if row is not None:
                rows.append(row)
    rows.sort(key=lambda r: (r[2] or "", r[0]))  # deterministic: by first_ts, then session_id
    return SESSIONS_COLUMNS, rows


# ---- secret-guard audit log (SPEC-135, counts only) -------------------------------------------

# Column names/order come from `schemas.SAFETY_SCHEMA` (single source of truth, see above).
SAFETY_COLUMNS = schemas.column_names(schemas.SAFETY_SCHEMA)

# Matches ONLY the leading 4-5 bracketed groups of a secret-guard log line
# (`[ts] [STATUS] [session] [tool] [RULE]? message...`, confirmed live shape). The free-text
# `message...` remainder (confirmed during design-time probing to sometimes carry a real file
# path, e.g. a redirected-secret destination) is deliberately OUTSIDE any capture group -- it is
# matched by nothing, so it can never end up in a row.
_SAFETY_LINE_RE = re.compile(
    r"^\[(?P<ts>[^\]]+)\]\s*\[(?P<status>[^\]]+)\]\s*\[(?P<session>[^\]]*)\]\s*\[(?P<tool>[^\]]*)\]"
    r"(?:\s*\[(?P<rule>[A-Za-z]\d+[a-z]?)\])?"
)


def read_safety(log_path: Path | None = None):
    """One row per secret-guard audit-log line matching the bracket-prefix shape above:
    `(ts, status, session, tool, rule)`. `rule` is NULL when the line carries none (e.g. a
    `BYPASS` line). Skip-safe on a missing log; a non-matching line is skipped, never raises."""
    p = log_path or config.secret_guard_log_path()
    if not p.exists():
        return SAFETY_COLUMNS, []
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return SAFETY_COLUMNS, []
    rows = []
    for line in text.splitlines():
        m = _SAFETY_LINE_RE.match(line)
        if not m:
            continue
        rows.append([
            m.group("ts"), m.group("status"),
            m.group("session") or None, m.group("tool") or None, m.group("rule"),
        ])
    rows.sort(key=lambda r: (r[0], r[1]))  # deterministic: by ts, then status
    return SAFETY_COLUMNS, rows


# ---- memory-verify sweep (SPEC-136) --------------------------------------------------------

# Column names/order come from `schemas.MEMORY_SCHEMA` (single source of truth, see above).
MEMORY_COLUMNS = schemas.column_names(schemas.MEMORY_SCHEMA)


def read_memories(repo_dir: Path | None = None, projects_root: Path | None = None):
    """One row per memory FILE (note or MEMORY.md index) across every store
    `memory_lens.scan()` walks: `(store, slug, written, last_verified, dead_ref_count)`.
    `last_verified` is THIS call's own timestamp -- the lens has no persisted cross-run state,
    matching every table's delete-and-rematerialize contract. The compact aggregate here is a
    DIFFERENT consumer of the same scan than `cli.memory_sweep`'s rich per-reference report;
    see `memory_lens.py` module docstring."""
    units = memory_lens.scan(repo_dir, projects_root)
    now = _dt.datetime.now(tz=_dt.timezone.utc).isoformat()
    rows = [[u.store, u.slug, u.written, now, u.dead_ref_count] for u in units]
    return MEMORY_COLUMNS, rows
