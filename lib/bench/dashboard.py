#!/usr/bin/env python3
"""bench dashboard: the control-plane dashboard over ALL recorded data.

Forge-skinned (docs/design/forge-design-guidelines.md is the binding design
guide: coal/sheet/ember tokens, mono-led display, square corners, hairline
grids, one heat-spine moment, reduced-motion respected). Chart rules follow
the dataviz method: single-hue magnitude charts, status palette with glyph
secondary-encoding (never color alone), sequential ember heat grid, one axis
per chart, legends for multi-series only. Sidebar surfaces:

  Fleet         KPI tiles + 30-day charts (runs/day, gate records/day),
                verdict mix per gate, breakdowns (repo, lane), activity heat grid
  Explorer      filterable/segmented index of every rid -> replay commands
  Event stream  time-ordered gate verdict feed (OK / SKIP / OVERRIDE) + reasons
  Tool activity real Claude Code session transcripts: tool calls, MCP servers, models
  Bench / RCA   benchmark KPIs + the failure-fingerprint table
  Alerts        template rules (plain JSON) evaluated at build time

Data sources, honest by construction: run ledgers (logs/runs/*.log) and bench
rows (runs/*.jsonl) are facts; transcripts contribute COUNTS ONLY (tool names,
models, timing; never message content). Design: docs/dashboard-design.md.
Ownership split: this generator lives with the product code (dwarves-kit); the
rendered page ships into forge/site/dashboard/observability/ (forge owns UI).

  build [--log-dir D] [--transcripts-dir D] [--max-transcripts N]
        [--alerts alerts.json] [--window-days N] [--out dashboard.html]
"""

import argparse
import datetime as dtm
import html as H
import json
import os
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from report import run_summary  # noqa: E402
from events import expected_plan  # noqa: E402

HERE = Path(__file__).resolve().parent
UTC = dtm.timezone.utc
PHASE_ORDER = ["grill", "think", "design", "design-critique", "ui-design", "spec",
               "validate", "design-record", "test-plan", "build", "review", "docs",
               "ship", "reflect"]

TOKEN_KINDS = ["input_tokens", "output_tokens",
               "cache_creation_input_tokens", "cache_read_input_tokens"]

# USD per million tokens, list price. Transcripts carry no cost field, so spend is
# COMPUTED from these rates; a stale table means wrong money, hence the visible
# provenance note on the page. Cache read = 0.1x input, 5-minute cache write = 1.25x.
PRICES = {
    "claude-fable-5": (10.0, 50.0),
    "claude-mythos-5": (10.0, 50.0),
    "claude-opus-5": (5.0, 25.0),
    "claude-opus-4-8": (5.0, 25.0),
    "claude-opus-4-7": (5.0, 25.0),
    "claude-opus-4-6": (5.0, 25.0),
    "claude-sonnet-5": (3.0, 15.0),
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-haiku-4-5": (1.0, 5.0),
}
CACHE_READ_MULT = 0.1
CACHE_WRITE_MULT = 1.25


def price_for(model):
    """Longest-prefix match so dated snapshots (claude-opus-5-2026xx) still price."""
    if model in PRICES:
        return PRICES[model]
    hits = [k for k in PRICES if model.startswith(k)]
    if hits:
        return PRICES[max(hits, key=len)]
    return None


def model_cost(model, tok):
    """USD for one model's token counter. Unknown model -> 0.0, surfaced as
    'unpriced' on the page rather than silently guessed."""
    p = price_for(model)
    if not p:
        return 0.0
    inp, out = p
    return (tok.get("input_tokens", 0) * inp
            + tok.get("cache_read_input_tokens", 0) * inp * CACHE_READ_MULT
            + tok.get("cache_creation_input_tokens", 0) * inp * CACHE_WRITE_MULT
            + tok.get("output_tokens", 0) * out) / 1_000_000


def now():
    return dtm.datetime.now(UTC)


# ---- data assembly ----------------------------------------------------------

def collect_runs(log_dir):
    runs_dir = Path(log_dir) / "runs"
    out = []
    plans = {}
    for f in sorted(runs_dir.glob("*.log")):
        r = run_summary(f)
        if not r["t1"]:
            continue
        lane = r["meta"].get("lane")
        conf = None
        if lane:
            if lane not in plans:
                plans[lane] = [p for p, lvl in expected_plan(lane) if "required" in lvl]
            req = plans[lane]
            if req:
                seen = sum(1 for p in req if r["gates"].get(p, ("",))[0] in ("pass", "override"))
                conf = (seen, len(req))
        r["conformance"] = conf
        r["misfire"] = bool(lane and r["meta"].get("classified") and lane != r["meta"]["classified"])
        out.append(r)
    return sorted(out, key=lambda r: r["t1"], reverse=True)


def collect_events(log_dir):
    """Every GATE event across every rid, newest first (stream shows a slice;
    the heat grid and trends consume all of them)."""
    evs = []
    for f in Path(log_dir, "runs").glob("*.log"):
        rid = f.stem
        for line in f.read_text().splitlines():
            parts = [p.strip() for p in line.split(" | ", 3)]
            if len(parts) == 4 and parts[1] == "GATE":
                try:
                    ts = dtm.datetime.fromisoformat(parts[0].replace("Z", "+00:00"))
                except ValueError:
                    continue
                status, _, reason = parts[3].partition(" | ")
                evs.append({"ts": ts, "rid": rid, "phase": parts[2],
                            "status": status.strip(), "reason": reason.strip()})
    evs.sort(key=lambda e: e["ts"], reverse=True)
    return evs


def collect_debt(log_dir):
    """Every | DEBT | line across every rid (ADR-0031 understanding-gate markers)."""
    out = []
    for f in Path(log_dir, "runs").glob("*.log"):
        for line in f.read_text().splitlines():
            parts = [p.strip() for p in line.split(" | ", 2)]
            if len(parts) == 3 and parts[1] == "DEBT":
                try:
                    ts = dtm.datetime.fromisoformat(parts[0].replace("Z", "+00:00"))
                except ValueError:
                    continue
                kv = dict(t.partition("=")[::2] for t in parts[2].split() if "=" in t)
                reason = parts[2].partition("reason=")[2].replace("-", " ").strip()
                out.append({"ts": ts, "rid": f.stem, "significance": kv.get("significance", "?"),
                            "verdict": kv.get("verdict", "?"), "response": kv.get("response", ""),
                            "reason": reason[:400]})
    return sorted(out, key=lambda d: d["ts"])


def debt_metrics(debt):
    """The cognitive-debt score, v1 formula per DECISION-BRIEF-cognitive-debt-score.md:
    100 - 10*high-sig open defers - 4*low-sig open defers - min(20, days since last
    paydown), floored at 0. A paydown = any response=engage line; only defers newer
    than it count as open (engage lines don't name which items they clear, so the
    open-item list ships alongside the number for human judgment)."""
    paydowns = [d for d in debt if d["response"] == "engage"]
    last_pay = paydowns[-1]["ts"] if paydowns else None
    open_defers = [d for d in debt
                   if d["verdict"] == "tap" and d["response"] == "defer"
                   and (last_pay is None or d["ts"] > last_pay)]
    hi = sum(1 for d in open_defers if d["significance"] == "high")
    lo = len(open_defers) - hi
    stale = min(20, (now() - last_pay).days) if last_pay else 20
    score = max(0, 100 - 10 * hi - 4 * lo - stale)
    return {"score": score, "open": open_defers, "open_high": hi, "open_low": lo,
            "staleness_days": (now() - last_pay).days if last_pay else None,
            "last_paydown": last_pay.date().isoformat() if last_pay else None,
            "total_lines": len(debt),
            "verdicts": dict(Counter(d["verdict"] for d in debt)),
            "paydowns": len(paydowns)}


def collect_sessions(tdir, max_files=25):
    """COUNTS ONLY from Claude Code transcripts: tool names, models, timing.
    Message content is never read into the output (privacy rule in the design
    doc); a transcript contributes only aggregates."""
    root = Path(tdir).expanduser()
    if not root.is_dir():
        return []
    files = sorted(root.glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    sessions = []
    for f in files[:max_files]:
        tools, models, tiers, versions = Counter(), Counter(), Counter(), Counter()
        tok = Counter()          # token totals by kind, whole session
        per_model = {}           # model -> token Counter, for per-model costing
        side = Counter()         # main-thread vs subagent (isSidechain) message split
        branches = Counter()
        t0 = t1 = None
        try:
            with f.open() as fh:
                for line in fh:
                    if len(line) > 400_000:
                        continue
                    try:
                        d = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    ts = d.get("timestamp")
                    if isinstance(ts, str):
                        t0, t1 = t0 or ts, ts
                    if d.get("gitBranch"):
                        branches[d["gitBranch"]] += 1
                    msg = d.get("message") or {}
                    if not isinstance(msg, dict):
                        continue
                    if msg.get("model"):
                        models[msg["model"]] += 1
                    for blk in msg.get("content") or []:
                        if isinstance(blk, dict) and blk.get("type") == "tool_use":
                            tools[blk.get("name", "?")] += 1
                    u = msg.get("usage") or {}
                    if not u:
                        continue
                    side["subagent" if d.get("isSidechain") else "main"] += 1
                    if u.get("service_tier"):
                        tiers[u["service_tier"]] += 1
                    if d.get("version"):
                        versions[d["version"]] += 1
                    m = msg.get("model") or "unknown"
                    pm = per_model.setdefault(m, Counter())
                    for k in TOKEN_KINDS:
                        v = u.get(k)
                        if isinstance(v, int):
                            tok[k] += v
                            pm[k] += v
        except OSError:
            continue
        if not tools and not tok:
            continue
        mins = 0
        try:
            if t0 and t1:
                mins = (dtm.datetime.fromisoformat(t1.replace("Z", "+00:00"))
                        - dtm.datetime.fromisoformat(t0.replace("Z", "+00:00"))).total_seconds() / 60
        except ValueError:
            pass
        cost = sum(model_cost(m, c) for m, c in per_model.items())
        sessions.append({
            "session": f.stem[:8], "project": f.parent.name.split("-")[-1],
            "models": models, "tools": tools, "mins": round(mins),
            "day": (t1 or "")[:10], "tok": tok, "per_model": per_model, "cost": cost,
            "tiers": tiers, "versions": versions, "side": side, "branches": branches,
        })
    return sessions


def collect_bench(runs_glob="runs/*.jsonl"):
    rows = []
    for f in sorted(HERE.glob(runs_glob)):
        for line in f.read_text().splitlines():
            if line.strip():
                rows.append(json.loads(line))
    return rows


# ---- metrics + alerts -------------------------------------------------------

def fleet_metrics(runs, events, window_days=30):
    cut = now() - dtm.timedelta(days=window_days)
    w = [r for r in runs if r["t1"] >= cut]
    ev_w = [e for e in events if e["ts"] >= cut]
    gates = [s for r in w for s, _ in r["gates"].values()]
    n_g = len(gates) or 1
    confs = [r["conformance"] for r in w if r["conformance"]]
    m = {
        "window_days": window_days,
        "runs": len(w),
        "repos": len({r["meta"].get("repo", "?") for r in w if r["meta"].get("repo")}),
        "gate_records": len(gates),
        "ran": gates.count("pass"), "skipped": gates.count("skip"),
        "overridden": gates.count("override"),
        "override_rate": round(gates.count("override") / n_g, 3),
        "skip_rate": round(gates.count("skip") / n_g, 3),
        "misfires": sum(1 for r in w if r["misfire"]),
        "misfire_rate": round(sum(1 for r in w if r["misfire"]) / (len(w) or 1), 3),
        "full_conformance": sum(1 for c in confs if c[0] == c[1]),
        "conf_known": len(confs),
    }
    days = [(now() - dtm.timedelta(days=i)).date() for i in range(window_days - 1, -1, -1)]
    per_day = Counter(r["t1"].date() for r in w)
    ev_day = Counter(e["ts"].date() for e in ev_w)
    m["days"] = days
    m["trend_runs"] = [per_day.get(d, 0) for d in days]
    m["trend_gates"] = [ev_day.get(d, 0) for d in days]
    # verdict mix per phase (status counts, ordered by the canonical plan order)
    mix = {}
    for e in ev_w:
        mix.setdefault(e["phase"], Counter())[e["status"]] += 1
    phases = [p for p in PHASE_ORDER if p in mix] + sorted(set(mix) - set(PHASE_ORDER))
    m["phase_mix"] = [(p, mix[p].get("ran", 0), mix[p].get("skipped", 0),
                       mix[p].get("override", 0)) for p in phases]
    m["repo_counts"] = Counter(r["meta"].get("repo") for r in w if r["meta"].get("repo")).most_common(8)
    lane_min = Counter()
    for r in w:
        if r["meta"].get("lane") and r["t0"]:
            lane_min[r["meta"]["lane"]] += (r["t1"] - r["t0"]).total_seconds() / 60
    m["lane_minutes"] = [(k, round(v)) for k, v in lane_min.most_common(6)]
    heat = [[0] * 24 for _ in range(7)]
    for e in ev_w:
        lt = e["ts"].astimezone()
        heat[lt.weekday()][lt.hour] += 1
    m["heat"] = heat
    return m


def money_metrics(sessions, window_days=30, monthly_budget=None):
    """Spend + token plane from transcript usage. Costs are computed from PRICES,
    never read from a cost field (transcripts carry none)."""
    tok = Counter()
    by_model = {}
    by_project = {}
    by_day = {}
    side = Counter()
    tiers, versions = Counter(), Counter()
    unpriced = set()
    for s in sessions:
        # A session with no billed messages (tool-only, or a transcript predating
        # usage records) still belongs in the counts; treat its money fields as empty
        # rather than dropping the session or crashing on a missing key.
        tok.update(s.get("tok") or {})
        side.update(s.get("side") or {})
        tiers.update(s.get("tiers") or {})
        versions.update(s.get("versions") or {})
        for m, c in (s.get("per_model") or {}).items():
            e = by_model.setdefault(m, {"tok": Counter(), "cost": 0.0, "sessions": 0})
            e["tok"].update(c)
            e["cost"] += model_cost(m, c)
            e["sessions"] += 1
            if not price_for(m):
                unpriced.add(m)
        p = by_project.setdefault(s["project"], {"cost": 0.0, "sessions": 0, "tok": Counter()})
        p["cost"] += s.get("cost", 0.0)
        p["sessions"] += 1
        p["tok"].update(s.get("tok") or {})
        if s.get("day"):
            by_day[s["day"]] = by_day.get(s["day"], 0.0) + s.get("cost", 0.0)
    total = sum(s.get("cost", 0.0) for s in sessions)
    reads = tok["cache_read_input_tokens"]
    writes = tok["cache_creation_input_tokens"]
    fresh = tok["input_tokens"]
    prompt_total = reads + writes + fresh
    days = sorted(by_day)
    m = {
        "total_cost": total,
        "tok": tok,
        "prompt_total": prompt_total,
        "cache_hit": (reads / prompt_total) if prompt_total else 0.0,
        "read_ratio": (reads / fresh) if fresh else 0.0,
        "cost_per_session": (total / len(sessions)) if sessions else 0.0,
        "by_model": sorted(by_model.items(), key=lambda kv: -kv[1]["cost"]),
        "by_project": sorted(by_project.items(), key=lambda kv: -kv[1]["cost"])[:10],
        "trend_days": days,
        "trend_cost": [by_day[d] for d in days],
        "side": side,
        "tiers": tiers,
        "versions": versions,
        "unpriced": sorted(unpriced),
        "sessions": len(sessions),
        "window_days": window_days,
    }
    # Burn rate + projection. Only meaningful with at least two distinct days of
    # data: extrapolating a single (possibly partial, possibly atypical) day x30
    # produces a confident-looking fiction, so below that the projection is None
    # and the page says so instead of printing a number.
    m["span_days"] = len(days)
    m["date_range"] = (days[0], days[-1]) if days else None
    if len(days) >= 2:
        m["daily_burn"] = total / len(days)
        m["projected_30d"] = m["daily_burn"] * 30
    else:
        m["daily_burn"] = None
        m["projected_30d"] = None
    m["budget"] = monthly_budget
    m["budget_used"] = (m["projected_30d"] / monthly_budget
                        if monthly_budget and m["projected_30d"] else None)
    return m


DEFAULT_ALERTS = [
    {"id": "override-rate", "metric": "override_rate", "op": ">", "threshold": 0.15,
     "severity": "warn", "note": "gates being overridden too often; check reasons in the stream"},
    {"id": "misfire-rate", "metric": "misfire_rate", "op": ">", "threshold": 0.2,
     "severity": "warn", "note": "lane chosen disagrees with classifier too often (feed for keyword fixes)"},
    {"id": "skip-rate", "metric": "skip_rate", "op": ">", "threshold": 0.5,
     "severity": "info", "note": "over half of gate records are skips; lanes may be over-provisioned"},
    {"id": "no-runs", "metric": "runs", "op": "<", "threshold": 1,
     "severity": "info", "note": "no kit runs recorded in the window"},
]


def eval_alerts(metrics, rules):
    ops = {">": lambda a, b: a > b, "<": lambda a, b: a < b, ">=": lambda a, b: a >= b}
    out = []
    for r in rules:
        val = metrics.get(r["metric"])
        firing = val is not None and ops[r["op"]](val, r["threshold"])
        out.append({**r, "value": val, "firing": firing})
    return out


# ---- charts (SVG/HTML, forge tokens, dataviz method) ------------------------

def area_chart(vals, days, title, w=540, h=150):
    """Single-series area chart: one hue (ember), y axis with 3 gridlines,
    x axis first/mid/last date, per-day hover targets with native tooltips.
    Single series, so no legend (the title names it)."""
    if not vals:
        return ""
    left, right, top, bot = 34, 10, 10, 22
    iw, ih = w - left - right, h - top - bot
    mx = max(max(vals), 1)
    step = iw / max(len(vals) - 1, 1)

    def x(i):
        return left + i * step

    def y(v):
        return top + ih - (v / mx) * ih

    pts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(vals))
    area = f"{left},{top + ih} {pts} {x(len(vals) - 1):.1f},{top + ih}"
    grid = ""
    for gv in (0, mx / 2, mx):
        gy = y(gv)
        grid += (f'<line x1="{left}" y1="{gy:.1f}" x2="{w - right}" y2="{gy:.1f}" class="grid"/>'
                 f'<text x="{left - 5}" y="{gy + 3.5:.1f}" class="tick" text-anchor="end">{gv:.0f}</text>')
    xt = ""
    for i in (0, len(days) // 2, len(days) - 1):
        xt += (f'<text x="{x(i):.1f}" y="{h - 6}" class="tick" '
               f'text-anchor="middle">{days[i].strftime("%m-%d")}</text>')
    hover = "".join(
        f'<g><rect x="{x(i) - step / 2:.1f}" y="{top}" width="{step:.1f}" height="{ih}" fill="transparent">'
        f"<title>{days[i]} · {v}</title></rect>"
        f'<circle cx="{x(i):.1f}" cy="{y(v):.1f}" r="2" class="pt"/></g>'
        for i, v in enumerate(vals))
    last = vals[-1]
    return f"""<figure class="chart"><figcaption>{H.escape(title)}</figcaption>
<svg viewBox="0 0 {w} {h}" role="img" aria-label="{H.escape(title)}">
{grid}{xt}
<polygon points="{area}" class="fill"/>
<polyline points="{pts}" class="line"/>
{hover}
<text x="{x(len(vals) - 1) - 4:.1f}" y="{y(last) - 6:.1f}" class="endlbl" text-anchor="end">{last}</text>
</svg></figure>"""


def verdict_mix(phase_mix):
    """Horizontal stacked status bars per gate phase. Status palette with glyph
    secondary encoding (never color alone); 2px gaps between segments."""
    if not phase_mix:
        return ""
    mx = max(r + s + o for _, r, s, o in phase_mix) or 1
    rows = ""
    for p, r, s, o in phase_mix:
        tot = r + s + o
        segs = ""
        for cls, v, glyph, name in (("ok", r, "●", "ran"), ("skip", s, "○", "skipped"),
                                    ("ovr", o, "⚑", "override")):
            if v:
                segs += (f'<span class="seg {cls}" style="width:{100 * v / mx:.1f}%">'
                         f"<i>{glyph} {name} {v}</i></span>")
        rows += (f'<div class="mixrow"><span class="lbl">{H.escape(p)}</span>'
                 f'<span class="mixtrack">{segs}</span>'
                 f'<span class="val">{tot}</span></div>')
    legend = ('<div class="legend"><span><b class="sw ok"></b>● ran</span>'
              '<span><b class="sw skip"></b>○ skipped</span>'
              '<span><b class="sw ovr"></b>⚑ override</span></div>')
    return f'<figure class="chart"><figcaption>Verdict mix per gate</figcaption>{legend}{rows}</figure>'


def hbars(items, title, unit=""):
    """Single-measure horizontal bars; identity on the axis label, one hue."""
    if not items:
        return ""
    mx = max(v for _, v in items) or 1
    rows = "".join(
        f'<div class="mixrow"><span class="lbl">{H.escape(str(k))}</span>'
        f'<span class="mixtrack"><span class="seg one" style="width:{100 * v / mx:.1f}%">'
        f"<i>{k}: {v}{unit}</i></span></span>"
        f'<span class="val">{v}{unit}</span></div>'
        for k, v in items)
    return f'<figure class="chart"><figcaption>{H.escape(title)}</figcaption>{rows}</figure>'


def heat_grid(heat):
    """Day x hour activity: sequential single hue (ember, 5 alpha steps,
    light -> dark = low -> high), native tooltip per cell."""
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    mx = max((v for row in heat for v in row), default=0) or 1
    cells = ""
    for d in range(7):
        cells += f'<span class="hlbl">{days[d]}</span>'
        for h24 in range(24):
            v = heat[d][h24]
            a = 0 if v == 0 else 0.15 + 0.85 * (v / mx)
            cells += (f'<span class="hc" style="background:rgba(200,74,22,{a:.2f})">'
                      f"<i>{days[d]} {h24:02d}:00 · {v} events</i></span>")
    hours = '<span class="hlbl"></span>' + "".join(
        f'<span class="hx">{h:02d}</span>' if h % 6 == 0 else "<span></span>" for h in range(24))
    return (f'<figure class="chart wide"><figcaption>Gate activity · weekday x hour (local)</figcaption>'
            f'<div class="heat">{cells}{hours}</div></figure>')


# ---- render -----------------------------------------------------------------

STYLE = """<style>
:root{
  --coal:#F2F0EC; --sheet:#FAF9F6; --card:#FFFFFF; --ink:#1C1E24; --iron:#3A3F49;
  --ash:#6E7480; --rule:#D8D4CC; --rule-strong:#B9B4AA; --ember:#C84A16;
  --heat2:#C84A16; --heat3:#F08C1B; --heat4:#FFD75E; --ok:#2E7D4F; --warn:#B07B10;
  --bad:#B3261E; --glow:rgba(200,74,22,.14);
  --mono:ui-monospace,"SF Mono","Cascadia Code","JetBrains Mono",Menlo,Consolas,monospace;
  --sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif}
@media (prefers-color-scheme:dark){:root{
  --coal:#15171C; --sheet:#1B1E24; --card:#1F232B; --ink:#ECEAE4; --iron:#B8BDC7;
  --ash:#8A8F99; --rule:#2B2F37; --rule-strong:#3C414B; --ok:#5DBB84; --warn:#D9A441;
  --bad:#E5726B; --glow:rgba(240,140,27,.10)}}
:root[data-theme=dark]{
  --coal:#15171C; --sheet:#1B1E24; --card:#1F232B; --ink:#ECEAE4; --iron:#B8BDC7;
  --ash:#8A8F99; --rule:#2B2F37; --rule-strong:#3C414B; --ok:#5DBB84; --warn:#D9A441;
  --bad:#E5726B; --glow:rgba(240,140,27,.10)}
:root[data-theme=light]{
  --coal:#F2F0EC; --sheet:#FAF9F6; --card:#FFFFFF; --ink:#1C1E24; --iron:#3A3F49;
  --ash:#6E7480; --rule:#D8D4CC; --rule-strong:#B9B4AA; --ok:#2E7D4F; --warn:#B07B10;
  --bad:#B3261E; --glow:rgba(200,74,22,.14)}
*{box-sizing:border-box;margin:0}
body{background:var(--coal);color:var(--ink);font-family:var(--sans);line-height:1.5;
-webkit-font-smoothing:antialiased}
a{color:inherit}
:focus-visible{outline:2px solid var(--ember);outline-offset:2px}
.banner{background:var(--sheet);border-bottom:1px solid var(--rule);font-family:var(--mono);
font-size:11.5px;letter-spacing:.12em;text-transform:uppercase;color:var(--ash);
text-align:center;padding:6px 12px}
.banner b{color:var(--ember)}
.spine{height:6px;background:linear-gradient(90deg,#8A8E96,var(--heat2),var(--heat3),var(--heat4))}
.shell{display:grid;grid-template-columns:212px 1fr;min-height:100vh}
@media(max-width:760px){.shell{grid-template-columns:1fr}}
aside{border-right:1px solid var(--rule);padding:20px 0;display:flex;flex-direction:column;gap:2px}
@media(max-width:760px){aside{border-right:none;border-bottom:1px solid var(--rule);
flex-direction:row;flex-wrap:wrap;padding:10px 12px}}
.wordmark{font-family:var(--mono);font-weight:700;font-size:15px;letter-spacing:.26em;
text-decoration:none;padding:0 20px 16px;display:block}
.wordmark b{background:linear-gradient(90deg,var(--heat2),var(--heat3));
-webkit-background-clip:text;background-clip:text;color:transparent}
.grp{font-family:var(--mono);font-size:10.5px;letter-spacing:.18em;text-transform:uppercase;
color:var(--ash);padding:12px 20px 4px}
.navbtn{display:block;width:100%;text-align:left;background:none;border:none;
border-left:2px solid transparent;font-family:var(--mono);font-size:12.5px;
letter-spacing:.08em;text-transform:uppercase;color:var(--iron);padding:9px 20px;cursor:pointer}
.navbtn:hover{color:var(--ember)}
.navbtn[aria-current]{color:var(--ink);border-left-color:var(--ember);background:var(--glow)}
@media(max-width:760px){.navbtn{width:auto;border-left:none;border-bottom:2px solid transparent;
padding:8px 10px}.navbtn[aria-current]{border-bottom-color:var(--ember)}.grp{display:none}}
main{padding:26px 28px 60px;max-width:1080px;min-width:0}
h1{font-family:var(--mono);font-weight:700;text-transform:uppercase;font-size:clamp(20px,3vw,28px);
line-height:1.08;margin:0 0 6px}
.eyebrow{font-family:var(--mono);font-size:11.5px;letter-spacing:.16em;text-transform:uppercase;
color:var(--ember);margin-bottom:4px}
.meta{color:var(--ash);font-size:13.5px;max-width:58ch;margin-bottom:18px}
section{display:none}section.on{display:block}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(158px,1fr));gap:1px;
background:var(--rule);border:1px solid var(--rule);margin:16px 0}
.tile{background:var(--card);padding:12px 14px}
.tile b{display:block;font-family:var(--mono);font-size:22px;font-variant-numeric:tabular-nums}
.tile span{font-family:var(--mono);font-size:10.5px;letter-spacing:.1em;text-transform:uppercase;
color:var(--ash)}
.charts{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:1px;
background:var(--rule);border:1px solid var(--rule);margin:16px 0}
.chart{background:var(--card);padding:14px 16px;min-width:0}
.chart.wide{grid-column:1/-1}
.chart figcaption{font-family:var(--mono);font-size:11px;letter-spacing:.14em;
text-transform:uppercase;color:var(--ash);margin-bottom:8px}
.chart svg{width:100%;height:auto;display:block}
svg .grid{stroke:var(--rule);stroke-width:1}
svg .tick{fill:var(--ash);font-family:var(--mono);font-size:9.5px}
svg .line{fill:none;stroke:var(--ember);stroke-width:2}
svg .fill{fill:var(--ember);opacity:.13}
svg .pt{fill:var(--ember)}
svg .endlbl{fill:var(--ink);font-family:var(--mono);font-size:10.5px;font-weight:700}
.legend{display:flex;gap:14px;font-family:var(--mono);font-size:11px;color:var(--iron);
margin-bottom:8px}
.legend .sw{display:inline-block;width:10px;height:10px;margin-right:5px;vertical-align:-1px}
.sw.ok,.seg.ok{background:var(--ok)}
.sw.skip,.seg.skip{background:var(--ash);opacity:.55}
.sw.ovr,.seg.ovr{background:var(--warn)}
.seg.one{background:var(--ember)}
.seg.over{background:var(--bad)}
.mixrow{display:grid;grid-template-columns:7.5rem 1fr 3.2rem;align-items:center;gap:8px;
padding:2.5px 0;font-family:var(--mono);font-size:11.5px}
.mixrow .lbl{color:var(--iron);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.mixrow .val{color:var(--ash);text-align:right;font-variant-numeric:tabular-nums}
.mixtrack{display:flex;gap:2px;height:12px;background:var(--sheet)}
.seg{display:inline-block;height:100%;position:relative;min-width:2px}
.seg i{display:none}
.seg:hover i{display:block;position:absolute;bottom:16px;left:0;background:var(--card);
border:1px solid var(--rule-strong);padding:2px 8px;font-style:normal;white-space:nowrap;
z-index:5;color:var(--ink)}
.heat{display:grid;grid-template-columns:2.4rem repeat(24,1fr);gap:1px;background:var(--rule);
border:1px solid var(--rule);padding:1px}
.hc{position:relative;aspect-ratio:1.4;background:var(--card);min-width:0}
.hc i{display:none}
.hc:hover i{display:block;position:absolute;bottom:110%;left:0;background:var(--card);
border:1px solid var(--rule-strong);padding:2px 8px;font-style:normal;font-family:var(--mono);
font-size:10.5px;white-space:nowrap;z-index:5;color:var(--ink)}
.hlbl,.hx{font-family:var(--mono);font-size:9.5px;color:var(--ash);background:var(--card);
display:flex;align-items:center;padding-left:4px}
.hx{justify-content:flex-start}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums;margin:10px 0}
th,td{border:1px solid var(--rule);padding:6px 9px;font-size:12.5px;text-align:left;
background:var(--card)}
th{font-family:var(--mono);font-size:10.5px;letter-spacing:.12em;text-transform:uppercase;
color:var(--ash);position:sticky;top:0}
td code,.mono{font-family:var(--mono);font-size:12px}
tr:hover td{background:var(--glow)}
.chip{display:inline-block;font-family:var(--mono);font-size:10.5px;letter-spacing:.06em;
padding:1px 8px;border:1px solid var(--rule-strong)}
.chip.ok{color:var(--ok);border-color:var(--ok)}
.chip.bad{color:var(--bad);border-color:var(--bad)}
.chip.warn{color:var(--warn);border-color:var(--warn)}
.chip.dim{color:var(--ash)}
.seg-bar{display:flex;flex-wrap:wrap;gap:6px;margin:12px 0}
.seg-bar button,#q{font-family:var(--mono);font-size:11.5px;letter-spacing:.06em;
text-transform:uppercase;background:var(--card);color:var(--iron);
border:1px solid var(--rule-strong);padding:5px 12px;cursor:pointer}
.seg-bar button.on{color:var(--ember);border-color:var(--ember)}
#q{min-width:15rem;text-transform:none}
.scroll{max-height:30rem;overflow:auto;border:1px solid var(--rule)}
.scroll table{margin:0;border:none}
.reason{color:var(--ash);font-size:11.5px;max-width:32rem;overflow:hidden;
text-overflow:ellipsis;white-space:nowrap}
.fp{font-family:var(--mono);font-size:11px;color:var(--bad);white-space:pre-wrap}
.footer{margin-top:28px;font-family:var(--mono);font-size:11px;color:var(--ash)}
tr.exrow{cursor:pointer}
tr.detail>td{background:var(--sheet);padding:10px 14px}
.detail-log table{margin:6px 0 0}
body.redacted code,body.redacted .reason,body.redacted td.mono,
body.redacted .detail-log{filter:blur(5px);user-select:none}
select{font-family:var(--mono);font-size:11.5px;background:var(--card);color:var(--ink);
border:1px solid var(--rule-strong);padding:2px 6px}
@media (prefers-reduced-motion:no-preference){.navbtn,.chip{transition:color .15s,border-color .15s}}
</style>"""


def _chip(status):
    cls = {"ran": "ok", "skipped": "dim", "override": "warn"}.get(status, "dim")
    label = {"ran": "● OK", "skipped": "○ SKIP", "override": "⚑ OVERRIDE"}.get(status, status.upper())
    return f'<span class="chip {cls}">{label}</span>'


def collect_config():
    """kit.toml module + status surface for the visual config view. Uses stdlib
    tomllib; degrades to raw-line scan when the file has no parseable sections."""
    root = Path(__file__).resolve().parents[2]
    cfg = root / "kit.toml"
    if not cfg.exists():
        return None
    out = {"path": str(cfg), "modules": {}, "keys": []}
    try:
        import tomllib
        data = tomllib.loads(cfg.read_text())
        out["modules"] = data.get("modules", {})
        for section, body in data.items():
            if section == "modules" or not isinstance(body, dict):
                continue
            for k, v in body.items():
                out["keys"].append({"section": section, "key": k, "value": v})
    except Exception:
        pass
    # status tags live in comments ([impl]/[design]/[reserved]/[consumer])
    tags = Counter()
    for line in cfg.read_text().splitlines():
        for t in ("impl", "design", "reserved", "consumer"):
            if f"[{t}]" in line:
                tags[t] += 1
    out["status_tags"] = dict(tags)
    return out


DEFAULT_TOOL_POLICY = {
    "_doc": "v2 capability->provider policy enforced by hooks/tool-policy-guard.sh "
            "(PreToolUse). Each capability lists interchangeable providers; 'preferred' "
            "names the default rung; rules match tool-name substrings to allow|ask|deny. "
            "The hook reads v2 (capabilities) and legacy v1 (top-level domains) alike.",
    "capabilities": {
        "browser": {
            "label": "Browser drive",
            "preferred": "browser-harness-js",
            "providers": [
                {"id": "browser-harness-js", "label": "browser-harness-js · CDP to running Helium", "match": None, "action": "allow"},
                {"id": "agent-browser", "label": "agent-browser · real Edge profile", "match": None, "action": "allow"},
                {"id": "lightpanda", "label": "Lightpanda · stateless public reads", "match": None, "action": "allow"},
                {"id": "playwright-mcp", "label": "Playwright MCP · scripted replay", "match": "mcp__plugin_playwright_playwright__", "action": "ask",
                 "note": "scripted-replay tooling, not the interactive default"},
                {"id": "browserbase", "label": "Browserbase · cloud browser", "match": "mcp__browserbase", "action": "ask",
                 "note": "never for logged-in accounts"},
            ],
            "rules": [],
        },
        "computer_use": {
            "label": "Computer use",
            "preferred": "macos-ladder",
            "providers": [
                {"id": "macos-ladder", "label": "macOS ladder · CLI/osascript (L0-L2)", "match": None, "action": "allow"},
                {"id": "computer-use-mcp", "label": "computer-use MCP · vision loop (L4)", "match": "mcp__computer-use__", "action": "ask",
                 "note": "confirm the lighter rung is exhausted"},
                {"id": "peekaboo", "label": "Peekaboo · screenshot/AX", "match": "mcp__peekaboo", "action": "ask",
                 "note": "per-project MCP; descoped from global"},
                {"id": "e2b", "label": "e2b · cloud desktop sandbox", "match": "mcp__e2b", "action": "ask",
                 "note": "cloud execution; no local secrets"},
            ],
            "rules": [],
        },
    },
}


RUNTIME_PROBES = [
    {"id": "claude-code", "label": "Claude Code", "path": "~/.claude/projects",
     "glob": "*/*.jsonl", "adapter": "live"},
    {"id": "codex", "label": "Codex CLI", "path": "~/.codex/sessions",
     "glob": "**/rollout-*.json*", "adapter": "detect"},
    {"id": "pi", "label": "pi / oh-my-pi", "path": "~/.pi/agent",
     "glob": "**/*", "adapter": "detect"},
    {"id": "opencode", "label": "OpenCode", "path": "~/.local/share/opencode",
     "glob": "opencode.db", "adapter": "detect"},
    {"id": "gemini", "label": "Gemini CLI", "path": "~/.gemini", "glob": "*", "adapter": "detect"},
    {"id": "cursor", "label": "Cursor", "path": "~/.cursor", "glob": "*", "adapter": "detect"},
]


def collect_runtimes():
    """Detect installed agent runtimes and their local session stores. 'live'
    adapter = normalized into the event protocol today (claude-code);
    'detect' = presence + store stats only, an adapter away from full render."""
    out = []
    for pr in RUNTIME_PROBES:
        root = Path(pr["path"]).expanduser()
        e = {"id": pr["id"], "label": pr["label"], "adapter": pr["adapter"],
             "detected": root.exists(), "files": 0, "latest": None}
        if root.exists():
            try:
                files = [f for f in root.glob(pr["glob"]) if f.is_file()]
                e["files"] = len(files)
                if files:
                    latest = max(f.stat().st_mtime for f in files)
                    e["latest"] = dtm.datetime.fromtimestamp(latest).date().isoformat()
            except OSError:
                pass
        out.append(e)
    return out


def fmt_tok(n):
    for unit, div in (("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= div:
            return f"{n / div:.1f}{unit}"
    return str(n)


def gauge(frac, label):
    """Single-measure horizontal fill for budget/pool headroom."""
    pct = min(100.0, max(0.0, frac * 100))
    cls = "one" if pct < 75 else ("ovr" if pct < 100 else "over")
    return (f'<div class="mixrow"><span class="lbl">{H.escape(label)}</span>'
            f'<span class="mixtrack"><span class="seg {cls}" style="width:{pct:.1f}%">'
            f"<i>{label}: {pct:.0f}%</i></span></span>"
            f'<span class="val">{pct:.0f}%</span></div>')


def money_sections(mm):
    """Cost & tokens + Runtime sections (the money plane)."""
    tok = mm["tok"]
    burn = f"${mm['daily_burn']:,.2f}" if mm["daily_burn"] is not None else "n/a"
    proj = f"${mm['projected_30d']:,.0f}" if mm["projected_30d"] is not None else "n/a"
    tiles = "".join(
        f'<div class="tile"><b>{v}</b><span>{k}</span></div>' for k, v in [
            (f"spend · {mm['sessions']} sampled sessions", f"${mm['total_cost']:,.2f}"),
            ("$ / session", f"${mm['cost_per_session']:,.2f}"),
            ("$ / day (observed)", burn),
            ("30d run-rate", proj),
            ("prompt tokens", fmt_tok(mm["prompt_total"])),
            ("output tokens", fmt_tok(tok["output_tokens"])),
            ("cache-hit rate", f"{mm['cache_hit']:.0%}"),
            ("read:fresh ratio", f"{mm['read_ratio']:,.0f}:1"),
        ])
    rng = (f"{mm['date_range'][0]} to {mm['date_range'][1]}"
           if mm["date_range"] else "no dated sessions")
    scope = (f'<p class="meta">Sample: the {mm["sessions"]} most recent transcripts on this '
             f"host ({rng}, {mm['span_days']} distinct day"
             f"{'s' if mm['span_days'] != 1 else ''}). This is a SAMPLE, not the full "
             f"{mm['window_days']}-day history: raise <code>--max-transcripts</code> to widen it."
             + ("" if mm["projected_30d"] is not None else
                " Daily burn and the 30-day run-rate read <b>n/a</b> because the sample spans "
                "under two days; extrapolating one partial day would invent a number."))

    mix = ""
    kinds = [("cache_read_input_tokens", "cache read", "one"),
             ("cache_creation_input_tokens", "cache write", "ovr"),
             ("input_tokens", "fresh input", "skip"),
             ("output_tokens", "output", "ok")]
    mx = max((tok[k] for k, _, _ in kinds), default=1) or 1
    for k, label, cls in kinds:
        v = tok[k]
        mix += (f'<div class="mixrow"><span class="lbl">{label}</span>'
                f'<span class="mixtrack"><span class="seg {cls}" '
                f'style="width:{100 * v / mx:.1f}%"><i>{label}: {v:,}</i></span></span>'
                f'<span class="val">{fmt_tok(v)}</span></div>')
    mix_fig = (f'<figure class="chart"><figcaption>Token mix · where the tokens go</figcaption>'
               f'{mix}<p class="meta" style="margin:.5rem 0 0">Cache reads bill at '
               f'{CACHE_READ_MULT:g}x input and dominate volume; a high read:fresh ratio means a '
               f'large context re-read every turn.</p></figure>')

    model_rows = "".join(
        f'<tr><td><code>{H.escape(mo)}</code>'
        f'{"" if price_for(mo) else " <span class=chip warn>unpriced</span>"}</td>'
        f"<td>${e['cost']:,.2f}</td><td>{e['sessions']}</td>"
        f"<td>{fmt_tok(e['tok']['cache_read_input_tokens'])}</td>"
        f"<td>{fmt_tok(e['tok']['output_tokens'])}</td>"
        f"<td class=mono>{'/'.join(f'${x:g}' for x in price_for(mo)) if price_for(mo) else '-'}</td>"
        f"</tr>" for mo, e in mm["by_model"])

    proj_rows = "".join(
        f"<tr><td>{H.escape(p)}</td><td>${e['cost']:,.2f}</td><td>{e['sessions']}</td>"
        f"<td>{fmt_tok(sum(e['tok'][k] for k in TOKEN_KINDS))}</td></tr>"
        for p, e in mm["by_project"])

    days = [dtm.date.fromisoformat(d) for d in mm["trend_days"]] if mm["trend_days"] else []
    trend = (area_chart([round(c, 2) for c in mm["trend_cost"]], days,
                        "Spend per day (USD, computed)") if days else "")

    budget = ""
    if mm["budget"]:
        label = f"30d run-rate vs ${mm['budget']:,.0f} budget"
        budget = ('<figure class="chart"><figcaption>Pool headroom</figcaption>'
                  + gauge(mm["budget_used"], label)
                  + '<p class="meta" style="margin:.5rem 0 0">Budget is an operator input '
                    "(<code>--monthly-budget</code>), not a provider-reported quota.</p></figure>")

    side = mm["side"]
    tot_side = sum(side.values()) or 1
    side_rows = "".join(
        f'<div class="mixrow"><span class="lbl">{k}</span>'
        f'<span class="mixtrack"><span class="seg {"one" if k == "main" else "ovr"}" '
        f'style="width:{100 * v / tot_side:.1f}%"><i>{k}: {v}</i></span></span>'
        f'<span class="val">{100 * v / tot_side:.0f}%</span></div>'
        for k, v in side.most_common())

    unpriced = ""
    if mm["unpriced"]:
        unpriced = ('<p class="meta">Unpriced models (excluded from spend): '
                    + ", ".join(f"<code>{H.escape(u)}</code>" for u in mm["unpriced"]) + "</p>")

    cost_sec = f"""<section id="cost">
<div class="eyebrow">Spend</div>
<h1>Cost &amp; tokens</h1>
<p class="meta">Token counts are read from transcript usage; <b>dollar amounts are
computed</b> from a list-price table in the generator (transcripts carry no cost field).
Treat them as an estimate of list-price spend, not an invoice.</p>
{scope}
<div class="tiles">{tiles}</div>
<div class="charts">{trend}{mix_fig}{budget}</div>
<h2>By model</h2>
<table><tr><th>model</th><th>spend</th><th>sessions</th><th>cache read</th>
<th>output</th><th>$/MTok in/out</th></tr>{model_rows}</table>
{unpriced}
<h2>By project</h2>
<table><tr><th>project</th><th>spend</th><th>sessions</th><th>tokens</th></tr>{proj_rows}</table>
</section>"""

    runtime_sec = f"""<section id="runtime">
<div class="eyebrow">Spend</div>
<h1>Runtime</h1>
<p class="meta">What served the work: model tier, service tier, CLI build, and the
main-thread vs subagent split. Provider account identity is <b>not</b> in the
transcripts, so per-account attribution needs an operator-supplied mapping; everything
below is derived from observed runs.</p>
<div class="tiles">
<div class="tile"><b>{len(mm['by_model'])}</b><span>models in play</span></div>
<div class="tile"><b>{', '.join(mm['tiers']) or '-'}</b><span>service tier</span></div>
<div class="tile"><b>{len(mm['versions'])}</b><span>CLI builds seen</span></div>
<div class="tile"><b>{sum(mm['side'].values()):,}</b><span>billed messages</span></div>
</div>
<div class="charts">
<figure class="chart"><figcaption>Main thread vs subagents</figcaption>{side_rows}
<p class="meta" style="margin:.5rem 0 0">Subagent share is the fan-out cost: high share
means most spend is delegated work, which is the cheap-first routing target.</p></figure>
{hbars([(v, c) for v, c in mm['versions'].most_common(6)], "CLI builds seen (messages)")}
</div>
</section>"""
    return cost_sec, runtime_sec


def debt_section(dm):
    cls = "ok" if dm["score"] >= 80 else ("warn" if dm["score"] >= 50 else "bad")
    items = "".join(
        f"<tr><td class=mono>{d['ts'].date()}</td><td><code>{H.escape(d['rid'])}</code></td>"
        f'<td><span class="chip {"warn" if d["significance"] == "high" else "dim"}">'
        f"{d['significance']}</span></td>"
        f'<td class="reason" title="{H.escape(d["reason"])}">{H.escape(d["reason"])}</td></tr>'
        for d in reversed(dm["open"])) or '<tr><td colspan=4 class=reason>no open defers</td></tr>'
    verdicts = " · ".join(f"{k} {v}" for k, v in dm["verdicts"].items()) or "none recorded"
    return f"""<section id="debt">
<div class="eyebrow">Verify</div>
<h1>Cognitive debt</h1>
<p class="meta">The understanding gate's read side (ADR-0031): verification proves the work
is correct; this score tracks whether the HUMAN still understands it. Computed only from
recorded <span class=mono>DEBT</span> ledger lines; formula in
DECISION-BRIEF-cognitive-debt-score.md. It pressures the weekend paydown; it never blocks.</p>
<div class="tiles">
<div class="tile"><b><span class="chip {cls}" style="font-size:18px">{dm['score']}</span></b>
<span>debt score (100 = absorbed)</span></div>
<div class="tile"><b>{dm['open_high']} / {dm['open_low']}</b><span>open defers · high / low</span></div>
<div class="tile"><b>{dm['last_paydown'] or 'never'}</b><span>last paydown</span></div>
<div class="tile"><b>{dm['staleness_days'] if dm['staleness_days'] is not None else '-'}</b><span>days since paydown</span></div>
<div class="tile"><b>{dm['total_lines']}</b><span>debt lines recorded</span></div>
</div>
<p class="meta">Verdict mix: {verdicts}. Engage lines do not name which defers they clear,
so the open list below is the audit surface; the number is the glance.</p>
<h2>Open defers (owed to the human)</h2>
<div class="scroll"><table><tr><th>date</th><th>run</th><th>sig</th><th>what is owed</th></tr>
{items}</table></div>
</section>"""


def config_section(cfg, policy, runtimes=None):
    if cfg:
        mods = "".join(
            f'<span class="chip {"ok" if v else "dim"}">{H.escape(str(k))}'
            f'{"" if v else " off"}</span> '
            for k, v in sorted(cfg["modules"].items())) or '<span class=reason>none declared</span>'
        tags = "".join(
            f'<div class="tile"><b>{v}</b><span>[{k}] keys</span></div>'
            for k, v in sorted(cfg["status_tags"].items()))
        keys = "".join(
            f"<tr><td class=mono>{H.escape(x['section'])}</td><td><code>{H.escape(x['key'])}</code></td>"
            f'<td><input class="cfg-key" data-section="{H.escape(x["section"])}" '
            f'data-key="{H.escape(x["key"])}" data-orig="{H.escape(str(x["value"]))}" '
            f'value="{H.escape(str(x["value"]))}"></td></tr>' for x in cfg["keys"][:40])
        cfg_html = (f"<h2>Modules (kit.toml)</h2><p>{mods}</p>"
                    f'<div class="tiles">{tags}</div>'
                    f"<h2>Config keys (editable)</h2><div class='scroll'><table>"
                    f"<tr><th>section</th><th>key</th><th>value</th></tr>{keys}</table></div>"
                    f'<div class="seg-bar"><button id="cfg-export">Export .kit.toml overrides</button></div>'
                    f'<textarea id="cfg-out" readonly hidden style="width:100%;min-height:6rem;'
                    f'font-family:var(--mono);font-size:11.5px;background:var(--sheet);'
                    f'color:var(--ink);border:1px solid var(--rule);padding:8px"></textarea>'
                    f'<p class="meta">Source: <code>{H.escape(cfg["path"])}</code>. Edited values export '
                    f"as a per-project <code>.kit.toml</code> override (only changed keys; the rest "
                    f"inherit). Status tags: an inert key does nothing until its tag says [impl].</p>")
    else:
        cfg_html = '<p class="meta">kit.toml not found from this checkout.</p>'

    caps = policy.get("capabilities", {})
    cap_html = ""
    for cid, cap in caps.items():
        provs = cap.get("providers", [])
        pref = cap.get("preferred", "")
        pref_sel = "".join(
            f'<option value="{H.escape(pv["id"])}" {"selected" if pv["id"] == pref else ""}>'
            f'{H.escape(pv["label"])}</option>' for pv in provs)
        rows = ""
        for pv in provs:
            act = pv.get("action", "allow")
            match = pv.get("match") or ""
            sel = "".join(f'<option {"selected" if act == a else ""}>{a}</option>'
                          for a in ("allow", "ask", "deny"))
            rows += (f'<tr data-cap="{H.escape(cid)}" data-provider="{H.escape(pv["id"])}">'
                     f'<td>{H.escape(pv["label"])}</td>'
                     f'<td><code>{H.escape(match) if match else "(built-in / no MCP match)"}</code></td>'
                     f'<td><select class="prov-act">{sel}</select></td>'
                     f'<td class="reason">{H.escape(pv.get("note", ""))}</td></tr>')
        for i, r in enumerate(cap.get("rules", [])):
            rows += (f'<tr data-cap="{H.escape(cid)}" data-rule="{i}">'
                     f"<td>custom rule</td><td><code>{H.escape(r['match'])}</code></td>"
                     f'<td><select class="prov-act">'
                     + "".join(f'<option {"selected" if r["action"] == a else ""}>{a}</option>'
                               for a in ("allow", "ask", "deny"))
                     + f'</select></td><td><button class="act rule-rm">remove</button></td></tr>')
        cap_html += f"""<h2>{H.escape(cap.get("label", cid))}</h2>
<p class="meta">Preferred provider (the rung the hook names when it warns):</p>
<p><select class="cap-pref" data-cap="{H.escape(cid)}">{pref_sel}</select></p>
<table class="cap-table" data-cap="{H.escape(cid)}">
<tr><th>provider / integration</th><th>tool match</th><th>action</th><th>note</th></tr>{rows}
</table>
<div class="seg-bar">
<input class="rule-match" data-cap="{H.escape(cid)}" placeholder="add tool match, e.g. mcp__foo__" style="min-width:16rem">
<button class="rule-add" data-cap="{H.escape(cid)}">Add rule</button>
</div>"""

    rt_html = ""
    if runtimes:
        rt_rows = "".join(
            f"<tr><td>{H.escape(r['label'])}</td>"
            f'<td><span class="chip {"ok" if r["detected"] else "dim"}">'
            f'{"detected" if r["detected"] else "not found"}</span></td>'
            f"<td>{r['files']}</td><td class=mono>{r['latest'] or '-'}</td>"
            f'<td><span class="chip {"ok" if r["adapter"] == "live" else "warn"}">'
            f'{"live adapter" if r["adapter"] == "live" else "detect-only"}</span></td></tr>'
            for r in runtimes)
        rt_html = f"""<h2>Agent runtimes on this host</h2>
<p class="meta">Where other-LLM interactions render: the event protocol is runtime-neutral,
so each runtime needs one adapter (lib/bench/events.py) to appear in the explorer, replay,
and spend views. Claude Code's adapter is live; the rest are detected with store stats and
are one adapter away (codex first: its rollout files are already JSONL on disk).</p>
<table><tr><th>runtime</th><th>status</th><th>store files</th><th>last activity</th>
<th>coverage</th></tr>{rt_rows}</table>"""

    return f"""<section id="config">
<div class="eyebrow">Operate</div>
<h1>Config &amp; tool policy</h1>
<p class="meta">Capabilities are served by interchangeable providers; pick the preferred
rung, set allow / ask / deny per provider, add custom matches. The
<span class=mono>tool-policy-guard</span> PreToolUse hook enforces it: <b>ask</b> warns
with the preferred rung, <b>deny</b> blocks. Export and save where the hook reads it
(<span class=mono>~/.claude/dwarves-kit/tool-policy.json</span>).</p>
{cap_html}
<div class="seg-bar">
<button id="policy-export">Export policy JSON</button>
</div>
<textarea id="policy-out" readonly style="width:100%;min-height:8rem;font-family:var(--mono);
font-size:11.5px;background:var(--sheet);color:var(--ink);border:1px solid var(--rule);
padding:8px;display:none"></textarea>
{rt_html}
{cfg_html}
</section>"""


def render(runs, events, sessions, bench_rows, metrics, alerts, out, money=None,
           debt=None, config=None, policy=None, runtimes=None):
    m = metrics
    mm = money or money_metrics(sessions, m["window_days"])
    dm = debt or debt_metrics([])
    policy = policy or DEFAULT_TOOL_POLICY
    firing = [a for a in alerts if a["firing"]]
    stream = events[:150]
    by_rid = {}
    for e in events:
        by_rid.setdefault(e["rid"], []).append(e)

    tiles = "".join(
        f'<div class="tile"><b>{v}</b><span>{k}</span></div>' for k, v in [
            (f"runs / {m['window_days']}d", m["runs"]),
            ("repos active", m["repos"]),
            ("gate records", m["gate_records"]),
            ("● ran", m["ran"]), ("○ skipped", m["skipped"]),
            ("⚑ overridden", m["overridden"]),
            ("lane misfires", m["misfires"]),
            ("full conformance", f"{m['full_conformance']}/{m['conf_known']}"),
            ("alerts firing", len(firing)),
        ])

    charts = (
        area_chart(m["trend_runs"], m["days"], f"Runs per day · last {m['window_days']}d")
        + area_chart(m["trend_gates"], m["days"], f"Gate records per day · last {m['window_days']}d")
        + verdict_mix(m["phase_mix"])
        + hbars(m["repo_counts"], "Runs by repo")
        + hbars(m["lane_minutes"], "Worker minutes by lane", "m")
        + heat_grid(m["heat"]))

    ex_rows = ""
    for r in runs:
        lane = r["meta"].get("lane", "")
        conf = r["conformance"]
        conf_html = (f'<span class="chip {"ok" if conf[0] == conf[1] else "bad"}">{conf[0]}/{conf[1]}</span>'
                     if conf else '<span class="chip dim">-</span>')
        g = r["gates"]
        counts = f"{sum(1 for s, _ in g.values() if s == 'pass')}● {sum(1 for s, _ in g.values() if s == 'skip')}○ {sum(1 for s, _ in g.values() if s == 'override')}⚑"
        mis = ' <span class="chip warn">misfire</span>' if r["misfire"] else ""
        mins = (r["t1"] - r["t0"]).total_seconds() / 60 if r["t0"] else 0
        tags = " ".join(filter(None, [
            "misfire" if r["misfire"] else "", lane and f"lane-{lane}",
            "low-conf" if conf and conf[0] < conf[1] else "",
            "recent" if (now() - r["t1"]).days <= 7 else "",
            r["meta"].get("repo", "")]))
        rid_events = by_rid.get(r["rid"], [])
        detail_rows = "".join(
            f"<tr><td class=mono>{e['ts'].strftime('%m-%d %H:%M')}</td>"
            f"<td class=mono>{H.escape(e['phase'])}</td><td>{_chip(e['status'])}</td>"
            f"<td class=reason title=\"{H.escape(e['reason'])}\">{H.escape(e['reason'])}</td></tr>"
            for e in sorted(rid_events, key=lambda e: e["ts"])[:60])
        detail = (f'<tr class="detail" data-detail="{H.escape(r["rid"].lower())}" hidden>'
                  f'<td colspan="8"><div class="detail-log">'
                  f"<p class=meta>Full usage log · {len(rid_events)} events · replay: "
                  f"<span class=mono>forge-tui run {H.escape(r['rid'])}</span></p>"
                  f"<table><tr><th>time</th><th>gate</th><th>verdict</th><th>reason</th></tr>"
                  f"{detail_rows}</table></div></td></tr>")
        ex_rows += (f'<tr class="exrow" data-k="{H.escape(r["rid"].lower())} {H.escape(tags)}" '
                    f'data-rid="{H.escape(r["rid"].lower())}" tabindex="0">'
                    f'<td><code>{H.escape(r["rid"])}</code>{mis}</td>'
                    f"<td>{r['t1'].date()}</td><td>{H.escape(r['meta'].get('repo', ''))}</td>"
                    f"<td>{H.escape(lane)}</td><td>{H.escape(r['meta'].get('type', ''))}</td>"
                    f"<td>{counts}</td><td>{conf_html}</td><td>{mins:.0f}m</td></tr>") + detail

    seg_defs = [("all", ""), ("misfires", "misfire"), ("low conformance", "low-conf"),
                ("full lane", "lane-full"), ("tiny lane", "lane-tiny"), ("last 7d", "recent")]
    segs = "".join(f'<button data-seg="{v}" {"class=on" if v == "" else ""}>{k}</button>'
                   for k, v in seg_defs)

    ev_rows = "".join(
        f"<tr><td class=mono>{e['ts'].strftime('%m-%d %H:%M')}</td><td><code>{H.escape(e['rid'])}</code></td>"
        f"<td class=mono>{H.escape(e['phase'])}</td><td>{_chip(e['status'])}</td>"
        f'<td class="reason" title="{H.escape(e["reason"])}">{H.escape(e["reason"])}</td></tr>'
        for e in stream)

    tool_tot, mcp_tot = Counter(), Counter()
    for s in sessions:
        for t, c in s["tools"].items():
            tool_tot[t] += c
            if t.startswith("mcp__"):
                mcp_tot[t.split("__")[1]] += c
    top_tools = hbars(tool_tot.most_common(14), "Top tools · recent sessions")
    mcp_html = ", ".join(f"<code>{H.escape(k)}</code> ({v})" for k, v in mcp_tot.most_common(8)) or "none seen"
    sess_rows = "".join(
        f'<tr><td><code>{H.escape(s["session"])}</code></td><td>{H.escape(s["project"])}</td>'
        f"<td class=mono>{H.escape(', '.join(mm.split('-')[1] if '-' in mm else mm for mm in list(s['models'])[:2]))}</td>"
        f"<td>{s['mins']}m</td><td>{sum(s['tools'].values())}</td>"
        f"<td class=reason>{H.escape(', '.join(f'{t} x{c}' for t, c in s['tools'].most_common(4)))}</td></tr>"
        for s in sessions)

    fps = [r for r in bench_rows if r.get("fail_detail")]
    fp_rows = "".join(
        f"<tr><td><code>{H.escape(r['task'])}</code></td>"
        f"<td><code>{H.escape(r['model'])}/{H.escape(r['executor'])}</code></td>"
        f"<td class=mono>{r['ts'][:10]}</td><td class=fp>{H.escape(r['fail_detail'])}</td></tr>"
        for r in fps)
    bpass = sum(1 for r in bench_rows if r.get("pass"))
    bcost = sum(r.get("cost_usd") or 0 for r in bench_rows)

    al_rows = "".join(
        f'<tr><td><code>{H.escape(a["id"])}</code></td>'
        f"<td class=mono>{a['metric']} {a['op']} {a['threshold']}</td><td class=mono>{a['value']}</td>"
        f'<td><span class="chip {"bad" if a["firing"] else "ok"}">{"FIRING" if a["firing"] else "ok"}</span></td>'
        f"<td class=reason>{H.escape(a['note'])}</td></tr>" for a in alerts)

    policy_json = json.dumps({k: v for k, v in policy.items() if not k.startswith('_')}, indent=1).replace('</', '<\\/')
    gen = now().isoformat(timespec="seconds")
    nav = "".join(
        f'<button class="navbtn" data-sec="{sid}" {"aria-current=page" if sid == "fleet" else ""}>{label}</button>'
        for sid, label in [("fleet", "Fleet"), ("explorer", "Run explorer"),
                           ("stream", "Event stream"), ("tools", "Tool activity")])
    nav_money = "".join(
        f'<button class="navbtn" data-sec="{sid}">{label}</button>'
        for sid, label in [("cost", "Cost &amp; tokens"), ("runtime", "Runtime")])
    nav2 = "".join(
        f'<button class="navbtn" data-sec="{sid}">{label}</button>'
        for sid, label in [("bench", "Bench / RCA"), ("alerts", "Alerts")])
    cost_sec, runtime_sec = money_sections(mm)
    debt_sec = debt_section(dm)
    config_sec = config_section(config, policy, runtimes)

    page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Forge · Observability</title>
{STYLE}
</head>
<body>
<div class="banner">LIVE DATA · generated from the run ledgers {gen} ·
<b>reproduce: python3 dashboard.py build</b></div>
<div class="spine"></div>
<div class="shell">
<aside>
<a class="wordmark" href="#fleet"><b>FORGE</b></a>
<div class="grp">Observe</div>
{nav}
<div class="grp">Spend</div>
{nav_money}
<div class="grp">Verify</div>
{nav2}
<button class="navbtn" data-sec="debt">Cognitive debt</button>
<div class="grp">Operate</div>
<button class="navbtn" data-sec="config">Config &amp; policy</button>
<div class="grp">Console</div>
<a class="navbtn" href="/dashboard/">Crew dashboard</a>
<button class="navbtn" id="redact-toggle" aria-pressed="false">Redact mode</button>
</aside>
<main>
<section id="fleet" class="on">
<div class="eyebrow">Control plane</div>
<h1>Fleet</h1>
<p class="meta">Every number reads from the append-only run ledgers. Nothing on this
page is hand-entered; a correction is a new run, never an edit.</p>
<div class="tiles">{tiles}</div>
<div class="charts">{charts}</div>
</section>
<section id="explorer">
<div class="eyebrow">Observe</div>
<h1>Run explorer</h1>
<p class="meta">{len(runs)} recorded runs. Segments are saved filters; conformance =
required gates present for the run's lane. Replay any row:
<span class=mono>forge-tui run &lt;rid&gt;</span>.</p>
<div class="seg-bar"><input id="q" placeholder="filter rid / repo / lane...">{segs}</div>
<div class="scroll"><table id="ex"><tr><th>rid</th><th>last event</th><th>repo</th>
<th>lane</th><th>type</th><th>gates</th><th>conformance</th><th>span</th></tr>
{ex_rows}</table></div>
</section>
<section id="stream">
<div class="eyebrow">Observe</div>
<h1>Event stream</h1>
<p class="meta">Latest {len(stream)} gate verdicts across every run; the reason is the
audit trail.</p>
<div class="seg-bar">
<button id="audit-csv">Download audit CSV</button>
</div>
<div class="scroll"><table><tr><th>time</th><th>rid</th><th>gate</th><th>verdict</th>
<th>reason</th></tr>{ev_rows}</table></div>
</section>
<section id="tools">
<div class="eyebrow">Observe</div>
<h1>Tool activity</h1>
<p class="meta">{len(sessions)} recent sessions from this host's Claude Code transcripts,
counts only: tool names, models, timing. Message content is never read into this page.
MCP servers seen: {mcp_html}.</p>
<div class="charts">{top_tools}</div>
<div class="scroll"><table><tr><th>session</th><th>project</th><th>model</th><th>span</th>
<th>tool calls</th><th>top tools</th></tr>{sess_rows}</table></div>
</section>
{cost_sec}
{runtime_sec}
{debt_sec}
{config_sec}
<section id="bench">
<div class="eyebrow">Verify</div>
<h1>Bench / RCA</h1>
<div class="tiles">
<div class="tile"><b>{len(bench_rows)}</b><span>recorded cells</span></div>
<div class="tile"><b>{bpass}/{len(bench_rows)}</b><span>passed</span></div>
<div class="tile"><b>${bcost:.2f}</b><span>total spend</span></div>
<div class="tile"><b>{len(fps)}</b><span>failure fingerprints</span></div>
</div>
<p class="meta">Fingerprints answer "failed on what, exactly": the verbatim failing case.</p>
<div class="scroll"><table><tr><th>task</th><th>config</th><th>date</th>
<th>fingerprint</th></tr>{fp_rows}</table></div>
</section>
<section id="alerts">
<div class="eyebrow">Verify</div>
<h1>Alerts</h1>
<p class="meta">Template rules from a plain JSON file, evaluated at build over the
{m['window_days']}-day window. Propose-first: no daemon, no auto-fix. {len(firing)} firing.</p>
<table><tr><th>rule</th><th>condition</th><th>value</th><th>state</th><th>note</th></tr>
{al_rows}</table>
</section>
<div class="footer">Forge control plane · facts from run ledgers · counts-only transcripts ·
design per forge-design-guidelines.md</div>
</main>
</div>
<script type="application/json" id="policy-data">{policy_json}</script>
<script>
const secs=document.querySelectorAll("section"),btns=document.querySelectorAll(".navbtn");
function show(id){{
  secs.forEach(s=>s.classList.toggle("on",s.id===id));
  btns.forEach(b=>{{if(b.dataset.sec===id)b.setAttribute("aria-current","page");
    else b.removeAttribute("aria-current");}});
}}
btns.forEach(b=>b.onclick=()=>{{show(b.dataset.sec);
  history.replaceState(null,"","#"+b.dataset.sec);}});
if(location.hash&&document.getElementById(location.hash.slice(1)))show(location.hash.slice(1));
let seg="";
const q=document.getElementById("q");
function filt(){{
  const t=q.value.toLowerCase();
  document.querySelectorAll("#ex tr[data-k]").forEach(r=>{{
    const k=r.dataset.k;
    r.style.display=(k.includes(t)&&(seg===""||k.includes(seg)))?"":"none";
  }});
}}
q.oninput=filt;
document.querySelectorAll(".seg-bar button[data-seg]").forEach(b=>b.onclick=()=>{{
  seg=b.dataset.seg;
  document.querySelectorAll(".seg-bar button[data-seg]").forEach(x=>x.classList.toggle("on",x===b));
  filt();
}});
document.querySelectorAll("tr.exrow").forEach(r=>{{
  const open=()=>{{const d=document.querySelector(`tr.detail[data-detail="${{r.dataset.rid}}"]`);
    if(d)d.hidden=!d.hidden;}};
  r.onclick=e=>{{if(!e.target.closest("a"))open();}};
  r.onkeydown=e=>{{if(e.key==="Enter"||e.key===" "){{e.preventDefault();open();}}}};
}});
const red=document.getElementById("redact-toggle");
if(red)red.onclick=()=>{{
  const on=document.body.classList.toggle("redacted");
  red.setAttribute("aria-pressed",String(on));
  red.textContent=on?"Redacted (click to show)":"Redact mode";
}};
const csvBtn=document.getElementById("audit-csv");
if(csvBtn)csvBtn.onclick=()=>{{
  const rows=[["time","rid","gate","verdict","reason"]];
  document.querySelectorAll("#stream table tr").forEach(tr=>{{
    const c=tr.querySelectorAll("td");
    if(c.length===5)rows.push([...c].map(td=>'"'+td.textContent.trim().replace(/"/g,'""')+'"'));
  }});
  const blob=new Blob([rows.map(r=>r.join(",")).join("\\n")],{{type:"text/csv"}});
  const a=document.createElement("a");
  a.href=URL.createObjectURL(blob);a.download="forge-audit.csv";a.click();
  URL.revokeObjectURL(a.href);
}};
document.querySelectorAll(".rule-add").forEach(b=>b.onclick=()=>{{
  const cap=b.dataset.cap;
  const inp=document.querySelector(`.rule-match[data-cap="${{cap}}"]`);
  const m=(inp.value||"").trim();
  if(!m)return;
  const tbl=document.querySelector(`.cap-table[data-cap="${{cap}}"]`);
  const tr=document.createElement("tr");
  tr.dataset.cap=cap;tr.dataset.custom="1";
  tr.innerHTML=`<td>custom rule</td><td><code>${{m}}</code></td>`+
    `<td><select class="prov-act"><option>allow</option><option selected>ask</option>`+
    `<option>deny</option></select></td><td><button class="act rule-rm">remove</button></td>`;
  tbl.appendChild(tr);
  inp.value="";
  tr.querySelector(".rule-rm").onclick=()=>tr.remove();
}});
document.querySelectorAll(".rule-rm").forEach(b=>b.onclick=()=>b.closest("tr").remove());
const pex=document.getElementById("policy-export");
if(pex)pex.onclick=()=>{{
  const base=JSON.parse(document.getElementById("policy-data").textContent);
  const caps=base.capabilities||{{}};
  for(const cid of Object.keys(caps)){{
    const cap=caps[cid];
    const pref=document.querySelector(`.cap-pref[data-cap="${{cid}}"]`);
    if(pref)cap.preferred=pref.value;
    document.querySelectorAll(`.cap-table[data-cap="${{cid}}"] tr[data-provider]`).forEach(tr=>{{
      const pv=(cap.providers||[]).find(x=>x.id===tr.dataset.provider);
      const s=tr.querySelector("select.prov-act");
      if(pv&&s)pv.action=s.value;
    }});
    cap.rules=[];
    document.querySelectorAll(`.cap-table[data-cap="${{cid}}"] tr[data-custom],`+
      `.cap-table[data-cap="${{cid}}"] tr[data-rule]`).forEach(tr=>{{
      const m=tr.querySelector("code");
      const s=tr.querySelector("select.prov-act");
      if(m&&s)cap.rules.push({{match:m.textContent,action:s.value}});
    }});
  }}
  const out=document.getElementById("policy-out");
  out.style.display="block";
  out.value=JSON.stringify(base,null,2);
  out.select();
  const blob=new Blob([out.value],{{type:"application/json"}});
  const a=document.createElement("a");
  a.href=URL.createObjectURL(blob);a.download="tool-policy.json";a.click();
  URL.revokeObjectURL(a.href);
}};
const cex=document.getElementById("cfg-export");
if(cex)cex.onclick=()=>{{
  const changed={{}};
  document.querySelectorAll("input.cfg-key").forEach(i=>{{
    if(i.value!==i.dataset.orig){{
      (changed[i.dataset.section]=changed[i.dataset.section]||{{}})[i.dataset.key]=i.value;
    }}
  }});
  let toml="# .kit.toml , per-project overrides (changed keys only; the rest inherit)\\n";
  for(const sec of Object.keys(changed)){{
    toml+=`\\n[${{sec}}]\\n`;
    for(const k of Object.keys(changed[sec])){{
      const v=changed[sec][k];
      toml+=`${{k}} = ${{/^(true|false|-?\\d+(\\.\\d+)?)$/.test(v)?v:JSON.stringify(v)}}\\n`;
    }}
  }}
  const out=document.getElementById("cfg-out");
  out.hidden=false;
  out.value=Object.keys(changed).length?toml:"# no keys changed";
  out.select();
}};
</script>
</body>
</html>"""
    Path(out).write_text(page)
    print(f"dashboard written to {out}: {len(runs)} runs, {len(events)} events, "
          f"{len(sessions)} sessions, {len(bench_rows)} bench cells, "
          f"{len(firing)} alerts firing", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(prog="bench-dashboard", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="build the control-plane dashboard page")
    b.add_argument("--log-dir", default=os.environ.get(
        "DWARVES_KIT_LOG_DIR", str(Path.home() / ".local/state/dwarves-kit/logs")))
    b.add_argument("--transcripts-dir", default=str(Path.home() / ".claude/projects"))
    b.add_argument("--max-transcripts", type=int, default=25)
    b.add_argument("--alerts", default=None, help="JSON rules file; default built-ins")
    b.add_argument("--window-days", type=int, default=30)
    b.add_argument("--monthly-budget", type=float, default=None,
                   help="USD budget for the pool-headroom gauge (operator input)")
    b.add_argument("--tool-policy", default=None,
                   help="tool-policy JSON to render (default: ~/.claude/dwarves-kit/tool-policy.json)")
    b.add_argument("--out", default="dashboard.html")
    s = sub.add_parser("stats", help="all dashboard numbers as JSON (agent surface)")
    d = sub.add_parser("debt", help="cognitive-debt score (ADR-0031 read side)")
    for x in (s, d):
        x.add_argument("--log-dir", default=os.environ.get(
            "DWARVES_KIT_LOG_DIR", str(Path.home() / ".local/state/dwarves-kit/logs")))
        x.add_argument("--format", choices=("text", "json"), default="text")
    s.add_argument("--transcripts-dir", default=str(Path.home() / ".claude/projects"))
    s.add_argument("--max-transcripts", type=int, default=25)
    s.add_argument("--window-days", type=int, default=30)
    s.set_defaults(format="json")
    a = ap.parse_args()

    if a.cmd == "debt":
        dm = debt_metrics(collect_debt(a.log_dir))
        if a.format == "json":
            print(json.dumps(dm, default=str, indent=1))
        else:
            print(f"cognitive debt score: {dm['score']}/100  "
                  f"(open defers {dm['open_high']} high / {dm['open_low']} low, "
                  f"last paydown {dm['last_paydown'] or 'never'})")
            for d in dm["open"]:
                print(f"  {d['ts'].date()} [{d['significance']}] {d['reason'][:120]}")
        return

    runs = collect_runs(a.log_dir)
    events = collect_events(a.log_dir)
    sessions = collect_sessions(a.transcripts_dir, a.max_transcripts)
    bench_rows = collect_bench()
    metrics = fleet_metrics(runs, events, a.window_days)
    money = money_metrics(sessions, a.window_days, getattr(a, "monthly_budget", None))
    dm = debt_metrics(collect_debt(a.log_dir))
    rules = (json.loads(Path(a.alerts).read_text())
             if getattr(a, "alerts", None) else DEFAULT_ALERTS)
    alerts = eval_alerts({**metrics, **{f"cost_{k}": v for k, v in
                                        (("total", money["total_cost"]),
                                         ("per_session", money["cost_per_session"]),
                                         ("cache_hit", money["cache_hit"]))}}, rules)

    if a.cmd == "stats":
        # Agent-first surface: every number on the page, one JSON blob, no HTML.
        drop = {"days", "heat", "phase_mix", "trend_runs", "trend_gates"}
        slim = {k: v for k, v in metrics.items() if k not in drop}
        mslim = {k: v for k, v in money.items()
                 if k not in {"by_model", "by_project", "trend_days", "trend_cost", "tok"}}
        mslim["tok"] = dict(money["tok"])
        mslim["by_model"] = [
            {"model": mo, "cost": round(e["cost"], 2), "sessions": e["sessions"]}
            for mo, e in money["by_model"]]
        print(json.dumps({"fleet": slim, "money": mslim, "debt": dm,
                          "alerts": [{"id": x["id"], "firing": x["firing"], "value": x["value"]}
                                     for x in alerts]},
                         default=str, indent=1))
        return

    policy_path = Path(getattr(a, "tool_policy", "") or
                       Path.home() / ".claude/dwarves-kit/tool-policy.json")
    policy = (json.loads(policy_path.read_text()) if policy_path.exists()
              else DEFAULT_TOOL_POLICY)
    render(runs, events, sessions, bench_rows, metrics, alerts, a.out, money,
           debt=dm, config=collect_config(), policy=policy, runtimes=collect_runtimes())


if __name__ == "__main__":
    main()
