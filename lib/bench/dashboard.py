#!/usr/bin/env python3
"""bench dashboard: the control-plane dashboard over ALL recorded data.

One self-contained page with a sidebar (the Fiddler-parity surface set, fed by
our own data planes):

  Fleet         KPI tiles + 30-day trends over every run ledger
  Explorer      filterable/segmented index of every rid -> replay commands
  Event stream  time-ordered gate verdict feed (OK / skipped / override) + reasons
  Tool activity real Claude Code session transcripts: tool calls, MCP servers, models
  Bench / RCA   benchmark KPIs + the failure-fingerprint table
  Alerts        template rules (plain JSON) evaluated at build time

Data sources, honest by construction: run ledgers (logs/runs/*.log) and bench
rows (runs/*.jsonl) are facts; transcripts contribute COUNTS ONLY (tool names,
models, timing; never message content). Design: docs/dashboard-design.md.

  build [--log-dir D] [--transcripts-dir D] [--max-transcripts N]
        [--alerts alerts.json] [--out dashboard.html]
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


def collect_events(log_dir, limit=150):
    """Time-ordered gate events across every rid (the verdict stream)."""
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
    return evs[:limit]


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

def fleet_metrics(runs, window_days=30):
    cut = now() - dtm.timedelta(days=window_days)
    w = [r for r in runs if r["t1"] >= cut]
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
    m["trend_runs"] = [per_day.get(d, 0) for d in days]
    ev_day = Counter()
    for r in w:
        ev_day[r["t1"].date()] += len(r["gates"])
    m["trend_gates"] = [ev_day.get(d, 0) for d in days]
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


# ---- render -----------------------------------------------------------------

STYLE = """<style>
:root{--bg:#fafafa;--fg:#111827;--line:#37415133;--muted:#6b7280;--accent:#4f46e5;
--card:#ffffff;--warn:#d97706;--ok:#16a34a;--bad:#dc2626;--okbg:#dcfce7;--badbg:#fee2e2}
@media(prefers-color-scheme:dark){:root{--bg:#0f172a;--fg:#f3f4f6;--line:#9ca3af33;
--muted:#9ca3af;--accent:#818cf8;--card:#1e293b;--warn:#fbbf24;--ok:#4ade80;
--bad:#f87171;--okbg:#14532d;--badbg:#7f1d1d}}
:root[data-theme=dark]{--bg:#0f172a;--fg:#f3f4f6;--line:#9ca3af33;--muted:#9ca3af;
--accent:#818cf8;--card:#1e293b;--warn:#fbbf24;--ok:#4ade80;--bad:#f87171;
--okbg:#14532d;--badbg:#7f1d1d}
:root[data-theme=light]{--bg:#fafafa;--fg:#111827;--line:#37415133;--muted:#6b7280;
--accent:#4f46e5;--card:#ffffff;--warn:#d97706;--ok:#16a34a;--bad:#dc2626;
--okbg:#dcfce7;--badbg:#fee2e2}
*{box-sizing:border-box}
body{font-family:system-ui,sans-serif;background:var(--bg);color:var(--fg);
margin:0;line-height:1.5;display:flex;min-height:100vh}
nav{width:13.5rem;flex-shrink:0;border-right:1px solid var(--line);padding:1rem .8rem;
position:sticky;top:0;height:100vh;overflow-y:auto}
nav h1{font-size:.95rem;margin:.2rem .4rem 1rem}
nav a{display:block;padding:.42rem .6rem;border-radius:6px;color:var(--fg);
text-decoration:none;font-size:.88rem;margin:.1rem 0}
nav a.on{background:var(--accent);color:#fff}
nav a:hover:not(.on){background:color-mix(in srgb,var(--accent) 12%,transparent)}
nav .grp{font-size:.68rem;text-transform:uppercase;letter-spacing:.06em;
color:var(--muted);margin:1rem .6rem .2rem}
main{flex:1;padding:1.2rem 1.6rem;max-width:70rem;min-width:0}
section{display:none}section.on{display:block}
h2{font-size:1.05rem;margin:.4rem 0 .8rem}
.meta{color:var(--muted);font-size:.84rem;max-width:75ch}
.tiles{display:grid;grid-template-columns:repeat(auto-fill,minmax(10.5rem,1fr));
gap:.7rem;margin:1rem 0}
.tile{border:1px solid var(--line);border-radius:10px;background:var(--card);
padding:.7rem .9rem}
.tile b{display:block;font-size:1.35rem;font-variant-numeric:tabular-nums}
.tile span{font-size:.78rem;color:var(--muted)}
.tile svg{display:block;margin-top:.3rem}
.tile svg polyline{fill:none;stroke:var(--accent);stroke-width:1.6}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums;margin:.6rem 0}
th,td{border:1px solid var(--line);padding:.32rem .55rem;font-size:.82rem;text-align:left}
th{font-size:.68rem;text-transform:uppercase;letter-spacing:.05em;position:sticky;top:0;
background:var(--bg)}
.chip{display:inline-block;border-radius:99px;padding:0 .55rem;font-size:.75rem;font-weight:600}
.chip.ok{background:var(--okbg)}.chip.bad{background:var(--badbg)}
.chip.warn{color:var(--warn);border:1px solid var(--warn)}
.chip.dim{color:var(--muted);border:1px solid var(--line)}
.seg{display:flex;flex-wrap:wrap;gap:.4rem;margin:.6rem 0}
.seg button,#q{font:inherit;font-size:.8rem;background:var(--card);color:var(--fg);
border:1px solid var(--line);border-radius:99px;padding:.22rem .8rem;cursor:pointer}
.seg button.on{border-color:var(--accent);color:var(--accent);font-weight:600}
#q{border-radius:8px;min-width:14rem}
.scroll{max-height:32rem;overflow:auto;border:1px solid var(--line);border-radius:8px}
.scroll table{margin:0}
.reason{color:var(--muted);font-size:.78rem;max-width:34rem;overflow:hidden;
text-overflow:ellipsis;white-space:nowrap}
.bar{height:.55rem;background:var(--accent);border-radius:3px;display:inline-block;
vertical-align:middle}
code{font-family:ui-monospace,monospace;font-size:.85em}
.fp{font-family:ui-monospace,monospace;font-size:.75rem;color:var(--bad);white-space:pre-wrap}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(16rem,1fr));gap:.7rem}
.card{border:1px solid var(--line);border-radius:10px;background:var(--card);padding:.7rem .9rem;
font-size:.85rem}
@media(max-width:760px){body{flex-direction:column}nav{width:auto;height:auto;position:static;
display:flex;flex-wrap:wrap;gap:.2rem}nav h1,nav .grp{display:none}main{padding:1rem}}
</style>"""


def spark(vals, w=120, h=26):
    if not vals or max(vals) == 0:
        return ""
    mx = max(vals)
    pts = " ".join(f"{i * w / (len(vals) - 1):.1f},{h - 2 - (v / mx) * (h - 5):.1f}"
                   for i, v in enumerate(vals))
    return f'<svg width="{w}" height="{h}" viewBox="0 0 {w} {h}"><polyline points="{pts}"/></svg>'


def _chip(status):
    cls = {"ran": "ok", "skipped": "dim", "override": "warn"}.get(status, "dim")
    label = {"ran": "OK", "skipped": "SKIP", "override": "OVERRIDE"}.get(status, status.upper())
    return f'<span class="chip {cls}">{label}</span>'


def render(runs, events, sessions, bench_rows, metrics, alerts, out):
    m = metrics
    firing = [a for a in alerts if a["firing"]]

    tiles = ""
    for label, val, extra in [
        ("runs (30d)", m["runs"], spark(m["trend_runs"])),
        ("repos active", m["repos"], ""),
        ("gate records", m["gate_records"], spark(m["trend_gates"])),
        ("gates ran", m["ran"], ""),
        ("skipped", m["skipped"], ""),
        ("overridden", m["overridden"], f"<span>rate {m['override_rate']:.0%}</span>"),
        ("lane misfires", m["misfires"], f"<span>rate {m['misfire_rate']:.0%}</span>"),
        ("full conformance", f"{m['full_conformance']}/{m['conf_known']}",
         "<span>of runs with a known lane</span>"),
        ("alerts firing", len(firing), ""),
    ]:
        tiles += f'<div class="tile"><b>{val}</b><span>{label}</span>{extra}</div>'

    ex_rows = ""
    for r in runs:
        lane = r["meta"].get("lane", "")
        conf = r["conformance"]
        conf_html = (f'<span class="chip {"ok" if conf[0] == conf[1] else "bad"}">{conf[0]}/{conf[1]}</span>'
                     if conf else "<small>-</small>")
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
        f"<tr><td>{e['ts'].strftime('%m-%d %H:%M')}</td><td><code>{H.escape(e['rid'])}</code></td>"
        f"<td>{H.escape(e['phase'])}</td><td>{_chip(e['status'])}</td>"
        f'<td class="reason" title="{H.escape(e["reason"])}">{H.escape(e["reason"])}</td></tr>'
        for e in events)

    tool_tot = Counter()
    mcp_tot = Counter()
    for s in sessions:
        for t, c in s["tools"].items():
            tool_tot[t] += c
            if t.startswith("mcp__"):
                mcp_tot[t.split("__")[1]] += c
    mx = max(tool_tot.values()) if tool_tot else 1
    top_tools = "".join(
        f'<tr><td><code>{H.escape(t)}</code></td>'
        f'<td><span class="bar" style="width:{max(2, 160 * c / mx)}px"></span> {c}</td></tr>'
        for t, c in tool_tot.most_common(15))
    mcp_html = ", ".join(f"<code>{H.escape(k)}</code> ({v})" for k, v in mcp_tot.most_common(8)) or "none seen"
    sess_rows = "".join(
        f'<tr><td><code>{H.escape(s["session"])}</code></td><td>{H.escape(s["project"])}</td>'
        f"<td>{H.escape(', '.join(m.split('-')[1] if '-' in m else m for m in list(s['models'])[:2]))}</td>"
        f"<td>{s['mins']}m</td><td>{sum(s['tools'].values())}</td>"
        f"<td>{H.escape(', '.join(f'{t} x{c}' for t, c in s['tools'].most_common(4)))}</td></tr>"
        for s in sessions)

    fps = [r for r in bench_rows if r.get("fail_detail")]
    fp_rows = "".join(
        f"<tr><td><code>{H.escape(r['task'])}</code></td>"
        f"<td><code>{H.escape(r['model'])}/{H.escape(r['executor'])}</code></td>"
        f"<td>{r['ts'][:10]}</td><td class=fp>{H.escape(r['fail_detail'])}</td></tr>"
        for r in fps)
    bpass = sum(1 for r in bench_rows if r.get("pass"))
    bcost = sum(r.get("cost_usd") or 0 for r in bench_rows)

    al_rows = "".join(
        f'<tr><td><code>{H.escape(a["id"])}</code></td>'
        f"<td>{a['metric']} {a['op']} {a['threshold']}</td><td>{a['value']}</td>"
        f'<td><span class="chip {"bad" if a["firing"] else "ok"}">{"FIRING" if a["firing"] else "ok"}</span></td>'
        f"<td class=reason>{H.escape(a['note'])}</td></tr>" for a in alerts)

    gen = now().isoformat(timespec="seconds")
    page = f"""<title>bench · control plane</title>
{STYLE}
<nav>
<h1>⌁ bench control plane</h1>
<div class="grp">Observe</div>
<a href="#fleet" class="on">Fleet</a>
<a href="#explorer">Run explorer</a>
<a href="#stream">Event stream</a>
<a href="#tools">Tool activity</a>
<div class="grp">Verify</div>
<a href="#bench">Bench / RCA</a>
<a href="#alerts">Alerts</a>
</nav>
<main>
<section id="fleet" class="on">
<h2>Fleet · last {m['window_days']} days</h2>
<p class="meta">Every number reads from the append-only run ledgers; nothing here is
hand-entered. Generated {gen}.</p>
<div class="tiles">{tiles}</div>
<p class="meta">Companion surfaces: the run viewer replays any rid below
(<code>python3 tui.py run &lt;rid&gt;</code>); report.py renders a mega-run;
the scoreboard renders bench baselines.</p>
</section>
<section id="explorer">
<h2>Run explorer · {len(runs)} recorded runs</h2>
<div class="seg"><input id="q" placeholder="filter rid / repo / lane...">{segs}</div>
<div class="scroll"><table id="ex"><tr><th>rid</th><th>last event</th><th>repo</th>
<th>lane</th><th>type</th><th>gates</th><th>conformance</th><th>span</th></tr>
{ex_rows}</table></div>
<p class="meta">Segments are saved filters; conformance = required gates present for
the run's lane (from the WORKFLOW matrix). Replay any row:
<code>python3 tui.py run &lt;rid&gt;</code>.</p>
</section>
<section id="stream">
<h2>Event stream · latest {len(events)} gate verdicts</h2>
<div class="scroll"><table><tr><th>time</th><th>rid</th><th>gate</th><th>verdict</th>
<th>reason</th></tr>{ev_rows}</table></div>
</section>
<section id="tools">
<h2>Tool activity · {len(sessions)} recent sessions (counts only)</h2>
<p class="meta">From Claude Code transcripts on this host: tool names, models, and
timing only; message content is never read into this page. MCP servers seen:
{mcp_html}.</p>
<div class="cards"><div class="card"><b>Top tools</b>
<table>{top_tools}</table></div>
<div class="card" style="grid-column:span 2;min-width:0"><b>Sessions</b>
<div class="scroll" style="max-height:22rem"><table><tr><th>session</th><th>project</th>
<th>model</th><th>span</th><th>tool calls</th><th>top tools</th></tr>{sess_rows}</table>
</div></div></div>
</section>
<section id="bench">
<h2>Bench / RCA</h2>
<div class="tiles">
<div class="tile"><b>{len(bench_rows)}</b><span>recorded cells</span></div>
<div class="tile"><b>{bpass}/{len(bench_rows)}</b><span>passed</span></div>
<div class="tile"><b>${bcost:.2f}</b><span>total spend</span></div>
<div class="tile"><b>{len(fps)}</b><span>failure fingerprints</span></div>
</div>
<h2>Failure fingerprints (what exactly failed)</h2>
<div class="scroll"><table><tr><th>task</th><th>config</th><th>date</th>
<th>fingerprint</th></tr>{fp_rows}</table></div>
</section>
<section id="alerts">
<h2>Alerts · template rules over the {m['window_days']}-day window</h2>
<p class="meta">Rules live in a plain JSON file next to this generator; evaluation
happens at build time (propose-first, no daemon). {len(firing)} firing.</p>
<table><tr><th>rule</th><th>condition</th><th>value</th><th>state</th><th>note</th></tr>
{al_rows}</table>
</section>
</main>
<script>
const secs = document.querySelectorAll("section"), links = document.querySelectorAll("nav a");
function show(id){{
  secs.forEach(s=>s.classList.toggle("on", s.id===id));
  links.forEach(l=>l.classList.toggle("on", l.getAttribute("href")==="#"+id));
}}
links.forEach(l=>l.onclick=e=>{{e.preventDefault();show(l.getAttribute("href").slice(1));
history.replaceState(null,"","#"+l.getAttribute("href").slice(1));}});
if(location.hash) show(location.hash.slice(1));
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
document.querySelectorAll(".seg button").forEach(b=>b.onclick=()=>{{
  seg=b.dataset.seg;
  document.querySelectorAll(".seg button").forEach(x=>x.classList.toggle("on",x===b));
  filt();
}});
</script>"""
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
    metrics = fleet_metrics(runs, a.window_days)
    rules = json.loads(Path(a.alerts).read_text()) if a.alerts else DEFAULT_ALERTS
    alerts = eval_alerts(metrics, rules)
    render(runs, events, sessions, bench_rows, metrics, alerts, a.out)


if __name__ == "__main__":
    main()
