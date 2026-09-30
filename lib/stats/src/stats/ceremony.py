"""Ceremony lens: gate work and subagent dispatches versus progress and catches.

A pure projection over rows the lens already holds: `kit_gates` (with its GATE timestamp),
`git_lines`, `subagent_runs`, `subagent_scan` and `ledger_lines`. `summarize()` takes plain
dicts and returns one summary dict; nothing here opens a file, a database or git. `from_lens()`
is the one entry that fetches rows, through `materialize` (the single data path), and calls
`summarize()`. `render_text()` turns a summary into markdown tables for the CLI.

Two rules run through every number:

- Unknown stays unknown. A value nobody recorded is `None` in the summary and `?` in the text,
  never 0. Catches count only rows that carry an OUTCOME bracket.
- The ceremony share is a share of gate RECORDS, never of tokens or time.
"""

from __future__ import annotations

import datetime as _dt
import fnmatch
import re
from collections import Counter, defaultdict

DEFAULT_WINDOW_DAYS = 14

_UTC = _dt.timezone.utc
_TASKS_RE = re.compile(r"\btasks=(\d+)")
_SQUASH_RE = re.compile(r"\(#\d+\)\s*$")

_GATES_SQL = ("SELECT rid, gate, outcome, caught, reason, start_ts, end_ts, ts FROM kit_gates")
_GIT_SQL = "SELECT sha, ts, subject, added, deleted, binary_files FROM git_lines"
_DISPATCH_SQL = ("SELECT rid, session, agent_id, agent_type, model, first_ts, last_ts, input_tokens, "
                 "output_tokens, cache_read_tokens, cache_creation_tokens, rid_source FROM subagent_runs")
_SCAN_SQL = "SELECT files_seen, files_read, skipped_files, earliest FROM subagent_scan"
_LEDGER_SQL = "SELECT rid, starts, tokens, gates FROM ledger_lines"


def parse_ts(s) -> _dt.datetime | None:
    """ISO-8601 to an aware datetime (naive input is taken as UTC); None when unparseable."""
    if not s or not isinstance(s, str):
        return None
    t = s.strip()
    if t.endswith(("Z", "z")):
        t = t[:-1] + "+00:00"
    try:
        d = _dt.datetime.fromisoformat(t)
    except ValueError:
        return None
    return d if d.tzinfo else d.replace(tzinfo=_UTC)


def iso(d: _dt.datetime | None) -> str | None:
    return d.astimezone(_UTC).strftime("%Y-%m-%dT%H:%M:%SZ") if d else None


def is_excluded(rid, patterns) -> bool:
    return any(fnmatch.fnmatchcase(rid or "", p) for p in patterns)


def resolve_window(gates, days=DEFAULT_WINDOW_DAYS, frm=None, to=None, exclude=()):
    """`(start, end)`. Default: the last `days` ending at the latest GATE timestamp in the
    ledger (not wall clock, so a fixed ledger gives a fixed answer). Explicit bounds win.
    `gates` is any iterable of `(rid, ts)` pairs."""
    latest = max((t for rid, ts in gates if not is_excluded(rid, exclude)
                  for t in [parse_ts(ts)] if t), default=None)
    end = to or latest
    start = frm or (end - _dt.timedelta(days=days) if end else None)
    return start, end


def commit_ts(sha: str) -> _dt.datetime | None:
    """Committer date of `sha` in the lens's git repo (`--since-sha`); None when unresolvable."""
    import subprocess

    from . import config

    try:
        out = subprocess.run(
            ["git", "-C", str(config.git_repo_dir()), "show", "-s", "--format=%cI", f"{sha}^{{commit}}"],
            capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    return parse_ts(out.stdout.strip()) if out.returncode == 0 else None


def rows_to_dicts(cols, rows):
    return [dict(zip(cols, r)) for r in rows]


def _in_window(t, start, end) -> bool:
    return t is not None and (start is None or t >= start) and (end is None or t <= end)


def _monday(t: _dt.datetime) -> str:
    d = t.astimezone(_UTC).date()
    return (d - _dt.timedelta(days=d.weekday())).isoformat()


def _share(n, d):
    return n / d if d else None


def _sum_tokens(ds):
    return {"input": sum(d["input_tokens"] or 0 for d in ds),
            "output": sum(d["output_tokens"] or 0 for d in ds),
            "cache_read": sum(d["cache_read_tokens"] or 0 for d in ds),
            "cache_creation": sum(d["cache_creation_tokens"] or 0 for d in ds)}


def _net(tok):
    """Net tokens: input + output + cache-creation. Cache-read is reported apart because it
    dwarfs the rest (about 93 percent in the live corpus) and misleads as a headline."""
    return tok["input"] + tok["output"] + tok["cache_creation"] if tok else None


def _cache_read(tok):
    return tok["cache_read"] if tok else None


def summarize(gates, git, dispatches, scan, ledger, start, end, *,
              exclude=(), progress_phases=(), repo=None):
    """Numbers for one window. Every argument is a list of dicts named like the lens columns.
    Gate names are lowercased and trimmed before any match or grouping, so `Ship` and `ship`
    are one gate. Rows of an excluded rid never enter a total."""
    progress_phases = {p.strip().lower() for p in progress_phases}
    rows, no_ts = [], 0
    for r in gates:
        if is_excluded(r["rid"], exclude):
            continue
        t = parse_ts(r["ts"])
        if t is None:
            no_ts += 1
            continue
        if _in_window(t, start, end):
            rows.append({**r, "gate": (r["gate"] or "").strip().lower(),
                         "outcome": (r["outcome"] or "").strip().lower(), "t": t})
    active = [r for r in rows if r["outcome"] in ("ran", "override")]
    ceremony = [r for r in active if r["gate"] not in progress_phases]
    caught_true = sum(1 for r in active if r["caught"] is True)
    known = sum(1 for r in active if r["caught"] is not None)

    weeks = defaultdict(lambda: [0, 0])
    for r in active:
        w = weeks[_monday(r["t"])]
        w[1] += 1
        w[0] += r["gate"] not in progress_phases
    weekly = [{"week": k, "ceremony": v[0], "total": v[1], "share": _share(v[0], v[1])}
              for k, v in sorted(weeks.items())]

    commits = [c for c in git if _in_window(parse_ts(c["ts"]), start, end)]
    prs = [c for c in commits if _SQUASH_RE.search(c["subject"] or "")]
    progress = ({"lines": sum((c["added"] or 0) + (c["deleted"] or 0) for c in prs),
                 "prs": len(prs), "binary_files": sum(c["binary_files"] or 0 for c in prs),
                 "repo": repo} if git else None)

    disp, disp_no_ts = [], 0
    for d in dispatches:
        if d["rid"] and is_excluded(d["rid"], exclude):
            continue
        t = parse_ts(d["first_ts"])
        if t is None:
            disp_no_ts += 1
        elif _in_window(t, start, end):
            disp.append(d)
    # transcripts are pruned: a window that starts before the earliest one on disk cannot be
    # measured, so every dispatch and token cell is unknown, never a partial count
    earliest = parse_ts(scan[0]["earliest"]) if scan and scan[0]["earliest"] else None
    pruned = earliest is not None and start is not None and start < earliest
    if pruned:
        disp, disp_no_ts = [], None
    attributed = [d for d in disp if d["rid"]]
    tokens = _sum_tokens(attributed) if attributed else None

    by_rid_rows, by_rid_disp = defaultdict(list), defaultdict(list)
    for r in rows:
        by_rid_rows[r["rid"]].append(r)
    for d in attributed:
        by_rid_disp[d["rid"]].append(d)
    runs = []
    for rid in sorted(set(by_rid_rows) | set(by_rid_disp)):
        rr = by_rid_rows.get(rid, [])
        act = [r for r in rr if r["outcome"] in ("ran", "override")]
        cer = [r for r in act if r["gate"] not in progress_phases]
        k = sum(1 for r in act if r["caught"] is not None)
        builds = sorted((r for r in rr if r["gate"] == "build" and r["outcome"] == "ran"),
                        key=lambda r: r["t"])
        m = _TASKS_RE.search(builds[-1]["reason"] or "") if builds else None
        tasks = int(m.group(1)) if m and int(m.group(1)) > 0 else None
        ds = by_rid_disp.get(rid, [])
        tok = _sum_tokens(ds) if ds else None
        mine = [c for c in prs if rid.lower() in (c["subject"] or "").lower()]
        runs.append({
            "rid": rid, "ceremony": len(cer), "records": len(act),
            "override": sum(1 for r in act if r["outcome"] == "override"),
            "skipped": sum(1 for r in rr if r["outcome"] == "skipped"),
            "share": _share(len(cer), len(act)),
            "catches": sum(1 for r in act if r["caught"] is True) if k else None, "known": k,
            "lines": sum((c["added"] or 0) + (c["deleted"] or 0) for c in mine) if mine else None,
            "prs": len(mine) if mine else None,
            "dispatches": len(ds) if ds else None,
            "by_type": dict(sorted(Counter(d["agent_type"] for d in ds).items())) if ds else None,
            "tokens": tok, "tokens_net": _net(tok), "tokens_cache_read": _cache_read(tok),
            "tasks": tasks,
            "dispatches_per_task": len(ds) / tasks if ds and tasks else None,
            "tokens_per_task": _net(tok) / tasks if tok and tasks else None,
        })

    excluded = [{"rid": r["rid"], "starts": r["starts"], "tokens": r["tokens"]}
                for r in ledger if is_excluded(r["rid"], exclude)]
    suspect = sorted(r["rid"] for r in ledger
                     if not is_excluded(r["rid"], exclude) and r["starts"] > 0 and r["gates"] == 0)
    sc = scan[0] if scan else None
    return {
        "window": {"start": iso(start), "end": iso(end)},
        "records": {
            "ran": sum(1 for r in rows if r["outcome"] == "ran"),
            "override": sum(1 for r in rows if r["outcome"] == "override"),
            "skipped": sum(1 for r in rows if r["outcome"] == "skipped"),
            "active": len(active), "ceremony": len(ceremony),
            "ceremony_ran": sum(1 for r in ceremony if r["outcome"] == "ran"),
            "ceremony_override": sum(1 for r in ceremony if r["outcome"] == "override"),
            "share": _share(len(ceremony), len(active)), "no_ts": no_ts,
            "by_gate": dict(sorted(Counter(r["gate"] for r in active).items())),
        },
        "catches": {"caught": caught_true, "known": known,
                    "value": caught_true if known else None},
        "progress": progress, "weekly": weekly, "runs": runs,
        "dispatch": {
            "count": None if pruned else len(disp), "no_ts": disp_no_ts,
            "by_type": dict(sorted(Counter(d["agent_type"] for d in disp).items())),
            "rid_source": {s: None if pruned else sum(1 for d in disp if d["rid_source"] == s)
                           for s in ("tag", "window", "ambiguous", "none")},
            "attributed": None if pruned else len(attributed), "pruned": pruned,
            "tokens": tokens, "tokens_net": _net(tokens),
            "tokens_cache_read": _cache_read(tokens),
        },
        "transcripts": ({"files_seen": sc["files_seen"], "files_read": sc["files_read"],
                         "skipped_files": sc["skipped_files"], "earliest": sc["earliest"]}
                        if sc else None),
        "excluded": excluded, "suspect_fixtures": suspect,
        "phases_progress": sorted(progress_phases),
    }


def from_lens(days=DEFAULT_WINDOW_DAYS, frm=None, to=None, *, context=True):
    """Fetch rows through `materialize` on ONE lens build and summarize them. `context=False`
    fetches only the gate rows (the anomaly's cheap first pass: no transcript read)."""
    from . import config, materialize

    sqls = [_GATES_SQL] + ([_GIT_SQL, _DISPATCH_SQL, _SCAN_SQL, _LEDGER_SQL] if context else [])
    materialize.set_window(frm, to, days)
    try:
        res = materialize.query_many(sqls)
    finally:
        materialize.set_window(None, None, None)
    d = [rows_to_dicts(c, r) for c, r in res]
    gates = d[0]
    exclude = config.exclude_rids()
    start, end = resolve_window([(g["rid"], g["ts"]) for g in gates], days, frm, to, exclude)
    git, disp, scan, ledger = d[1:] if context else ([], [], [], [])
    return summarize(gates, git, disp, scan, ledger, start, end, exclude=exclude,
                     progress_phases=config.ceremony_progress_phases(),
                     repo=str(config.git_repo_dir()))


# ---- text rendering ------------------------------------------------------------------

def _q(v, fmt="{}"):
    return "?" if v is None else fmt.format(v)


def _table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return out


def _types(by_type):
    return "?" if not by_type else ", ".join(f"{k}={v}" for k, v in by_type.items())


def render_text(s) -> str:
    rec, cat, w = s["records"], s["catches"], s["window"]
    prog, dsp, tr = s["progress"], s["dispatch"], s["transcripts"]
    out = [f"ceremony lens: window {_q(w['start'])} .. {_q(w['end'])}", ""]
    out.append(f"records: ran={rec['ran']} override={rec['override']} skipped={rec['skipped']} "
               "(skipped never enters the share)")
    out.append(f"ceremony records (ran+override): {rec['ceremony']} of {rec['active']} gate records, "
               f"ran={rec['ceremony_ran']} override={rec['ceremony_override']}; "
               f"share={_q(rec['share'], '{:.2f}')} (a share of gate records, never of tokens or time)")
    out.append("gates (ran+override): " + (", ".join(f"{k}={v}" for k, v in rec["by_gate"].items()) or "none"))
    out.append("catches: " + (f"{cat['caught']} ({cat['known']} known)" if cat["known"]
                              else "? (0 known)"))
    out.append(f"no-ts: {rec['no_ts']} gate rows without a parseable timestamp")
    out.append("progress: " + (f"lines={prog['lines']} prs={prog['prs']} binary-files={prog['binary_files']}"
                               f" (git repo {prog['repo']})" if prog else "lines=? prs=? (no git commits read)"))
    out.append("transcripts: " + (f"earliest {_q(tr['earliest'])}, files seen={tr['files_seen']} "
                                  f"read={tr['files_read']} skipped-files={tr['skipped_files']}"
                                  if tr else "?"))
    out.append(f"dispatches: {_q(dsp['count'])} ({_types(dsp['by_type'])}), "
               f"attributed={_q(dsp['attributed'])}, no-ts={_q(dsp['no_ts'])}"
               + (" (window starts before the earliest transcript)" if dsp["pruned"] else ""))
    out.append("join sources: " + " ".join(f"{k}={_q(v)}" for k, v in dsp["rid_source"].items()))
    tok = dsp["tokens"]
    out.append("tokens (attributed dispatches only): " + (
        f"net={dsp['tokens_net']} (in+out+cache-creation) cache-read={tok['cache_read']} "
        f"(total incl. cache-read={dsp['tokens_net'] + tok['cache_read']}) "
        f"in={tok['input']} out={tok['output']} cache-creation={tok['cache_creation']} "
        f"({dsp['attributed']} dispatches)" if tok else "?"))
    out.append("excluded rids: " + ("none" if not s["excluded"] else "; ".join(
        f"{e['rid']} (START {e['starts']}, TOKENS {e['tokens']})" for e in s["excluded"])))
    out.append("suspect fixtures: " + (", ".join(s["suspect_fixtures"]) or "none"))
    out += ["", "share by week", ""]
    out += _table(["week", "ceremony", "gate records", "share"],
                  [[x["week"], x["ceremony"], x["total"], _q(x["share"], "{:.2f}")]
                   for x in s["weekly"]])
    out += ["", "per run", ""]
    out += _table(
        ["rid", "ceremony", "records", "override", "skipped", "share", "catches", "lines", "prs",
         "dispatches", "by type", "net tokens", "dispatches/task", "net tokens/task"],
        [[r["rid"], r["ceremony"], r["records"], r["override"], r["skipped"],
          _q(r["share"], "{:.2f}"),
          f"{r['catches']}/{r['known']}" if r["known"] else "?", _q(r["lines"]), _q(r["prs"]),
          _q(r["dispatches"]), _types(r["by_type"]),
          _q(r["tokens_net"]), _q(r["dispatches_per_task"], "{:.1f}"),
          _q(r["tokens_per_task"], "{:.0f}")] for r in s["runs"]])
    return "\n".join(out)
