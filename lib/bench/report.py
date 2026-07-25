#!/usr/bin/env python3
"""bench report: the control-plane view over MANY runs (the RUN_REPORT, rendered).

Where viewer.py replays ONE run, report.py renders a fleet: swimlane timeline
(per-worker bars, model-colored), worker minutes by model, the gate-coverage
matrix (recorded / skipped-with-reason / override / absent, reasons on hover),
an optional wave dispatch board, and incidents.

Data split, honest by construction:
- FACTS come from the kit's own run ledgers (logs/runs/<rid>.log): spans,
  gates, statuses, reasons. Never hand-written.
- CONTEXT the ledger does not yet record (model, PR, lane, labels, incidents,
  waves) rides an overlay JSON, declared, visible, and replaced by the trace
  spine (ID-423) as those dims start being recorded.

  build --rids r1,r2,... [--overlay overlay.json] [--out report.html]

Zero JS output: pure HTML/CSS, tooltips via title attributes.
"""

import argparse
import datetime
import html as H
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from events import resolve_run  # noqa: E402

PHASE_ORDER = ["grill", "think", "design", "design-critique", "ui-design", "spec",
               "validate", "design-record", "test-plan", "build", "review", "docs",
               "ship", "reflect"]
CELL = {"pass": "●", "skip": "○", "override": "⚑"}


def run_summary(path, rid=None):
    """Facts for one rid straight from its ledger: span + last-status per gate."""
    import datetime as dtm
    rid = rid or Path(path).stem
    gates, first_ts, last_ts = {}, None, None
    meta = {}
    for line in Path(path).read_text().splitlines():
        parts = [p.strip() for p in line.split(" | ", 3)]
        if len(parts) < 3:
            continue
        try:
            ts = dtm.datetime.fromisoformat(parts[0].replace("Z", "+00:00"))
        except ValueError:
            continue
        first_ts, last_ts = first_ts or ts, ts
        if parts[1] == "START":
            for tok in parts[2].split():
                k, _, v = tok.partition("=")
                meta.setdefault(k, v)
        elif parts[1] == "GATE" and len(parts) == 4:
            status, _, reason = parts[3].partition(" | ")
            status = {"ran": "pass", "skipped": "skip", "override": "override"}.get(status.strip(), "pass")
            gates[parts[2]] = (status, reason.strip())
    return {"rid": rid, "t0": first_ts, "t1": last_ts, "gates": gates, "meta": meta}


STYLE = """<style>
:root{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;--accent:#4f46e5;
--card:#ffffff;--warn:#d97706;--pass:#16a34a;--fail:#dc2626;--passbg:#dcfce7;--failbg:#fee2e2}
@media(prefers-color-scheme:dark){:root{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;
--muted:#9ca3af;--accent:#818cf8;--card:#1f2937;--warn:#fbbf24;--pass:#4ade80;
--fail:#f87171;--passbg:#14532d;--failbg:#7f1d1d}}
:root[data-theme=dark]{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;--muted:#9ca3af;
--accent:#818cf8;--card:#1f2937;--warn:#fbbf24;--pass:#4ade80;--fail:#f87171;
--passbg:#14532d;--failbg:#7f1d1d}
:root[data-theme=light]{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;
--accent:#4f46e5;--card:#ffffff;--warn:#d97706;--pass:#16a34a;--fail:#dc2626;
--passbg:#dcfce7;--failbg:#fee2e2}
body{font-family:system-ui,sans-serif;background:var(--bg);color:var(--fg);
max-width:1100px;margin:1.5rem auto;padding:0 1rem;line-height:1.5}
h1{font-size:1.2rem}h2{font-size:1rem;margin-top:2rem}
.meta,figcaption{color:var(--muted);font-size:.85rem;max-width:75ch}
code{font-family:ui-monospace,monospace;font-size:.9em}
.stats{display:flex;flex-wrap:wrap;gap:.6rem;margin:.8rem 0}
.stat{border:1px solid var(--line);border-radius:8px;background:var(--card);
padding:.45rem .9rem;font-size:.85rem}
.stat b{display:block;font-size:1.05rem;font-variant-numeric:tabular-nums}
.tl{border:1px solid var(--line);border-radius:8px;background:var(--card);
padding:.6rem .9rem;margin:.8rem 0;overflow-x:auto}
.lane{font-size:.75rem;text-transform:uppercase;letter-spacing:.05em;
color:var(--muted);margin:.5rem 0 .15rem}
.row{display:grid;grid-template-columns:11rem 1fr 9rem;align-items:center;
gap:.6rem;font-size:.82rem;padding:.12rem 0}
.row .name{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.row .track{position:relative;height:.95rem;background:
color-mix(in srgb,var(--line) 30%,transparent);border-radius:4px}
.row .bar{position:absolute;top:0;bottom:0;border-radius:4px;min-width:4px}
.row .tail{color:var(--muted);font-variant-numeric:tabular-nums;white-space:nowrap}
.m-sonnet{background:var(--accent)}
.m-opus{background:var(--warn)}
.m-unknown{background:color-mix(in srgb,var(--muted) 60%,transparent)}
.legend{display:flex;gap:1rem;font-size:.78rem;color:var(--muted);margin:.3rem 0}
.legend i{display:inline-block;width:.9rem;height:.6rem;border-radius:3px;
vertical-align:baseline;margin-right:.3rem}
.mins .row{grid-template-columns:8rem 1fr 11rem}
table{border-collapse:collapse;margin:.75rem 0;font-variant-numeric:tabular-nums}
th,td{border:1px solid var(--line);padding:.3rem .55rem;font-size:.82rem;text-align:left}
th{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em}
td.c{text-align:center;cursor:default}
td.c.pass{color:var(--pass)}td.c.skip{color:var(--muted)}
td.c.override{color:var(--warn)}td.c.absent{color:var(--line)}
.wave td.state-dispatched{color:var(--accent);font-weight:600}
.wave td.state-queued{color:var(--muted)}
.wave td.state-hold{color:var(--warn)}
ol.inc{font-size:.87rem;max-width:80ch}
ol.inc b{display:inline}
.gap{border-left:3px solid var(--warn);padding:.4rem .8rem;background:var(--card);
font-size:.85rem;margin:.8rem 0;max-width:80ch}
</style>"""


def _fmt_t(ts):
    return ts.astimezone().strftime("%H:%M") if ts else "?"


def _mins(run):
    if run["t0"] and run["t1"]:
        return max(0.1, (run["t1"] - run["t0"]).total_seconds() / 60)
    return 0


def render(runs, overlay, out):
    ov_runs = overlay.get("runs", {})
    t0s = [r["t0"] for r in runs if r["t0"]]
    t1s = [r["t1"] for r in runs if r["t1"]]
    lo, hi = min(t0s), max(t1s)
    span = max(1.0, (hi - lo).total_seconds())

    def pct(ts):
        return 100 * (ts - lo).total_seconds() / span

    lanes = {}
    for r in runs:
        o = ov_runs.get(r["rid"], {})
        lanes.setdefault(o.get("lane", "runs"), []).append((r, o))

    tl = ""
    for lane, rows in lanes.items():
        tl += f'<div class="lane">{H.escape(lane)}</div>'
        for r, o in sorted(rows, key=lambda x: x[0]["t0"] or lo):
            model = o.get("model", "unknown")
            g = r["gates"]
            counts = f"{sum(1 for s, _ in g.values() if s == 'pass')}● {sum(1 for s, _ in g.values() if s == 'skip')}○ {sum(1 for s, _ in g.values() if s == 'override')}⚑"
            tip = (f"{r['rid']} · {_fmt_t(r['t0'])}-{_fmt_t(r['t1'])} · {_mins(r):.0f} min · "
                   f"model {model} · gates {counts}")
            left, width = pct(r["t0"]), max(0.5, pct(r["t1"]) - pct(r["t0"]))
            tl += (f'<div class="row"><span class="name" title="{H.escape(r["rid"])}">'
                   f'{H.escape(o.get("label", r["rid"]))}</span>'
                   f'<span class="track"><span class="bar m-{model}" title="{H.escape(tip)}" '
                   f'style="left:{left:.2f}%;width:{width:.2f}%"></span></span>'
                   f'<span class="tail">{_fmt_t(r["t0"])}-{_fmt_t(r["t1"])} · {H.escape(o.get("pr", ""))}</span></div>')

    by_model = {}
    for r in runs:
        m = ov_runs.get(r["rid"], {}).get("model", "unknown")
        by_model.setdefault(m, [0, 0])
        by_model[m][0] += _mins(r)
        by_model[m][1] += 1
    tot = sum(v[0] for v in by_model.values()) or 1
    mins = "".join(
        f'<div class="row"><span class="name">{H.escape(m)}</span>'
        f'<span class="track"><span class="bar m-{m}" style="left:0;width:{100 * v[0] / tot:.1f}%"></span></span>'
        f'<span class="tail">{v[0]:.0f} min ({100 * v[0] / tot:.0f}%) · {v[1]} runs</span></div>'
        for m, v in sorted(by_model.items(), key=lambda kv: -kv[1][0]))

    phases = [p for p in PHASE_ORDER if any(p in r["gates"] for r in runs)]
    phases += sorted({p for r in runs for p in r["gates"]} - set(phases))
    head = "<tr><th>run</th>" + "".join(f"<th>{p[:2]}</th>" for p in phases) + "</tr>"
    body = ""
    for r in runs:
        o = ov_runs.get(r["rid"], {})
        cells = ""
        for p in phases:
            if p in r["gates"]:
                s, reason = r["gates"][p]
                cells += f'<td class="c {s}" title="{H.escape(p)}: {s} · {H.escape(reason)}">{CELL[s]}</td>'
            else:
                cells += f'<td class="c absent" title="{H.escape(p)}: not recorded">−</td>'
        body += f'<tr><td>{H.escape(o.get("label", r["rid"]))}</td>{cells}</tr>'
    key = " · ".join(f"{p[:2]}={p}" for p in phases)

    waves = ""
    if overlay.get("waves"):
        w = overlay["waves"]
        rows = "".join(
            f'<tr><td>{H.escape(x["name"])}</td><td>{H.escape(x.get("model", ""))}</td>'
            f'<td class="state-{x.get("state", "queued").split()[0]}">{H.escape(x.get("state", ""))}</td>'
            f'<td>{H.escape(x.get("spec", ""))}</td><td>{H.escape(x.get("note", ""))}</td></tr>'
            for x in w["rows"])
        waves = (f'<h2>Wave board · {H.escape(w.get("title", ""))}</h2>'
                 f'<p class="meta">{H.escape(w.get("caption", ""))}</p>'
                 f'<table class="wave"><tr><th>sub-goal</th><th>model</th><th>state</th>'
                 f"<th>spec</th><th>note</th></tr>{rows}</table>")

    incidents = ""
    if overlay.get("incidents"):
        items = "".join(f"<li><b>{H.escape(i['label'])}:</b> {H.escape(i['detail'])}</li>"
                        for i in overlay["incidents"])
        incidents = f'<h2>Incidents &amp; lessons</h2><ol class="inc">{items}</ol>'

    gaps = ""
    if overlay.get("not_in_ledger"):
        gaps = (f'<div class="gap"><b>Not in the ledgers:</b> '
                f"{H.escape(overlay['not_in_ledger'])}</div>")

    ng = sum(len(r["gates"]) for r in runs)
    title = overlay.get("title", "run report")
    Path(out).write_text(f"""<title>bench · control-plane report</title>
{STYLE}
<h1>Run report · {H.escape(title)}</h1>
<p class="meta">Facts (spans, gates, statuses, reasons) are read from the kit's
append-only run ledgers; model / PR / lane context is declared overlay until the
trace spine records it. Hover any bar or matrix cell for its detail and reason.</p>
<div class="stats">
<div class="stat"><b>{len(runs)}</b>workers</div>
<div class="stat"><b>{_fmt_t(lo)}-{_fmt_t(hi)}</b>wall span</div>
<div class="stat"><b>{tot:.0f} min</b>worker minutes</div>
<div class="stat"><b>{ng}</b>gate records</div>
</div>
<h2>Timeline</h2>
<div class="legend"><span><i class="m-sonnet"></i>sonnet</span>
<span><i class="m-opus"></i>opus</span><span><i class="m-unknown"></i>unrecorded</span></div>
<div class="tl">{tl}</div>
<h2>Worker minutes by model</h2>
<div class="tl mins">{mins}</div>
<h2>Gate coverage (● recorded · ○ skipped-with-reason · ⚑ override · − not recorded)</h2>
<table>{head}{body}</table>
<figcaption>{key}</figcaption>
{gaps}{waves}{incidents}
<p class="meta">Generated {datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
· reproduce: <code>python3 report.py build --rids {",".join(r["rid"] for r in runs)}</code></p>""")
    print(f"report written to {out} ({len(runs)} runs)", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(prog="bench-report", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="render a control-plane report from run ledgers")
    b.add_argument("--rids", required=True, help="comma-separated rids or ledger paths")
    b.add_argument("--overlay", help="JSON with runs{rid:{lane,model,pr,label}}, waves, incidents")
    b.add_argument("--out", default="report.html")
    a = ap.parse_args()
    overlay = json.loads(Path(a.overlay).read_text()) if a.overlay else {}
    runs = [run_summary(resolve_run(r.strip())) for r in a.rids.split(",")]
    render(runs, overlay, a.out)


if __name__ == "__main__":
    main()
