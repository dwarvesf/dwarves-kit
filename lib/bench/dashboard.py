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
from tui import expected_plan  # noqa: E402

HERE = Path(__file__).resolve().parent
UTC = dtm.timezone.utc
PHASE_ORDER = ["grill", "think", "design", "design-critique", "ui-design", "spec",
               "validate", "design-record", "test-plan", "build", "review", "docs",
               "ship", "reflect"]


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
        tools, models = Counter(), Counter()
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
                    msg = d.get("message") or {}
                    if isinstance(msg, dict):
                        if msg.get("model"):
                            models[msg["model"]] += 1
                        for blk in msg.get("content") or []:
                            if isinstance(blk, dict) and blk.get("type") == "tool_use":
                                tools[blk.get("name", "?")] += 1
        except OSError:
            continue
        if not tools:
            continue
        mins = 0
        try:
            if t0 and t1:
                mins = (dtm.datetime.fromisoformat(t1.replace("Z", "+00:00"))
                        - dtm.datetime.fromisoformat(t0.replace("Z", "+00:00"))).total_seconds() / 60
        except ValueError:
            pass
        sessions.append({"session": f.stem[:8], "project": f.parent.name.split("-")[-1],
                         "models": models, "tools": tools, "mins": round(mins)})
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
@media (prefers-reduced-motion:no-preference){.navbtn,.chip{transition:color .15s,border-color .15s}}
</style>"""


def _chip(status):
    cls = {"ran": "ok", "skipped": "dim", "override": "warn"}.get(status, "dim")
    label = {"ran": "● OK", "skipped": "○ SKIP", "override": "⚑ OVERRIDE"}.get(status, status.upper())
    return f'<span class="chip {cls}">{label}</span>'


def render(runs, events, sessions, bench_rows, metrics, alerts, out):
    m = metrics
    firing = [a for a in alerts if a["firing"]]
    stream = events[:150]

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
        ex_rows += (f'<tr data-k="{H.escape(r["rid"].lower())} {H.escape(tags)}">'
                    f'<td><code>{H.escape(r["rid"])}</code>{mis}</td>'
                    f"<td>{r['t1'].date()}</td><td>{H.escape(r['meta'].get('repo', ''))}</td>"
                    f"<td>{H.escape(lane)}</td><td>{H.escape(r['meta'].get('type', ''))}</td>"
                    f"<td>{counts}</td><td>{conf_html}</td><td>{mins:.0f}m</td></tr>")

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

    gen = now().isoformat(timespec="seconds")
    nav = "".join(
        f'<button class="navbtn" data-sec="{sid}" {"aria-current=page" if sid == "fleet" else ""}>{label}</button>'
        for sid, label in [("fleet", "Fleet"), ("explorer", "Run explorer"),
                           ("stream", "Event stream"), ("tools", "Tool activity")])
    nav2 = "".join(
        f'<button class="navbtn" data-sec="{sid}">{label}</button>'
        for sid, label in [("bench", "Bench / RCA"), ("alerts", "Alerts")])

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
<div class="grp">Verify</div>
{nav2}
<div class="grp">Console</div>
<a class="navbtn" href="/dashboard/">Crew dashboard</a>
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
<span class=mono>python3 tui.py run &lt;rid&gt;</span>.</p>
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
document.querySelectorAll(".seg-bar button").forEach(b=>b.onclick=()=>{{
  seg=b.dataset.seg;
  document.querySelectorAll(".seg-bar button").forEach(x=>x.classList.toggle("on",x===b));
  filt();
}});
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
    b.add_argument("--out", default="dashboard.html")
    a = ap.parse_args()

    runs = collect_runs(a.log_dir)
    events = collect_events(a.log_dir)
    sessions = collect_sessions(a.transcripts_dir, a.max_transcripts)
    bench_rows = collect_bench()
    metrics = fleet_metrics(runs, events, a.window_days)
    rules = json.loads(Path(a.alerts).read_text()) if a.alerts else DEFAULT_ALERTS
    alerts = eval_alerts(metrics, rules)
    render(runs, events, sessions, bench_rows, metrics, alerts, a.out)


if __name__ == "__main__":
    main()
