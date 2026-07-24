#!/usr/bin/env python3
"""bench: standalone comparative benchmark runner (the kit's bench plane).

Replays a frozen, hashed task suite under a config matrix (model x executor),
scores each cell with the task's own check script, and appends one immutable
JSONL row per cell: suite_hash x config x outcome. Comparison across models,
tools, or workflows is then a GROUP BY over one fact table.

Standalone by design (PHILOSOPHY N4): stdlib only, no kit required. With the
kit present, rows carry kit_version so bench data joins the wider ledgers.

Verbs:
  run    --suite DIR --models a,b [--executors model,agent] [--repeats N] [--out F]
  render RUNS.jsonl [--html OUT.html]
  diff   --baseline OLD.jsonl --candidate NEW.jsonl

Row schema (see docs/METRICS.md for the metric contract built on top):
  ts, suite, suite_hash, task, model, executor, repeat, kit_version, session_id,
  pass, tests_passed, tests_total, duration_s, model_duration_s, cost_usd,
  turns, tokens_in, tokens_out, error
"""

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL_TIMEOUT_S = 600
AGENT_TIMEOUT_S = 900
CHECK_TIMEOUT_S = 60


def load_suite(suite_dir: Path):
    meta = json.loads((suite_dir / "suite.json").read_text())
    tasks = {}
    for tid in meta["tasks"]:
        tdir = suite_dir / "tasks" / tid
        tasks[tid] = {
            "prompt": (tdir / "task.md").read_text(),
            "check": (tdir / "check.py").read_text(),
        }
    return meta, tasks


def suite_hash(suite_dir: Path) -> str:
    """Content hash over suite.json + every task file, path-sorted, so a
    baseline is only comparable to runs of the byte-identical suite."""
    h = hashlib.sha256()
    for p in sorted(suite_dir.rglob("*")):
        if p.is_file() and "__pycache__" not in p.parts:
            h.update(p.relative_to(suite_dir).as_posix().encode())
            h.update(p.read_bytes())
    return h.hexdigest()[:12]


def kit_version():
    for parent in HERE.parents:
        v = parent / "VERSION"
        if v.is_file():
            return v.read_text().strip()
    return None


def strip_fences(text: str) -> str:
    """Models fence code despite instructions; take the largest fenced block
    if any, else the raw text."""
    blocks = re.findall(r"```(?:\w+)?\n(.*?)```", text, re.DOTALL)
    return max(blocks, key=len) if blocks else text


def parse_check_output(out: str):
    m = re.search(r"PASSED (\d+)/(\d+)", out)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


def claude_json(args, cwd, timeout):
    proc = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"claude exit {proc.returncode}: {proc.stderr[:300] or proc.stdout[:300]}")


def run_cell(cell, claude_bin):
    """Execute one (task, model, executor, repeat) cell in an isolated temp
    dir and return its row. check.py is copied in only AFTER the agent run so
    the executor can never read the verifier (anti-overfit)."""
    row = {
        "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "suite": cell["suite"], "suite_hash": cell["suite_hash"],
        "task": cell["task"], "model": cell["model"], "executor": cell["executor"],
        "repeat": cell["repeat"], "kit_version": cell["kit_version"], "session_id": None,
        "pass": False, "tests_passed": 0, "tests_total": 0,
        "duration_s": None, "model_duration_s": None, "cost_usd": None,
        "turns": None, "tokens_in": None, "tokens_out": None, "error": None,
        "fail_detail": None,
    }
    t0 = datetime.datetime.now()
    tmp = Path(tempfile.mkdtemp(prefix=f"bench-{cell['task']}-"))
    try:
        if cell["executor"] == "model":
            prompt = cell["prompt"] + (
                "\n\nOutput ONLY the Python module code for solution.py. "
                "No markdown fences, no prose, no explanation."
            )
            res = claude_json([claude_bin, "-p", prompt, "--model", cell["model"],
                               "--output-format", "json"], tmp, MODEL_TIMEOUT_S)
            (tmp / "solution.py").write_text(strip_fences(res.get("result") or ""))
        else:  # agent: full tool-using run inside the cell dir
            (tmp / "task.md").write_text(cell["prompt"])
            res = claude_json([claude_bin, "-p",
                               "Read task.md and write solution.py in the current directory "
                               "implementing it. Do not create any other files.",
                               "--model", cell["model"], "--output-format", "json",
                               "--permission-mode", "acceptEdits"], tmp, AGENT_TIMEOUT_S)
        row["session_id"] = res.get("session_id")
        row["cost_usd"] = res.get("total_cost_usd")
        row["turns"] = res.get("num_turns")
        if isinstance(res.get("duration_ms"), (int, float)):
            row["model_duration_s"] = round(res["duration_ms"] / 1000, 1)
        usage = res.get("usage") or {}
        row["tokens_in"] = usage.get("input_tokens")
        row["tokens_out"] = usage.get("output_tokens")

        (tmp / "check.py").write_text(cell["check"])
        chk = subprocess.run([sys.executable, "check.py"], cwd=tmp,
                             capture_output=True, text=True, timeout=CHECK_TIMEOUT_S)
        row["tests_passed"], row["tests_total"] = parse_check_output(chk.stdout)
        row["pass"] = chk.returncode == 0 and row["tests_total"] > 0
        fails = [l for l in chk.stdout.splitlines() if l.startswith("FAIL")]
        if fails:  # failure fingerprint: same detail across configs points at the suite, not the model
            row["fail_detail"] = " | ".join(fails[:3])[:400]
        elif row["tests_total"] == 0:  # check crashed before scoring (bad import/syntax): keep the crash
            row["fail_detail"] = (chk.stderr.strip().splitlines() or ["check produced no output"])[-1][:400]
    except Exception as e:  # a failed cell is a row, never a crashed matrix
        row["error"] = f"{type(e).__name__}: {e}"[:300]
    finally:
        row["duration_s"] = round((datetime.datetime.now() - t0).total_seconds(), 1)
        shutil.rmtree(tmp, ignore_errors=True)
    return row


def cmd_run(a):
    suite_dir = Path(a.suite)
    meta, tasks = load_suite(suite_dir)
    sh = suite_hash(suite_dir)
    kv = kit_version()
    cells = [
        {"suite": meta["name"], "suite_hash": sh, "kit_version": kv,
         "task": tid, "prompt": t["prompt"], "check": t["check"],
         "model": m, "executor": e, "repeat": r}
        for tid, t in tasks.items()
        for m in a.models.split(",")
        for e in a.executors.split(",")
        for r in range(a.repeats)
    ]
    print(f"suite={meta['name']} hash={sh} cells={len(cells)} jobs={a.jobs}", file=sys.stderr)
    out = Path(a.out)
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool, out.open("a") as f:
        for row in pool.map(lambda c: run_cell(c, a.claude_bin), cells):
            f.write(json.dumps(row) + "\n")
            f.flush()
            mark = "PASS" if row["pass"] else "FAIL"
            print(f"  {mark} {row['task']} {row['model']}/{row['executor']} "
                  f"{row['tests_passed']}/{row['tests_total']} "
                  f"{row['duration_s']}s ${row['cost_usd']} {row['error'] or ''}", file=sys.stderr)
    print(f"rows appended to {out}", file=sys.stderr)


def load_rows(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]


def summarize(rows):
    """Group rows by (model, executor) into the headline KPIs."""
    groups = {}
    for r in rows:
        groups.setdefault((r["model"], r["executor"]), []).append(r)
    out = []
    for (model, executor), rs in sorted(groups.items()):
        n = len(rs)
        costs = [r["cost_usd"] for r in rs if r["cost_usd"] is not None]
        durs = [r["duration_s"] for r in rs if r["duration_s"] is not None]
        out.append({
            "model": model, "executor": executor, "cells": n,
            "first_pass_yield": round(sum(r["pass"] for r in rs) / n, 2),
            "cost_per_task": round(sum(costs) / len(costs), 4) if costs else None,
            "wall_s_per_task": round(sum(durs) / len(durs), 1) if durs else None,
            "errors": sum(1 for r in rs if r["error"]),
        })
    return out


def cmd_render(a):
    rows = load_rows(a.runs)
    summary = summarize(rows)
    hdr = f"{'model':<12} {'executor':<9} {'cells':>5} {'yield':>6} {'$/task':>8} {'s/task':>7} {'err':>4}"
    print(hdr + "\n" + "-" * len(hdr))
    for s in summary:
        print(f"{s['model']:<12} {s['executor']:<9} {s['cells']:>5} {s['first_pass_yield']:>6} "
              f"{s['cost_per_task'] if s['cost_per_task'] is not None else '-':>8} "
              f"{s['wall_s_per_task'] if s['wall_s_per_task'] is not None else '-':>7} {s['errors']:>4}")
    if a.html:
        tasks_md = {}
        if a.suite:
            _, tasks = load_suite(Path(a.suite))
            tasks_md = {tid: t["prompt"] for tid, t in tasks.items()}
        Path(a.html).write_text(render_html(rows, summary, tasks_md))
        print(f"scoreboard written to {a.html}", file=sys.stderr)


STYLE = """<style>
:root{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;--accent:#4f46e5;
--card:#ffffff;--pass:#dcfce7;--fail:#fee2e2;--mixed:#fef9c3}
@media(prefers-color-scheme:dark){:root{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;
--muted:#9ca3af;--accent:#818cf8;--card:#1f2937;--pass:#14532d;--fail:#7f1d1d;--mixed:#713f12}}
:root[data-theme=dark]{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;--muted:#9ca3af;
--accent:#818cf8;--card:#1f2937;--pass:#14532d;--fail:#7f1d1d;--mixed:#713f12}
:root[data-theme=light]{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;
--accent:#4f46e5;--card:#ffffff;--pass:#dcfce7;--fail:#fee2e2;--mixed:#fef9c3}
body{font-family:system-ui,sans-serif;background:var(--bg);color:var(--fg);
max-width:960px;margin:2rem auto;padding:0 1rem;line-height:1.55}
h1{font-size:1.3rem;text-wrap:balance}h2{font-size:1.05rem;margin-top:2.2rem}
code{font-family:ui-monospace,monospace;font-size:.9em}
p.lede{font-size:1rem;max-width:65ch}
p.note,figcaption{color:var(--muted);font-size:.85rem;max-width:70ch}
table{border-collapse:collapse;margin:.75rem 0;width:100%;font-variant-numeric:tabular-nums}
th,td{border:1px solid var(--line);padding:.45rem .6rem;text-align:left;font-size:.9rem}
th{font-size:.72rem;text-transform:uppercase;letter-spacing:.05em}
td.pass{background:var(--pass)}td.fail{background:var(--fail)}td.mixed{background:var(--mixed)}
td a{color:inherit;text-decoration:underline dotted;text-underline-offset:3px}
small{color:var(--muted)}
.pipe{display:flex;flex-wrap:wrap;gap:.6rem;align-items:stretch;margin:1rem 0}
.pipe .box{flex:1 1 12rem;border:1px solid var(--line);border-radius:6px;
padding:.6rem .8rem;font-size:.85rem;background:var(--card)}
.pipe .box b{display:block;font-size:.72rem;text-transform:uppercase;
letter-spacing:.05em;margin-bottom:.25rem;color:var(--muted)}
.pipe .sut{border:2px solid var(--accent)}
.pipe .sut b{color:var(--accent)}
.arrow{align-self:center;color:var(--muted)}
details{border:1px solid var(--line);border-radius:6px;padding:.5rem .8rem;margin:.5rem 0;
background:var(--card)}
details summary{cursor:pointer;font-size:.9rem}
details pre{overflow-x:auto;font-size:.8rem;line-height:1.45;padding:.5rem;margin:.5rem 0 0}
dl.legend{font-size:.85rem;display:grid;grid-template-columns:max-content 1fr;
gap:.15rem 1rem;margin:.5rem 0}
dl.legend dt{font-weight:600}dl.legend dd{margin:0;color:var(--muted)}
.callout{border-left:3px solid var(--accent);padding:.5rem .9rem;margin:1rem 0;
background:var(--card);font-size:.9rem;max-width:75ch}
.cell-card{border:1px solid var(--line);border-radius:6px;background:var(--card);
padding:.6rem .9rem;margin:.6rem 0;font-size:.88rem}
.cell-card h3{font-size:.9rem;margin:.1rem 0 .4rem}
.cell-card .fd{font-family:ui-monospace,monospace;font-size:.78rem;overflow-x:auto;
display:block;white-space:pre;padding:.4rem;border:1px dashed var(--line);margin-top:.4rem}
.badge{display:inline-block;border-radius:99px;padding:.05rem .6rem;font-size:.75rem;
font-weight:600}
.badge.ok{background:var(--pass)}.badge.bad{background:var(--fail)}
pre.repro{overflow-x:auto;border:1px solid var(--line);border-radius:6px;
padding:.6rem .8rem;font-size:.8rem;background:var(--card)}
</style>"""


def _sig(md):
    """First signature-looking line of a task.md, as its one-line summary."""
    for line in md.splitlines():
        s = line.strip()
        if "(" in s and ")" in s and "->" in s:
            return s
    lines = [l.strip() for l in md.strip().splitlines() if l.strip()]
    return lines[0] if lines else ""


def render_html(rows, summary, tasks_md=None):
    import html as H

    tasks_md = tasks_md or {}
    suite = rows[0]["suite"] if rows else "?"
    shash = rows[0]["suite_hash"] if rows else "?"
    tasks = sorted({r["task"] for r in rows})
    models = sorted({r["model"] for r in rows})
    configs = sorted({(r["model"], r["executor"]) for r in rows})
    cell = {}
    for r in rows:
        cell.setdefault((r["task"], r["model"], r["executor"]), []).append(r)

    def cid(t, m, e):
        return f"d-{t}-{m}-{e}"

    # -- section: what was tested (pipeline figure) --
    ntests = {t: max((r["tests_total"] for r in rows if r["task"] == t), default=0) for t in tasks}
    pipe = f"""<figure>
<div class="pipe">
<div class="box"><b>Pinned: frozen task suite</b>{len(tasks)} tasks, content-hash
<code>{shash}</code>. Same bytes for every contender, forever comparable.</div>
<div class="arrow">→</div>
<div class="box sut"><b>Varied: system under test</b>Model ({", ".join(models)}) ×
workflow ({", ".join(sorted({e for _, e in configs}))}). The ONLY thing that changes
between columns.</div>
<div class="arrow">→</div>
<div class="box"><b>Pinned: hidden checks</b>Hand-written expected answers
({sum(ntests.values())} cases total), kept out of the sandbox until the attempt is
done, so nothing can study for the test.</div>
<div class="arrow">→</div>
<div class="box"><b>Output: immutable rows</b>One JSON row per attempt: passed?,
cases passed, cost, time. Never edited; a correction is a new run.</div>
</div>
<figcaption>Everything except the highlighted box is pinned, so any difference in
the numbers below is attributable to the model or workflow, not to luck or a moving
target.</figcaption></figure>"""

    # -- section: the tasks themselves --
    task_details = ""
    for t in tasks:
        md = tasks_md.get(t, "")
        sig = H.escape(_sig(md)) if md else ""
        body = f"<pre>{H.escape(md)}</pre>" if md else "<p class=note>Task text not bundled; re-render with --suite to include it.</p>"
        task_details += (f"<details><summary><code>{t}</code>"
                         f"{' · <code>' + sig + '</code>' if sig else ''}"
                         f" · {ntests[t]} hidden checks</summary>{body}</details>")

    # -- section: configs legend --
    exec_legend = {
        "model": "one bare completion, no tools: measures the raw model",
        "agent": "a full tool-using Claude Code run in a sandbox dir: measures the model inside a workflow",
    }
    cfg_rows = "".join(
        f"<tr><td><code>{m}</code></td><td><code>{e}</code></td>"
        f"<td>{exec_legend.get(e, '')}</td></tr>" for m, e in configs)

    # -- results tables --
    sm = "".join(
        f"<tr><td><code>{s['model']}</code></td><td><code>{s['executor']}</code></td><td>{s['cells']}</td>"
        f"<td>{s['first_pass_yield']}</td><td>{s['cost_per_task']}</td>"
        f"<td>{s['wall_s_per_task']}</td><td>{s['errors']}</td></tr>" for s in summary)

    def td(t, m, e):
        rs = cell.get((t, m, e))
        if not rs:
            return "<td>-</td>"
        p = sum(r["pass"] for r in rs)
        cls = "pass" if p == len(rs) else ("mixed" if p else "fail")
        detail = ", ".join(f"{r['tests_passed']}/{r['tests_total']}" for r in rs)
        return (f'<td class="{cls}"><a href="#{cid(t, m, e)}">{p}/{len(rs)}</a> '
                f"<small>{detail} cases</small></td>")

    matrix = "".join(
        f"<tr><th><code>{t}</code></th>" + "".join(td(t, m, e) for m, e in configs) + "</tr>"
        for t in tasks)

    # -- shared-failure callout: identical fingerprint across all configs of a task --
    callouts = ""
    for t in tasks:
        fds = [r.get("fail_detail") for (tt, _, _), rs in cell.items() if tt == t for r in rs]
        if len(fds) >= 2 and all(fds) and len(set(fds)) == 1:
            callouts += (f'<div class="callout"><b>Every config missed the same case on '
                         f"<code>{t}</code>.</b> Zero variance across contenders means either a "
                         f"shared blind spot or a suite problem; read the case and judge:"
                         f'<span class="fd">{H.escape(fds[0])}</span></div>')

    # -- drill-down cards --
    cards = ""
    for t in tasks:
        for m, e in configs:
            for r in cell.get((t, m, e), []):
                badge = '<span class="badge ok">passed</span>' if r["pass"] else '<span class="badge bad">failed</span>'
                fd = r.get("fail_detail")
                fd_html = f'<span class="fd">{H.escape(fd)}</span>' if fd else ""
                tok = (f" · {r['tokens_in']}/{r['tokens_out']} tok"
                       if r.get("tokens_in") is not None else "")
                cards += (f'<div class="cell-card" id="{cid(t, m, e)}"><h3><code>{t}</code> · '
                          f"<code>{m}/{e}</code> {badge}</h3>"
                          f"{r['tests_passed']}/{r['tests_total']} cases · "
                          f"${r['cost_usd']} · {r['duration_s']}s wall{tok}{fd_html}</div>")

    ts = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    return f"""<title>bench · {suite}@{shash}</title>
{STYLE}
<h1>bench scoreboard · suite <code>{suite}</code> @ <code>{shash}</code></h1>
<p class="lede">Every number here answers one question: <em>given the exact same frozen
tasks and the exact same hidden checks, how do different models and workflows compare?</em>
{len(rows)} attempts recorded {ts}.</p>

<h2>1 · What was tested</h2>
{pipe}

<h2>2 · The tasks (click to read the actual prompt)</h2>
{task_details}

<h2>3 · The contenders</h2>
<table><tr><th>model</th><th>workflow</th><th>meaning</th></tr>{cfg_rows}</table>

<h2>4 · Results per contender</h2>
<table><tr><th>model</th><th>workflow</th><th>attempts</th><th>first-pass yield</th>
<th>$/task</th><th>s/task</th><th>harness errors</th></tr>{sm}</table>
<dl class="legend">
<dt>first-pass yield</dt><dd>share of tasks fully passed on the first attempt, no retries, no human help; the headline quality number</dd>
<dt>$/task</dt><dd>average API cost per attempt; quality per dollar is the routing decision</dd>
<dt>s/task</dt><dd>average wall-clock seconds per attempt</dd>
<dt>harness errors</dt><dd>attempts that broke in the harness itself (not counted as task failures)</dd>
</dl>

<h2>5 · Task × contender matrix (click a cell for its detail)</h2>
<table><tr><th>task</th>{"".join(f"<th><code>{m}</code><br><small>{e}</small></th>" for m, e in configs)}</tr>
{matrix}</table>
{callouts}

<h2>6 · Attempt details</h2>
{cards}

<h2>7 · Reproduce this page</h2>
<pre class="repro">python3 bench.py run --suite suites/{suite} --models {",".join(models)} --out runs.jsonl
python3 bench.py render runs.jsonl --suite suites/{suite} --html scoreboard.html</pre>
<p class="note">Rows are append-only evidence: the same suite hash re-run later lands new
rows next to these, and <code>bench diff</code> reports exactly what got better or worse.</p>"""


def cmd_diff(a):
    def key(r):
        return (r["task"], r["model"], r["executor"])

    base = {key(r): r for r in load_rows(a.baseline)}
    cand = {key(r): r for r in load_rows(a.candidate)}
    bh = {r["suite_hash"] for r in base.values()}
    ch = {r["suite_hash"] for r in cand.values()}
    if bh != ch:
        print(f"WARNING: suite hashes differ ({bh} vs {ch}); comparison is not valid", file=sys.stderr)
    regressions = 0
    for k in sorted(set(base) | set(cand)):
        b, c = base.get(k), cand.get(k)
        if b is None or c is None:
            print(f"  {'/'.join(k)}: only in {'candidate' if b is None else 'baseline'}")
            continue
        if b["pass"] != c["pass"]:
            word = "FIXED" if c["pass"] else "REGRESSED"
            regressions += not c["pass"]
            print(f"  {word} {'/'.join(k)}")
        dc = (c["cost_usd"] or 0) - (b["cost_usd"] or 0)
        if abs(dc) > 0.001:
            print(f"  cost {'/'.join(k)}: {'+' if dc > 0 else ''}{dc:.4f} USD")
    print(f"{regressions} regression(s)")
    sys.exit(1 if regressions else 0)


def main():
    ap = argparse.ArgumentParser(prog="bench", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="replay a suite under a config matrix")
    r.add_argument("--suite", required=True)
    r.add_argument("--models", required=True, help="comma-separated model names")
    r.add_argument("--executors", default="model", help="model,agent")
    r.add_argument("--repeats", type=int, default=1, help=">1 measures flake rate")
    r.add_argument("--jobs", type=int, default=4)
    r.add_argument("--out", default="runs.jsonl")
    r.add_argument("--claude-bin", default="claude")
    r.set_defaults(fn=cmd_run)
    d = sub.add_parser("render", help="scoreboard from a runs file")
    d.add_argument("runs")
    d.add_argument("--html")
    d.add_argument("--suite", help="suite dir; bundles task prompts into the HTML")
    d.set_defaults(fn=cmd_render)
    f = sub.add_parser("diff", help="baseline vs candidate, exit 1 on regression")
    f.add_argument("--baseline", required=True)
    f.add_argument("--candidate", required=True)
    f.set_defaults(fn=cmd_diff)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
