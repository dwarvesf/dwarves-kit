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
        Path(a.html).write_text(render_html(rows, summary))
        print(f"scoreboard written to {a.html}", file=sys.stderr)


def render_html(rows, summary):
    suite = rows[0]["suite"] if rows else "?"
    shash = rows[0]["suite_hash"] if rows else "?"
    tasks = sorted({r["task"] for r in rows})
    configs = sorted({(r["model"], r["executor"]) for r in rows})
    cell = {}
    for r in rows:
        cell.setdefault((r["task"], r["model"], r["executor"]), []).append(r)

    def td(task, model, executor):
        rs = cell.get((task, model, executor))
        if not rs:
            return "<td>-</td>"
        p = sum(r["pass"] for r in rs)
        cls = "pass" if p == len(rs) else ("mixed" if p else "fail")
        detail = ", ".join(f"{r['tests_passed']}/{r['tests_total']}" for r in rs)
        cost = sum(r["cost_usd"] or 0 for r in rs)
        return f'<td class="{cls}">{p}/{len(rs)} <small>{detail} · ${cost:.3f}</small></td>'

    matrix = "".join(
        f"<tr><th>{t}</th>" + "".join(td(t, m, e) for m, e in configs) + "</tr>" for t in tasks)
    sm = "".join(
        f"<tr><td>{s['model']}</td><td>{s['executor']}</td><td>{s['cells']}</td>"
        f"<td>{s['first_pass_yield']}</td><td>{s['cost_per_task']}</td>"
        f"<td>{s['wall_s_per_task']}</td><td>{s['errors']}</td></tr>" for s in summary)
    return f"""<title>bench · {suite}@{shash}</title>
<style>
:root{{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;
--pass:#dcfce7;--fail:#fee2e2;--mixed:#fef9c3}}
@media(prefers-color-scheme:dark){{:root{{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;
--muted:#9ca3af;--pass:#14532d;--fail:#7f1d1d;--mixed:#713f12}}}}
:root[data-theme=dark]{{--bg:#111827;--fg:#f3f4f6;--line:#9ca3af44;--muted:#9ca3af;
--pass:#14532d;--fail:#7f1d1d;--mixed:#713f12}}
:root[data-theme=light]{{--bg:#fafafa;--fg:#111827;--line:#37415155;--muted:#6b7280;
--pass:#dcfce7;--fail:#fee2e2;--mixed:#fef9c3}}
body{{font-family:system-ui,sans-serif;background:var(--bg);color:var(--fg);
max-width:960px;margin:2rem auto;padding:0 1rem;line-height:1.5}}
h1{{font-size:1.25rem;text-wrap:balance}}h2{{font-size:1rem;margin-top:2rem}}
code{{font-family:ui-monospace,monospace}}
table{{border-collapse:collapse;margin:.75rem 0;width:100%;font-variant-numeric:tabular-nums}}
th,td{{border:1px solid var(--line);padding:.4rem .6rem;text-align:left;font-size:.9rem}}
th{{font-size:.75rem;text-transform:uppercase;letter-spacing:.04em}}
td.pass{{background:var(--pass)}}td.fail{{background:var(--fail)}}td.mixed{{background:var(--mixed)}}
small{{color:var(--muted)}}p{{color:var(--muted);font-size:.85rem}}
</style>
<h1>bench scoreboard · suite <code>{suite}</code> @ <code>{shash}</code></h1>
<p>{len(rows)} cells. Generated {datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')}.</p>
<h2>Summary per config</h2>
<table><tr><th>model</th><th>executor</th><th>cells</th><th>first-pass yield</th>
<th>$/task</th><th>s/task</th><th>errors</th></tr>{sm}</table>
<h2>Task matrix (pass / runs · tests · cost)</h2>
<table><tr><th>task</th>{"".join(f"<th>{m}<br><small>{e}</small></th>" for m, e in configs)}</tr>
{matrix}</table>"""


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
    d.set_defaults(fn=cmd_render)
    f = sub.add_parser("diff", help="baseline vs candidate, exit 1 on regression")
    f.add_argument("--baseline", required=True)
    f.add_argument("--candidate", required=True)
    f.set_defaults(fn=cmd_diff)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
