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
import re
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
            "session": f.stem[:8], "project": "-".join(f.parent.name.split("-")[-2:]),
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
    conf_day = Counter(r["t1"].date() for r in w
                       if r["conformance"] and r["conformance"][0] == r["conformance"][1])
    m["trend_conf"] = [conf_day.get(d, 0) for d in days]
    weeks = {}
    for r in w:
        if not r["meta"].get("lane"):
            continue
        wk = r["t1"].date().isocalendar()
        key = f"{wk[0]}-W{wk[1]:02d}"
        weeks.setdefault(key, Counter())[r["meta"]["lane"]] += 1
    m["lane_weeks"] = [(k, dict(v)) for k, v in sorted(weeks.items())][-8:]
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


CHEAP_MODELS = ("claude-haiku", "claude-sonnet")


def efficiency_rankings(sessions, min_cost=1.0):
    """Token-efficiency ranking per member proxy (project on a solo host; the
    team gateway supplies real member identity later). Three v1 metrics:
    unit cost of output ($/M output tokens, lower better), cache discipline
    (cache-read share of prompt, higher better), delegation leverage (output
    share from cheap models, higher better). Composite = min-max normalized,
    weighted 40/30/30, graded A>=80 B>=65 C>=50 D>=35 else E. Members below
    min_cost USD are excluded (volume floor: one tiny session must not top
    the board). Cost-per-shipped-run needs the session<->rid join (ID-420)
    and is deliberately absent rather than faked."""
    agg = {}
    for s in sessions:
        a = agg.setdefault(s["project"], {"cost": 0.0, "tok": Counter(), "cheap_out": 0,
                                          "out": 0, "sessions": 0})
        a["cost"] += s.get("cost", 0.0)
        a["tok"].update(s.get("tok") or {})
        a["sessions"] += 1
        for m, c in (s.get("per_model") or {}).items():
            o = c.get("output_tokens", 0)
            a["out"] += o
            if any(m.startswith(cm) for cm in CHEAP_MODELS):
                a["cheap_out"] += o
    rows = []
    for proj, a in agg.items():
        if a["cost"] < min_cost or not a["out"]:
            continue
        prompt = sum(a["tok"][k] for k in ("input_tokens", "cache_read_input_tokens",
                                           "cache_creation_input_tokens"))
        rows.append({
            "member": proj, "sessions": a["sessions"], "cost": a["cost"],
            "unit_cost": a["cost"] / (a["out"] / 1e6),
            "cache_disc": (a["tok"]["cache_read_input_tokens"] / prompt) if prompt else 0.0,
            "delegation": a["cheap_out"] / a["out"],
        })
    if not rows:
        return []

    def norm(vals, invert=False):
        lo, hi = min(vals), max(vals)
        if hi == lo:
            return [100.0] * len(vals)
        return [100 * ((hi - v) / (hi - lo) if invert else (v - lo) / (hi - lo)) for v in vals]

    n_unit = norm([r["unit_cost"] for r in rows], invert=True)
    n_cache = norm([r["cache_disc"] for r in rows])
    n_del = norm([r["delegation"] for r in rows])
    for r, u, ca, de in zip(rows, n_unit, n_cache, n_del):
        r["score"] = round(0.4 * u + 0.3 * ca + 0.3 * de)
        r["grade"] = ("A" if r["score"] >= 80 else "B" if r["score"] >= 65
                      else "C" if r["score"] >= 50 else "D" if r["score"] >= 35 else "E")
    return sorted(rows, key=lambda r: -r["score"])


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


# Allowance policy: efficient members earn headroom, inefficient ones get trimmed
# WITH a stated reason. Deliberately gentle (±15%) because the efficiency grade is a
# hygiene signal, not a measure of value; a hard reallocation on a soft signal would
# punish whoever draws the hardest work.
GRADE_MULT = {"A": 1.15, "B": 1.05, "C": 1.0, "D": 0.90, "E": 0.80}
CONCENTRATION_CAP = 0.40   # no single member proposed more than 40% of the pool
STARVATION_FLOOR = 0.25    # ...nor less than 25% of an equal split
DEMAND_HEADROOM = 1.5      # ...nor more than 1.5x what they actually spent
FLOOR_DEMAND_CAP = 3.0     # the floor may lift a member to at most 3x their spend


def period_key(day, period):
    d = dtm.date.fromisoformat(day)
    if period == "month":
        return f"{d.year}-{d.month:02d}"
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


def allocation_metrics(sessions, period="week", budget=None, feature_top=6):
    """Where the pool went: member x feature x period, with a period-over-period
    delta and a proposed next-period allowance plan.

    'Member' is the project on a solo host (the gateway supplies real identity).
    'Feature' is the git branch the work happened on, which is the only feature-
    shaped signal the transcripts actually carry; `main` is reported as
    unattributed rather than dressed up as a feature."""
    buckets = {}
    for s in sessions:
        if not s.get("day"):
            continue
        pk = period_key(s["day"], period)
        b = buckets.setdefault(pk, {"cost": 0.0, "members": {}})
        b["cost"] += s.get("cost", 0.0)
        m = b["members"].setdefault(s["project"], {"cost": 0.0, "sessions": 0,
                                                   "features": Counter(),
                                                   "tok": Counter()})
        m["cost"] += s.get("cost", 0.0)
        m["sessions"] += 1
        m["tok"].update(s.get("tok") or {})
        # split a session's cost across the branches it touched, by message share
        br = s.get("branches") or Counter()
        tot = sum(br.values())
        if tot:
            for name, n in br.items():
                m["features"][name] += s.get("cost", 0.0) * n / tot
        else:
            m["features"]["(no branch)"] += s.get("cost", 0.0)

    keys = sorted(buckets)
    if not keys:
        return None
    # A sample that starts mid-period makes the earliest bucket partial, and the
    # current bucket is still accruing. Comparing either without saying so produces
    # headlines like "+4963% week over week" that are pure sampling artifact.
    days_seen = sorted({s["day"] for s in sessions if s.get("day")})
    first_day, last_day = days_seen[0], days_seen[-1]
    partial = set()
    if period_key(first_day, period) == keys[0]:
        d = dtm.date.fromisoformat(first_day)
        starts_clean = (d.day == 1) if period == "month" else (d.isoweekday() == 1)
        if not starts_clean:
            partial.add(keys[0])
    d_last = dtm.date.fromisoformat(last_day)
    ends_clean = (d_last.isoweekday() == 7) if period == "week" else False
    if not ends_clean:
        partial.add(keys[-1])
    cur_k = keys[-1]
    prev_k = keys[-2] if len(keys) > 1 else None
    cur, prev = buckets[cur_k], (buckets[prev_k] if prev_k else None)

    eff = {r["member"]: r for r in efficiency_rankings(sessions)}
    members = []
    for name, m in sorted(cur["members"].items(), key=lambda kv: -kv[1]["cost"]):
        pcost = (prev["members"].get(name, {}).get("cost", 0.0) if prev else None)
        e = eff.get(name)
        feats = m["features"].most_common(feature_top)
        members.append({
            "member": name, "cost": m["cost"], "sessions": m["sessions"],
            "share": m["cost"] / cur["cost"] if cur["cost"] else 0.0,
            "prev_cost": pcost,
            "delta": (m["cost"] - pcost) if pcost is not None else None,
            "delta_pct": ((m["cost"] - pcost) / pcost) if pcost else None,
            "grade": e["grade"] if e else None,
            "score": e["score"] if e else None,
            "unit_cost": e["unit_cost"] if e else None,
            "features": [{"name": f, "cost": c,
                          "share": c / m["cost"] if m["cost"] else 0.0,
                          "attributed": f not in ("main", "HEAD", "(no branch)")}
                         for f, c in feats],
        })

    plan, unallocated, over_cap = [], 0.0, []
    if budget and members:
        equal = budget / len(members)
        floor = equal * STARVATION_FLOOR
        cap = budget * CONCENTRATION_CAP
        # A member cannot plausibly absorb an unbounded jump in one period, so each
        # proposal is bounded by DEMAND_HEADROOM x what they actually spent. Budget
        # that fits nobody's ceiling is reported as unallocated headroom rather than
        # force-fed to whoever happens to be under the cap (which produced absurd
        # proposals: a $44 spender offered $549 because a $3.9k member hit the cap).
        weights, ceilings = {}, {}
        for m in members:
            g = m["grade"] or "C"
            weights[m["member"]] = max(m["cost"], 0.01) * GRADE_MULT.get(g, 1.0)
            # The floor exists so nobody is starved, but it must not outrun demonstrated
            # demand: lifting a $50 spender to a $1,250 allowance because the pool is
            # large is the same force-feeding bug in a milder form. A member with no
            # history is the exception, they get the floor so they can start.
            demand = m["cost"] * DEMAND_HEADROOM
            lift = floor if m["cost"] <= 0.01 else min(floor, m["cost"] * FLOOR_DEMAND_CAP)
            ceilings[m["member"]] = max(demand, lift)
            if m["cost"] > cap:
                over_cap.append(m["member"])
        alloc = {k: 0.0 for k in weights}
        remaining = budget
        movable = set(weights)
        for _ in range(12):  # water-filling: settle, clamp, redistribute the rest
            if not movable or remaining <= 0.005:
                break
            wsum = sum(weights[k] for k in movable) or 1.0
            fixed = []
            for k in list(movable):
                want = alloc[k] + remaining * weights[k] / wsum
                limit = min(ceilings[k], cap)
                if want >= limit:
                    remaining -= (limit - alloc[k])
                    alloc[k] = limit
                    fixed.append(k)
            if not fixed:
                for k in movable:
                    alloc[k] += remaining * weights[k] / wsum
                remaining = 0.0
                break
            movable -= set(fixed)
        for k in movable:  # anyone still below floor gets lifted to it
            if alloc[k] < floor:
                remaining -= (floor - alloc[k])
                alloc[k] = floor
        unallocated = max(0.0, remaining)
        for m in members:
            k = m["member"]
            a_ = alloc[k]
            g = m["grade"]
            why = []
            if g in ("A", "B"):
                why.append(f"grade {g}: +{int((GRADE_MULT[g] - 1) * 100)}% headroom")
            elif g in ("D", "E"):
                why.append(f"grade {g}: {int((GRADE_MULT[g] - 1) * 100)}% weighting, "
                           f"unit cost ${m['unit_cost']:,.0f}/M out")
            else:
                why.append("grade C or unranked: baseline weighting")
            if abs(a_ - min(ceilings[k], cap)) < 0.01:
                why.append("at ceiling"
                           if ceilings[k] <= cap else "at the concentration cap")
            if k in over_cap:
                why.append(f"CURRENT spend already exceeds the {CONCENTRATION_CAP:.0%} "
                           f"concentration cap , this needs a decision, not a slider")
            plan.append({"member": k, "current": m["cost"], "proposed": a_,
                         "delta": a_ - m["cost"], "grade": g, "reason": "; ".join(why)})

    return {"partial": sorted(partial), "sample_days": len(days_seen),
            "sample_range": (first_day, last_day),
            "period": period, "current_key": cur_k, "prev_key": prev_k,
            "current_total": cur["cost"],
            "prev_total": prev["cost"] if prev else None,
            "members": members, "plan": plan, "budget": budget,
            "unallocated": unallocated if budget else None,
            "over_cap": over_cap,
            "periods": [{"key": k, "cost": buckets[k]["cost"]} for k in keys]}


def allocation_markdown(a):
    """The weekly/monthly report, as markdown a lead can paste into a channel."""
    if not a:
        return "_no dated sessions to report on_\n"
    L = [f"# Pool allocation report · {a['current_key']} ({a['period']}ly)", ""]
    tot = a["current_total"]
    flags = []
    if a["current_key"] in a["partial"]:
        flags.append(f"{a['current_key']} is still in progress")
    if a["prev_key"] and a["prev_key"] in a["partial"]:
        flags.append(f"{a['prev_key']} is partial in this sample")
    if a["prev_total"] and not flags:
        d = tot - a["prev_total"]
        L.append(f"**Pool drawn:** ${tot:,.2f} "
                 f"({'+' if d >= 0 else ''}{d:,.2f} vs {a['prev_key']}, "
                 f"{d / a['prev_total']:+.0%})")
    elif a["prev_total"]:
        d = tot - a["prev_total"]
        L.append(f"**Pool drawn:** ${tot:,.2f} (raw change {d:+,.2f} vs {a['prev_key']}, "
                 f"**not comparable**: {'; '.join(flags)})")
    else:
        L.append(f"**Pool drawn:** ${tot:,.2f} (no prior period to compare)")
    L += ["", "## By member", "",
          "| member | spend | share | vs prior | grade | $/M out | sessions |",
          "|---|---:|---:|---:|:--:|---:|---:|"]
    for m in a["members"]:
        dl = (f"{m['delta_pct']:+.0%}" if m["delta_pct"] is not None else "new")
        uc = f"${m['unit_cost']:,.0f}" if m["unit_cost"] else "-"
        L.append(f"| {m['member']} | ${m['cost']:,.2f} | {m['share']:.0%} | {dl} | "
                 f"{m['grade'] or '-'} | {uc} | {m['sessions']} |")
    L += ["", "## Where it went (top features per member)", ""]
    for m in a["members"]:
        feats = ", ".join(
            f"`{f['name']}` ${f['cost']:,.2f} ({f['share']:.0%})"
            + ("" if f["attributed"] else " _unattributed_")
            for f in m["features"])
        L.append(f"- **{m['member']}** , {feats}")
    if a["plan"]:
        L += ["", f"## Proposed allowances for next {a['period']} "
                  f"(pool ${a['budget']:,.0f})", "",
              "| member | current | proposed | change | why |",
              "|---|---:|---:|---:|---|"]
        for p in a["plan"]:
            L.append(f"| {p['member']} | ${p['current']:,.2f} | ${p['proposed']:,.2f} | "
                     f"{p['delta']:+,.2f} | {p['reason']} |")
        L += ["", "_Proposal only._ Efficiency grades measure token economics (unit cost, "
                  "cache discipline, cheap-model routing), not value delivered: a member "
                  "doing the hardest work can grade low while spending correctly. Review "
                  "before applying, and treat a trim as a conversation, not a verdict."]
    L += ["", "---", "",
          f"Sample: {a['sample_days']} days ({a['sample_range'][0]} to "
          f"{a['sample_range'][1]}). "
          + (f"Partial periods: {', '.join(a['partial'])}. " if a["partial"] else "")
          + "Costs are computed from list prices, not invoiced amounts. Feature attribution "
          "uses the git branch each session worked on; `main` and `HEAD` are reported as "
          "unattributed rather than presented as features. Per-member identity on a solo "
          "host is the project directory; the team gateway supplies real identity."]
    return "\n".join(L) + "\n"


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


def stacked_weeks(weeks, title):
    """Stacked bars per week by lane. Categorical fill order is fixed (never
    cycled), legend always present, 2px gaps between segments."""
    if not weeks:
        return ""
    lanes = []
    for _, counts in weeks:
        for k in counts:
            if k not in lanes:
                lanes.append(k)
    cls = ["one", "ovr", "ok", "skip", "over"]
    mx = max(sum(c.values()) for _, c in weeks) or 1
    legend = ('<div class="legend">' + "".join(
        f'<span><b class="sw {cls[i % len(cls)]}"></b>{H.escape(l)}</span>'
        for i, l in enumerate(lanes)) + "</div>")
    rows = ""
    for label, counts in weeks:
        segs = "".join(
            f'<span class="seg {cls[lanes.index(l) % len(cls)]}" '
            f'style="width:{100 * counts[l] / mx:.1f}%"><i>{H.escape(l)}: {counts[l]}</i></span>'
            for l in lanes if counts.get(l))
        rows += (f'<div class="mixrow"><span class="lbl">{H.escape(label)}</span>'
                 f'<span class="mixtrack">{segs}</span>'
                 f'<span class="val">{sum(counts.values())}</span></div>')
    return (f'<figure class="chart"><figcaption>{H.escape(title)}</figcaption>'
            f"{legend}{rows}</figure>")


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
a.rid-link{color:inherit;text-decoration:underline dotted;text-underline-offset:3px}
a.rid-link:hover{color:var(--ember)}
tr.detail>td{background:var(--sheet);padding:10px 14px}
.detail-log table{margin:6px 0 0}
body.redacted code,body.redacted .reason,body.redacted td.mono,
body.redacted .detail-log{filter:blur(5px);user-select:none}
select{font-family:var(--mono);font-size:11.5px;background:var(--card);color:var(--ink);
border:1px solid var(--rule-strong);padding:2px 6px}
@media (prefers-reduced-motion:no-preference){.navbtn,.chip{transition:color .15s,border-color .15s}}
</style>"""


SESSION_STYLE = """<style>
:root{--coal:#F2F0EC;--sheet:#FAF9F6;--card:#FFF;--ink:#1C1E24;--iron:#3A3F49;
--ash:#6E7480;--rule:#D8D4CC;--rule-strong:#B9B4AA;--ember:#C84A16;--heat2:#C84A16;
--heat3:#F08C1B;--heat4:#FFD75E;--ok:#2E7D4F;--warn:#B07B10;--bad:#B3261E;
--glow:rgba(200,74,22,.12);
--mono:ui-monospace,"SF Mono","Cascadia Code","JetBrains Mono",Menlo,monospace;
--sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Segoe UI",system-ui,sans-serif}
@media (prefers-color-scheme:dark){:root{--coal:#15171C;--sheet:#1B1E24;--card:#1F232B;
--ink:#ECEAE4;--iron:#B8BDC7;--ash:#8A8F99;--rule:#2B2F37;--rule-strong:#3C414B;
--ok:#5DBB84;--warn:#D9A441;--bad:#E5726B;--glow:rgba(240,140,27,.10)}}
:root[data-theme=dark]{--coal:#15171C;--sheet:#1B1E24;--card:#1F232B;--ink:#ECEAE4;
--iron:#B8BDC7;--ash:#8A8F99;--rule:#2B2F37;--rule-strong:#3C414B;--ok:#5DBB84;
--warn:#D9A441;--bad:#E5726B;--glow:rgba(240,140,27,.10)}
:root[data-theme=light]{--coal:#F2F0EC;--sheet:#FAF9F6;--card:#FFF;--ink:#1C1E24;
--iron:#3A3F49;--ash:#6E7480;--rule:#D8D4CC;--rule-strong:#B9B4AA;--ok:#2E7D4F;
--warn:#B07B10;--bad:#B3261E;--glow:rgba(200,74,22,.12)}
*{box-sizing:border-box}
body{background:var(--coal);color:var(--ink);font-family:var(--sans);margin:0;
line-height:1.55;-webkit-font-smoothing:antialiased}
.spine{height:6px;background:linear-gradient(90deg,#8A8E96,var(--heat2),var(--heat3),var(--heat4))}
main{max-width:960px;margin:0 auto;padding:22px 20px 60px}
.crumb{display:flex;justify-content:space-between;align-items:center;margin-bottom:18px;
font-family:var(--mono);font-size:12px}
.crumb a{color:var(--ash);text-decoration:none}
.crumb a:hover{color:var(--ember)}
.crumb button{font:inherit;font-family:var(--mono);font-size:11.5px;letter-spacing:.06em;
text-transform:uppercase;background:var(--card);color:var(--ember);
border:1px solid var(--ember);padding:5px 12px;cursor:pointer}
:focus-visible{outline:2px solid var(--ember);outline-offset:2px}
.eyebrow{font-family:var(--mono);font-size:11.5px;letter-spacing:.16em;
text-transform:uppercase;color:var(--ember)}
h1{font-family:var(--mono);font-weight:700;text-transform:uppercase;
font-size:clamp(20px,3.4vw,30px);line-height:1.06;margin:2px 0 6px;word-break:break-all}
h2{font-family:var(--mono);font-size:13px;letter-spacing:.12em;text-transform:uppercase;
margin:30px 0 8px;color:var(--iron)}
.meta{color:var(--ash);font-size:13.5px;max-width:70ch}
.dim{color:var(--ash)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:1px;
background:var(--rule);border:1px solid var(--rule);margin:18px 0}
.tile{background:var(--card);padding:12px 14px}
.tile b{display:block;font-family:var(--mono);font-size:17px}
.tile span{font-family:var(--mono);font-size:10.5px;letter-spacing:.08em;
text-transform:uppercase;color:var(--ash)}
table{border-collapse:collapse;width:100%;margin:8px 0;font-variant-numeric:tabular-nums}
th,td{border:1px solid var(--rule);padding:6px 9px;font-size:12.5px;text-align:left;
background:var(--card);vertical-align:top}
th{font-family:var(--mono);font-size:10.5px;letter-spacing:.12em;text-transform:uppercase;
color:var(--ash);position:sticky;top:0}
td.mono,.mono{font-family:var(--mono);font-size:11.5px;white-space:nowrap}
tr.s-missed td{background:color-mix(in srgb,var(--bad) 8%,var(--card))}
tr.s-override td{background:color-mix(in srgb,var(--warn) 8%,var(--card))}
tr:hover td{background:var(--glow)}
.chip{display:inline-block;font-family:var(--mono);font-size:10.5px;letter-spacing:.06em;
padding:1px 8px;border:1px solid var(--rule-strong);white-space:nowrap}
.chip.ok{color:var(--ok);border-color:var(--ok)}
.chip.bad{color:var(--bad);border-color:var(--bad)}
.chip.warn{color:var(--warn);border-color:var(--warn)}
.chip.dim{color:var(--ash)}
.scroll{max-height:none;overflow-x:auto;border:1px solid var(--rule)}
.scroll table{margin:0;border:none}
pre{background:var(--sheet);border:1px solid var(--rule);padding:10px 12px;overflow-x:auto;
font-family:var(--mono);font-size:12px}
.foot{margin-top:32px;font-family:var(--mono);font-size:11px;color:var(--ash)}
.stepper{display:flex;flex-wrap:wrap;gap:0;border:1px solid var(--rule-strong);
background:var(--card);margin:10px 0}
.step{display:flex;align-items:center;gap:8px;padding:10px 16px;position:relative;
font-family:var(--mono);flex:1 1 auto;min-width:110px;border-right:1px solid var(--rule)}
.step:last-child{border-right:none}
.step::after{content:"›";position:absolute;right:-6px;top:50%;transform:translateY(-50%);
color:var(--rule-strong);z-index:1;background:var(--card);line-height:1}
.step:last-child::after{content:none}
.step .g{font-size:15px;line-height:1}
.step .l{font-size:11px;letter-spacing:.1em;text-transform:uppercase;color:var(--iron)}
.step.ok .g{color:var(--ok)}
.step.ovr .g{color:var(--warn)}
.step.skip .g{color:var(--ash)}
.step.miss{background:color-mix(in srgb,var(--bad) 7%,var(--card))}
.step.miss .g{color:var(--bad)}
.step.miss .l{color:var(--bad)}
.step.opt .g,.step.opt .l{color:var(--rule-strong)}
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
                "under two days; extrapolating one partial day would invent a number.")
             + "</p>")

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


def efficiency_section(eff):
    """The ranking as its own board: leaderboard, grade bands, metric legend."""
    gcls = {"A": "ok", "B": "ok", "C": "dim", "D": "warn", "E": "bad"}
    if not eff:
        rows = '<tr><td colspan=8 class=reason>not enough volume to rank</td></tr>'
        podium = ""
    else:
        rows = "".join(
            f'<tr><td>{i + 1}</td>'
            f'<td><span class="chip {gcls[r["grade"]]}">{r["grade"]}</span></td>'
            f"<td>{H.escape(r['member'])}</td><td><b>{r['score']}</b></td>"
            f"<td>${r['unit_cost']:,.0f}</td><td>{r['cache_disc']:.0%}</td>"
            f"<td>{r['delegation']:.0%}</td><td>${r['cost']:,.2f}</td>"
            f"<td>{r['sessions']}</td></tr>"
            for i, r in enumerate(eff))
        top = eff[:3]
        podium = '<div class="tiles">' + "".join(
            f'<div class="tile"><b><span class="chip {gcls[r["grade"]]}">{r["grade"]}</span> '
            f'{H.escape(r["member"])}</b><span>#{i + 1} · score {r["score"]} · '
            f'${r["unit_cost"]:,.0f}/M out</span></div>'
            for i, r in enumerate(top)) + "</div>"
    dist = Counter(r["grade"] for r in eff)
    bands = "".join(
        f'<div class="mixrow"><span class="lbl">{g} · {lbl}</span>'
        f'<span class="mixtrack"><span class="seg {gcls[g]}" '
        f'style="width:{100 * dist.get(g, 0) / max(1, len(eff)):.0f}%">'
        f"<i>{g}: {dist.get(g, 0)}</i></span></span>"
        f'<span class="val">{dist.get(g, 0)}</span></div>'
        for g, lbl in (("A", "80+"), ("B", "65-79"), ("C", "50-64"),
                       ("D", "35-49"), ("E", "<35")))
    return f"""<section id="efficiency">
<div class="eyebrow">Spend</div>
<h1>Efficiency board</h1>
<p class="meta">Who spends tokens well, ranked. On this solo host a "member" is a project;
the team gateway supplies real member identity. Volume floor $1 so a single small session
cannot top the board.</p>
{podium}
<div class="charts">
<figure class="chart"><figcaption>Grade distribution</figcaption>{bands}</figure>
<figure class="chart"><figcaption>How the score is built</figcaption>
<div class="mixrow"><span class="lbl">unit cost</span><span class="mixtrack">
<span class="seg one" style="width:40%"><i>40%</i></span></span><span class="val">40%</span></div>
<div class="mixrow"><span class="lbl">cache discipline</span><span class="mixtrack">
<span class="seg ovr" style="width:30%"><i>30%</i></span></span><span class="val">30%</span></div>
<div class="mixrow"><span class="lbl">delegation</span><span class="mixtrack">
<span class="seg ok" style="width:30%"><i>30%</i></span></span><span class="val">30%</span></div>
<p class="meta" style="margin:.5rem 0 0">Each metric is min-max normalized across members,
then weighted. Cost-per-shipped-run is the metric that should dominate this board and is
deliberately absent until the session-to-run join lands (ID-420): without it there is no
defensible denominator.</p></figure>
</div>
<h2>Leaderboard</h2>
<table><tr><th>#</th><th>grade</th><th>member</th><th>score</th><th>$/M output</th>
<th>cache discipline</th><th>delegation</th><th>spend</th><th>sessions</th></tr>{rows}</table>
<dl class="legend">
<dt>unit cost</dt><dd>USD per million output tokens. Lower is better: work produced per dollar.</dd>
<dt>cache discipline</dt><dd>cache-read share of prompt tokens. Higher means stable prefixes and less re-reading the world each turn.</dd>
<dt>delegation</dt><dd>share of output tokens produced by cheap models. Higher means cheap-first routing rather than premium-everything.</dd>
</dl>
<p class="meta">This measures token economics, not value delivered. Someone doing the hardest
work can rank mid-table by spending premium tokens well; read it as a routing-and-hygiene
signal, never as a performance review.</p>
</section>"""


def allocation_section(a):
    """Pool -> member -> feature, period over period, plus the proposed plan."""
    if not a:
        return """<section id="allocation"><div class="eyebrow">Spend</div>
<h1>Pool allocation</h1><p class="meta">No dated sessions to allocate.</p></section>"""
    tot = a["current_total"]
    dtxt = "no prior period"
    if a["prev_total"]:
        d = tot - a["prev_total"]
        if a["current_key"] in a["partial"] or a["prev_key"] in a["partial"]:
            dtxt = "not comparable (partial period)"
        else:
            dtxt = f"{d:+,.2f} vs {a['prev_key']} ({d / a['prev_total']:+.0%})"
    tiles = "".join(f'<div class="tile"><b>{v}</b><span>{k}</span></div>' for k, v in [
        (f"pool drawn · {a['current_key']}", f"${tot:,.2f}"),
        ("change", dtxt),
        ("members drawing", len(a["members"])),
        ("unallocated headroom",
         f"${a['unallocated']:,.2f}" if a.get("unallocated") is not None else "set a budget"),
    ])
    partial_note = (f", partial periods: {', '.join(a['partial'])}"
                    if a["partial"] else "")
    mx = max((m["cost"] for m in a["members"]), default=1) or 1
    shares = "".join(
        f'<div class="mixrow"><span class="lbl">{H.escape(m["member"])}</span>'
        f'<span class="mixtrack"><span class="seg one" style="width:{100 * m["cost"] / mx:.1f}%">'
        f'<i>{H.escape(m["member"])}: ${m["cost"]:,.2f}</i></span></span>'
        f'<span class="val">{m["share"]:.0%}</span></div>' for m in a["members"][:12])
    trend = "".join(
        f'<div class="mixrow"><span class="lbl">{H.escape(p_["key"])}</span>'
        f'<span class="mixtrack"><span class="seg ovr" '
        f'style="width:{100 * p_["cost"] / max(x["cost"] for x in a["periods"]):.1f}%">'
        f'<i>${p_["cost"]:,.2f}</i></span></span>'
        f'<span class="val">${p_["cost"]:,.0f}</span></div>' for p_ in a["periods"][-8:])

    feat_rows = ""
    for m in a["members"][:12]:
        cells = " ".join(
            f'<span class="chip {"dim" if not f["attributed"] else "ok"}">'
            f'{H.escape(f["name"][:26])} ${f["cost"]:,.2f}</span>' for f in m["features"])
        feat_rows += (f'<tr><td>{H.escape(m["member"])}</td>'
                      f'<td>${m["cost"]:,.2f}</td><td>{cells}</td></tr>')

    gmap = {"A": "ok", "B": "ok", "C": "dim", "D": "warn", "E": "bad"}
    delta_rows = ""
    for m in a["members"]:
        prev = f"${m['prev_cost']:,.2f}" if m["prev_cost"] is not None else "&mdash;"
        chg = f"{m['delta_pct']:+.0%}" if m["delta_pct"] is not None else "new"
        grade = (f'<span class="chip {gmap[m["grade"]]}">{m["grade"]}</span>'
                 if m["grade"] else "-")
        delta_rows += (f'<tr><td>{H.escape(m["member"])}</td><td>${m["cost"]:,.2f}</td>'
                       f"<td>{prev}</td><td>{chg}</td><td>{grade}</td>"
                       f'<td>{m["sessions"]}</td></tr>')

    plan_html = ""
    if a["plan"]:
        prows = "".join(
            f'<tr><td>{H.escape(p_["member"])}</td><td>${p_["current"]:,.2f}</td>'
            f'<td><b>${p_["proposed"]:,.2f}</b></td>'
            f'<td class="{"up" if p_["delta"] >= 0 else "down"}">{p_["delta"]:+,.2f}</td>'
            f'<td class="reason">{H.escape(p_["reason"])}</td></tr>' for p_ in a["plan"])
        warn = ""
        if a["over_cap"]:
            warn = (f'<p class="meta"><span class="chip bad">decision needed</span> '
                    f'{H.escape(", ".join(a["over_cap"]))} already draws more than the '
                    f'{CONCENTRATION_CAP:.0%} concentration cap. No allowance slider fixes that; '
                    f'either the cap is wrong for your team or the work needs splitting.</p>')
        plan_html = f"""<h2>Proposed allowances · next {a['period']}</h2>
<p class="meta">Pool ${a['budget']:,.0f}. Proposals are bounded by demand
({DEMAND_HEADROOM:g}x what a member actually spent), by the {CONCENTRATION_CAP:.0%}
concentration cap, and by a starvation floor. Budget that fits nobody's ceiling shows as
<b>unallocated headroom</b> rather than being force-fed to whoever is under the cap.</p>
{warn}
<table><tr><th>member</th><th>current</th><th>proposed</th><th>change</th><th>why</th></tr>
{prows}</table>
<div class="seg-bar"><button id="plan-export">Export plan JSON</button></div>
<p class="meta">Proposal only, never applied automatically. Efficiency grades measure token
economics, not value delivered: a member doing the hardest work can grade low while
spending correctly. Treat a trim as a conversation.</p>"""

    return f"""<section id="allocation">
<div class="eyebrow">Spend</div>
<h1>Pool allocation</h1>
<p class="meta">Where the pool went: member, then feature, for {a['current_key']}
({a['period']}ly). Sample: {a['sample_days']} days ({a['sample_range'][0]} to
{a['sample_range'][1]}){partial_note}. Feature attribution uses the git branch each session worked on;
<code>main</code> and <code>HEAD</code> are shown greyed as unattributed rather than
dressed up as features. Member is the project directory on this host; the team gateway
supplies real member identity.</p>
<div class="tiles">{tiles}</div>
<div class="charts">
<figure class="chart"><figcaption>Share of pool · this {a['period']}</figcaption>{shares}</figure>
<figure class="chart"><figcaption>Pool drawn per {a['period']}</figcaption>{trend}</figure>
</div>
<h2>Member × feature</h2>
<div class="scroll"><table><tr><th>member</th><th>spend</th>
<th>features (branch attribution)</th></tr>{feat_rows}</table></div>
<h2>Period comparison</h2>
<table><tr><th>member</th><th>this {a['period']}</th><th>prior</th><th>change</th>
<th>grade</th><th>sessions</th></tr>{delta_rows}</table>
{plan_html}
</section>"""


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


TRANSCRIPT_STYLE = """<style>
.turn{border:1px solid var(--rule);border-left-width:3px;background:var(--card);
margin:10px 0;padding:10px 12px}
.turn.user{border-left-color:var(--ember);background:var(--sheet)}
.turn.agent{border-left-color:var(--rule-strong)}
.thead{display:flex;align-items:center;gap:8px;flex-wrap:wrap;font-family:var(--mono);
font-size:11px;color:var(--ash);margin-bottom:6px}
.thead .who{font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--iron)}
.turn.user .thead .who{color:var(--ember)}
.tstamp{color:var(--ash)}
.ttok,.tcost{margin-left:auto;font-variant-numeric:tabular-nums}
.tcost{color:var(--iron);margin-left:0}
.note-btn,.lesson-btn{font-family:var(--mono);font-size:10.5px;letter-spacing:.06em;
text-transform:uppercase;background:transparent;color:var(--ash);
border:1px solid var(--rule-strong);padding:1px 7px;cursor:pointer}
.note-btn:hover,.lesson-btn:hover{color:var(--ember);border-color:var(--ember)}
.btext{white-space:pre-wrap;font-size:13.5px;line-height:1.55;max-width:78ch}
.bthink{font-family:var(--mono);font-size:11.5px;color:var(--ash);font-style:italic;
margin:4px 0}
details.btool,details.bres{margin:5px 0;border:1px solid var(--rule);background:var(--sheet)}
details.btool summary,details.bres summary{cursor:pointer;padding:4px 8px;
font-family:var(--mono);font-size:11.5px;color:var(--iron)}
details.bres.err summary{color:var(--bad)}
details pre{margin:0;padding:8px 10px;border-top:1px solid var(--rule);max-height:22rem;
overflow:auto;white-space:pre-wrap;word-break:break-word;font-size:11.5px}
textarea.note{width:100%;min-height:3.4rem;margin-top:6px;background:var(--sheet);
color:var(--ink);border:1px solid var(--rule-strong);padding:6px 8px;
font-family:var(--sans);font-size:13px}
.crumb span{display:flex;gap:6px}
/* rich blocks: markdown prose, code, diff, terminal */
.btext.md{white-space:normal}
.btext.md p{margin:6px 0}
.btext.md h3,.btext.md h4,.btext.md h5{font-family:var(--mono);text-transform:uppercase;
letter-spacing:.06em;font-size:13px;margin:12px 0 4px;color:var(--iron)}
.btext.md ul,.btext.md ol{margin:6px 0;padding-left:22px;display:flex;
flex-direction:column;gap:3px}
.btext.md blockquote{border-left:3px solid var(--rule-strong);margin:6px 0;
padding:2px 12px;color:var(--iron)}
.btext.md code{font-family:var(--mono);font-size:.9em;background:var(--sheet);
border:1px solid var(--rule);padding:0 4px}
.btext.md pre.code code{border:none;background:none;padding:0}
.btext.md a{color:var(--ember)}
.btext.md hr{border:none;border-top:1px solid var(--rule);margin:10px 0}
pre.code,pre.term,pre.diff{margin:6px 0;padding:9px 11px;background:var(--ledgerbg,#1B1E24);
color:var(--ledgerink,#D7DCE4);font-family:var(--mono);font-size:11.5px;line-height:1.6;
overflow-x:auto;border:1px solid var(--rule-strong)}
details pre.code,details pre.term,details pre.diff{border:none;
border-top:1px solid var(--rule-strong);margin:0}
.hs{color:#8FBE6E}.hc{color:#6E7480;font-style:italic}.hk{color:#F08C1B}.hn{color:#FFD75E}
pre.term .ps1{color:#F08C1B;font-weight:700;margin-right:6px}
pre.diff .dl{display:block;white-space:pre-wrap;word-break:break-word}
pre.diff .del{background:rgba(179,38,30,.22);color:#F0A9A4}
pre.diff .add{background:rgba(46,125,79,.24);color:#9AD8B2}
.btool.oneline{font-family:var(--mono);font-size:11.5px;color:var(--iron);
border:1px solid var(--rule);background:var(--sheet);padding:4px 8px;margin:5px 0}
/* inferred workflow stage strip */
.stagebar{display:flex;gap:1px;height:18px;border:1px solid var(--rule-strong);
background:var(--rule);margin:8px 0 4px}
.stagebar a{flex:1 1 0;min-width:3px;display:block}
.st-explore{background:#3B6FC2}.st-build{background:#C84A16}
.st-verify{background:#2E7D4F}.st-ship{background:#B07B10}.st-talk{background:#8A8E96}
.stagekey{display:flex;gap:14px;flex-wrap:wrap;font-family:var(--mono);font-size:11px;
color:var(--iron);margin-bottom:4px}
.stagekey i{display:inline-block;width:10px;height:10px;margin-right:5px;vertical-align:-1px}
</style>"""


SECRET_PATTERNS = [
    (re.compile(r"sk-ant-[A-Za-z0-9_\-]{10,}"), "sk-ant-REDACTED"),
    (re.compile(r"\bsk-[A-Za-z0-9]{20,}"), "sk-REDACTED"),
    (re.compile(r"\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}"), "gh-token-REDACTED"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AKIA-REDACTED"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}"), "slack-token-REDACTED"),
    (re.compile(r"\bwhsec_[A-Za-z0-9]{16,}"), "whsec-REDACTED"),
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._\-]{20,}"), r"\1 REDACTED"),
    (re.compile(r"(?i)\b(password|passwd|secret|api[_-]?key|access[_-]?token|"
                r"refresh[_-]?token|client[_-]?secret)\s*[=:]\s*\S{6,}"),
     r"\1=REDACTED"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
     "-----PRIVATE KEY REDACTED-----"),
]


def redact(text):
    """Best-effort secret scrub before any transcript content is rendered.
    Returns (text, hits). This is a SELECTOR-poor context (free-form text, no
    named fields), so it is a mask and masks fail open: it is a safety net for
    accidental exposure, never a guarantee. The page says so."""
    if not text:
        return text, 0
    hits = 0
    for rx, repl in SECRET_PATTERNS:
        text, n = rx.subn(repl, text)
        hits += n
    return text, hits


def load_transcript(path, max_chars=4000):
    """Parse one Claude Code transcript into render-ready turns. Content IS read
    here (opt-in --with-transcript only); every string passes through redact()."""
    turns, redactions = [], 0
    meta = {"models": Counter(), "tools": Counter(), "tok": Counter(), "cost": 0.0,
            "project": path.parent.name, "session": path.stem, "t0": None, "t1": None,
            "cwd": None, "branch": None, "truncated": 0}
    per_model = {}
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        ts = d.get("timestamp")
        if isinstance(ts, str):
            meta["t0"] = meta["t0"] or ts
            meta["t1"] = ts
        meta["cwd"] = meta["cwd"] or d.get("cwd")
        meta["branch"] = meta["branch"] or d.get("gitBranch")
        msg = d.get("message") or {}
        if not isinstance(msg, dict):
            continue
        role = msg.get("role")
        if role not in ("user", "assistant"):
            continue
        model = msg.get("model")
        if model:
            meta["models"][model] += 1
        u = msg.get("usage") or {}
        c = Counter()
        for k in TOKEN_KINDS:
            v = u.get(k)
            if isinstance(v, int):
                c[k] += v
                meta["tok"][k] += v
        if c and model:
            pm = per_model.setdefault(model, Counter())
            pm.update(c)
        blocks = []
        content = msg.get("content")
        if isinstance(content, str):
            txt, n = redact(content)
            redactions += n
            blocks.append({"kind": "text", "text": txt})
        elif isinstance(content, list):
            for blk in content:
                if not isinstance(blk, dict):
                    continue
                bt = blk.get("type")
                if bt == "text":
                    txt, n = redact(blk.get("text", ""))
                    redactions += n
                    blocks.append({"kind": "text", "text": txt})
                elif bt == "thinking":
                    blocks.append({"kind": "thinking",
                                   "chars": len(blk.get("thinking") or "")})
                elif bt == "tool_use":
                    meta["tools"][blk.get("name", "?")] += 1
                    raw = json.dumps(blk.get("input", {}), indent=1)[:max_chars]
                    if len(json.dumps(blk.get("input", {}))) > max_chars:
                        meta["truncated"] += 1
                    txt, n = redact(raw)
                    redactions += n
                    inp = blk.get("input") if isinstance(blk.get("input"), dict) else {}
                    obj = {}
                    for k2, v2 in list(inp.items())[:12]:
                        s2 = v2 if isinstance(v2, str) else json.dumps(v2)
                        if len(s2) > max_chars:
                            s2 = s2[:max_chars] + "\n... [truncated]"
                            meta["truncated"] += 1
                        s2, n2 = redact(s2)
                        redactions += n2
                        obj[str(k2)] = s2
                    blocks.append({"kind": "tool_use", "name": blk.get("name", "?"),
                                   "input": txt, "obj": obj, "id": blk.get("id", "")})
                elif bt == "tool_result":
                    body = blk.get("content")
                    if isinstance(body, list):
                        body = "\n".join(b.get("text", "") for b in body
                                          if isinstance(b, dict) and b.get("type") == "text")
                    body = str(body or "")
                    if len(body) > max_chars:
                        meta["truncated"] += 1
                        body = body[:max_chars] + f"\n... [{len(body) - max_chars} more chars]"
                    txt, n = redact(body)
                    redactions += n
                    blocks.append({"kind": "tool_result", "text": txt,
                                   "id": blk.get("tool_use_id", ""),
                                   "error": bool(blk.get("is_error"))})
        if blocks:
            turns.append({"role": role, "ts": ts, "model": model, "tok": c,
                          "cost": model_cost(model, c) if model else 0.0,
                          "sidechain": bool(d.get("isSidechain")), "blocks": blocks})
    meta["cost"] = sum(model_cost(m, c) for m, c in per_model.items())
    meta["redactions"] = redactions
    return turns, meta


# Rich rendering helpers: server-side, stdlib-only, escape-first (injection-safe).

_HL_LANGS = {
    "python": ("py", r"#[^\n]*", r"\b(def|class|return|if|elif|else|for|while|import|from|as|with|try|except|finally|raise|lambda|yield|pass|break|continue|and|or|not|in|is|None|True|False|self|async|await)\b"),
    "py": None, "javascript": ("js", r"//[^\n]*", r"\b(function|const|let|var|return|if|else|for|while|class|new|this|typeof|instanceof|null|undefined|true|false|async|await|import|export|from|default|try|catch|throw)\b"),
    "js": None, "typescript": None, "ts": None,
    "bash": ("sh", r"#[^\n]*", r"\b(if|then|else|elif|fi|for|do|done|while|case|esac|function|local|export|return|echo|cd|source)\b"),
    "sh": None, "shell": None, "fish": None,
    "json": ("json", None, r"\b(true|false|null)\b"),
    "html": ("html", r"<!--.*?-->", r"\b(div|span|section|main|body|head|html|script|style|a|p|table|tr|td|th|button)\b"),
    "go": ("go", r"//[^\n]*", r"\b(func|package|import|return|if|else|for|range|type|struct|interface|map|chan|go|defer|var|const|nil|true|false)\b"),
    "sql": ("sql", r"--[^\n]*", r"\b(?i:select|from|where|join|left|right|inner|group by|order by|insert|update|delete|create|table|as|on|and|or|not|null)\b"),
}
_HL_ALIAS = {"py": "python", "js": "javascript", "typescript": "javascript",
             "ts": "javascript", "sh": "bash", "shell": "bash", "fish": "bash"}


def hl(code, lang=""):
    """Lightweight syntax highlight: comments, strings, keywords, numbers.
    Tokenizes the RAW text and escapes each piece, so markup cannot leak in."""
    spec = _HL_LANGS.get(_HL_ALIAS.get((lang or "").lower(), (lang or "").lower()))
    if not spec:
        return H.escape(code)
    _, comment, kw = spec
    parts = [r'(?P<s>"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')']
    if comment:
        parts.append(f"(?P<c>{comment})")
    parts += [f"(?P<k>{kw})", r"\b(?P<n>\d+(?:\.\d+)?)\b"]
    pat = re.compile("|".join(parts), re.S)
    cls_map = {"s": "hs", "c": "hc", "k": "hk", "n": "hn"}
    out, pos = [], 0
    for m in pat.finditer(code):
        out.append(H.escape(code[pos:m.start()]))
        name = next(g for g, v in m.groupdict().items() if v is not None)
        out.append(f'<span class="{cls_map[name]}">{H.escape(m.group(0))}</span>')
        pos = m.end()
    out.append(H.escape(code[pos:]))
    return "".join(out)


def _md_inline(s):
    s = H.escape(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<i>\1</i>", s)
    s = re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)",
               r'<a href="\2" rel="noopener noreferrer nofollow">\1</a>', s)
    return s


def md_html(text):
    """Small markdown renderer for assistant prose: headings, lists, fences with
    highlighting, tables, blockquotes. Falls back to escaped paragraphs."""
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        ln = lines[i]
        f = re.match(r"^```(\w*)\s*$", ln)
        if f:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"):
                j += 1
            code = "\n".join(lines[i + 1:j])
            out.append(f'<pre class="code"><code>{hl(code, f.group(1))}</code></pre>')
            i = j + 1
            continue
        if ln.startswith("|") and i + 1 < len(lines) and re.match(r"^\|[\s:|-]+\|?\s*$", lines[i + 1]):
            hdr = [c.strip() for c in ln.strip("|").split("|")]
            j = i + 2
            body = []
            while j < len(lines) and lines[j].startswith("|"):
                body.append([c.strip() for c in lines[j].strip("|").split("|")])
                j += 1
            th = "".join(f"<th>{_md_inline(c)}</th>" for c in hdr)
            tb = "".join("<tr>" + "".join(f"<td>{_md_inline(c)}</td>" for c in r) + "</tr>" for r in body)
            out.append(f'<div class="scroll"><table><tr>{th}</tr>{tb}</table></div>')
            i = j
            continue
        h = re.match(r"^(#{1,4})\s+(.*)$", ln)
        if h:
            lvl = min(len(h.group(1)) + 2, 5)
            out.append(f"<h{lvl}>{_md_inline(h.group(2))}</h{lvl}>")
            i += 1
            continue
        if re.match(r"^\s*([-*]|\d+\.)\s+", ln):
            items, j = [], i
            while j < len(lines) and re.match(r"^\s*([-*]|\d+\.)\s+", lines[j]):
                items.append(re.sub(r"^\s*([-*]|\d+\.)\s+", "", lines[j]))
                j += 1
            tag = "ol" if re.match(r"^\s*\d+\.", ln) else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{_md_inline(x)}</li>" for x in items) + f"</{tag}>")
            i = j
            continue
        if ln.startswith(">"):
            quote, j = [], i
            while j < len(lines) and lines[j].startswith(">"):
                quote.append(lines[j].lstrip("> "))
                j += 1
            out.append(f'<blockquote>{_md_inline(" ".join(quote))}</blockquote>')
            i = j
            continue
        if re.match(r"^\s*(---+|\*\*\*+)\s*$", ln):
            out.append("<hr>")
            i += 1
            continue
        if ln.strip():
            para, j = [], i
            while j < len(lines) and lines[j].strip() and not re.match(r"^(#|```|\||>|\s*[-*]\s|\s*\d+\.\s)", lines[j]):
                para.append(lines[j])
                j += 1
            out.append(f"<p>{_md_inline(' '.join(para))}</p>")
            i = j
            continue
        i += 1
    return "".join(out)


_EXT_LANG = {".py": "python", ".js": "javascript", ".ts": "javascript", ".mjs": "javascript",
             ".sh": "bash", ".fish": "bash", ".json": "json", ".html": "html",
             ".go": "go", ".sql": "sql"}


def tool_block(name, obj, raw_json):
    """Render a tool call by TYPE: Edit as a diff, Write as highlighted code,
    Bash as a terminal line, read-tools as a one-line summary; JSON otherwise."""
    def det(summary, body, open_=False):
        return (f'<details class="btool"{" open" if open_ else ""}>'
                f"<summary>▸ {summary}</summary>{body}</details>")
    if name == "Edit" and "old_string" in obj:
        old = "".join(f'<span class="dl del">- {H.escape(l)}</span>'
                      for l in obj["old_string"].splitlines() or [""])
        new = "".join(f'<span class="dl add">+ {H.escape(l)}</span>'
                      for l in obj.get("new_string", "").splitlines() or [""])
        fp = H.escape(obj.get("file_path", ""))
        return det(f"Edit <code>{fp}</code>", f'<pre class="diff">{old}{new}</pre>', True)
    if name in ("Write", "NotebookEdit") and "content" in obj:
        fp = obj.get("file_path", "")
        lang = _EXT_LANG.get(Path(fp).suffix.lower(), "")
        return det(f"Write <code>{H.escape(fp)}</code>",
                   f'<pre class="code"><code>{hl(obj["content"], lang)}</code></pre>')
    if name == "Bash" and "command" in obj:
        desc = f'<span class="dim"> · {H.escape(obj["description"])}</span>' if obj.get("description") else ""
        return det(f"Bash{desc}",
                   f'<pre class="term"><span class="ps1">$</span> {hl(obj["command"], "bash")}</pre>', True)
    if name in ("Read", "Grep", "Glob") and obj:
        arg = obj.get("file_path") or obj.get("pattern") or next(iter(obj.values()), "")
        return (f'<div class="btool oneline">▸ {H.escape(name)} '
                f"<code>{H.escape(str(arg)[:120])}</code></div>")
    return det(H.escape(name), f"<pre>{H.escape(raw_json)}</pre>")


STAGE_ORDER = ["explore", "build", "verify", "ship", "talk"]
STAGE_TOOLS = {"Edit": "build", "Write": "build", "NotebookEdit": "build",
               "Read": "explore", "Grep": "explore", "Glob": "explore",
               "WebFetch": "explore", "WebSearch": "explore", "Agent": "explore",
               "ToolSearch": "explore", "Task": "explore"}


def turn_stage(t):
    """Classify a turn into an INFERRED workflow stage from its tool usage.
    Heuristic on purpose: this is the analysis lane for sessions that did NOT
    run through the kit's gates (foreign agents); kit runs get real gate records."""
    for b in t["blocks"]:
        if b["kind"] != "tool_use":
            continue
        n = b["name"]
        if n == "Bash":
            cmd = (b.get("obj") or {}).get("command", "")
            if re.search(r"\bgit (commit|push|merge)\b|\bgh pr\b", cmd):
                return "ship"
            if re.search(r"\b(test|pytest|go test|npm test|node --check|shellcheck|lint|tsc)\b", cmd):
                return "verify"
            return "build"
        if n in STAGE_TOOLS:
            return STAGE_TOOLS[n]
        if n.startswith("mcp__"):
            return "explore"
    return "talk"


def scope_filter(runs, events, sessions, repos_csv):
    """TEAM scope: keep only the named repos' runs (ledger repo=) and sessions
    (transcript project dir contains the name). Personal mode = no filter, the
    whole host. The filter runs BEFORE any metric, so a team push can never
    leak another project's numbers, not even in an aggregate."""
    repos = [r.strip() for r in (repos_csv or "").split(",") if r.strip()]
    if not repos:
        return runs, events, sessions, {"mode": "personal"}
    runs = [r for r in runs if r["meta"].get("repo") in repos]
    keep = {r["rid"] for r in runs}
    events = [e for e in events if e["rid"] in keep]
    sessions = [s for s in sessions if any(t in s["project"] for t in repos)]
    return runs, events, sessions, {"mode": "team", "repos": repos}


def find_transcript(session_or_path, tdir):
    p = Path(session_or_path)
    if p.exists():
        return p
    root = Path(tdir).expanduser()
    hits = sorted(root.glob(f"*/{session_or_path}*.jsonl"))
    return hits[0] if hits else None


def transcript_page(path, dashboard_href="../index.html", max_chars=4000):
    """Full-transcript page: the actual work (prompts, tool calls, results) with
    per-turn cost, plus commentary + lesson extraction. The pi.dev-shaped view,
    with our gate/conformance framing kept on the run pages it links to."""
    turns, meta = load_transcript(path, max_chars)
    if not turns:
        return None
    rows = ""
    for i, t in enumerate(turns):
        who = "user" if t["role"] == "user" else "agent"
        side = ' <span class="chip dim">subagent</span>' if t["sidechain"] else ""
        cost = f'<span class="tcost">${t["cost"]:.3f}</span>' if t["cost"] else ""
        toks = ""
        if t["tok"]:
            toks = (f'<span class="ttok">{fmt_tok(t["tok"]["output_tokens"])} out · '
                    f'{fmt_tok(t["tok"]["cache_read_input_tokens"])} cache</span>')
        body = ""
        for b in t["blocks"]:
            if b["kind"] == "text":
                # Assistant prose is markdown-rendered; user prompts stay literal
                # (prompts often contain markup-shaped text that must not render).
                if who == "agent":
                    body += f'<div class="btext md">{md_html(b["text"])}</div>'
                else:
                    body += f'<div class="btext">{H.escape(b["text"])}</div>'
            elif b["kind"] == "thinking":
                body += (f'<div class="bthink">thinking · {b["chars"]:,} chars '
                         f"(content not recorded in the transcript)</div>")
            elif b["kind"] == "tool_use":
                body += tool_block(b["name"], b.get("obj") or {}, b["input"])
            elif b["kind"] == "tool_result":
                cls = "bres err" if b["error"] else "bres"
                img = ('<span class="chip dim">image content not stored</span>'
                       if re.match(r"^\s*\[Image", b["text"]) else "")
                body += (f'<details class="{cls}"><summary>'
                         f'{"✗ result (error)" if b["error"] else "◂ result"}{img}</summary>'
                         f'<pre>{H.escape(b["text"])}</pre></details>')
        stamp = (t["ts"] or "")[11:19]
        rows += f"""<div class="turn {who}" id="t{i}">
<div class="thead"><span class="who">{who}</span>{side}
<span class="tstamp">{stamp}</span>{toks}{cost}
<button class="note-btn" data-turn="{i}">note</button>
<button class="lesson-btn" data-turn="{i}">lesson</button></div>
{body}
<textarea class="note" data-note="{i}" hidden placeholder="commentary on this turn (saved in this browser)"></textarea>
</div>"""

    stages = [turn_stage(t) for t in turns]
    stage_counts = Counter(stages)
    strip = "".join(
        f'<a class="st-{s}" href="#t{i}" title="turn {i}: {s}"></a>'
        for i, s in enumerate(stages))
    key = "".join(
        f'<span><i class="st-{s}"></i>{s} ×{stage_counts[s]}</span>'
        for s in STAGE_ORDER if stage_counts[s])
    stage_html = f"""<h2>Workflow shape <span class="chip warn">inferred</span></h2>
<p class="meta">Stages inferred from tool usage per turn (read/search = explore,
edit/write = build, tests = verify, git commit/push = ship). This is the analysis
lane for sessions that did not run through the kit's gates; a kit run gets real
gate records on its session page instead of a guess. Click a segment to jump to
the turn.</p>
<div class="stagebar">{strip}</div>
<div class="stagekey">{key}</div>"""

    models = ", ".join(f"{m.split('-')[1] if '-' in m else m} ×{n}"
                       for m, n in meta["models"].most_common(4)) or "-"
    tools = ", ".join(f"{t} ×{n}" for t, n in meta["tools"].most_common(6)) or "none"
    red = meta["redactions"]
    red_note = (f'<span class="chip warn">{red} secret-shaped strings redacted</span>'
                if red else '<span class="chip ok">no secret shapes matched</span>')
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{H.escape(meta['session'][:12])} · Forge transcript</title>
<meta name="robots" content="noindex">
{SESSION_STYLE}
{TRANSCRIPT_STYLE}
</head>
<body>
<div class="spine"></div>
<main>
<div class="crumb"><a href="{dashboard_href}">&larr; control plane</a>
<span><button id="collapse">Collapse all tools</button>
<button id="export">Export notes</button>
<button id="share">Share</button></span></div>
<div class="eyebrow">Session transcript</div>
<h1>{H.escape(meta['session'][:24])}</h1>
<p class="meta">{H.escape(meta['project'])} · {(meta['t0'] or '')[:10]} ·
{len(turns)} turns · {models}{' · branch ' + H.escape(meta['branch']) if meta['branch'] else ''}</p>

<div class="tiles">
<div class="tile"><b>${meta['cost']:.2f}</b><span>computed cost</span></div>
<div class="tile"><b>{fmt_tok(meta['tok']['output_tokens'])}</b><span>output tokens</span></div>
<div class="tile"><b>{fmt_tok(meta['tok']['cache_read_input_tokens'])}</b><span>cache read</span></div>
<div class="tile"><b>{sum(meta['tools'].values())}</b><span>tool calls</span></div>
</div>
<p class="meta">Tools: {H.escape(tools)}. {red_note}
Redaction is a best-effort mask over free-form text, not a guarantee: review before
sharing a transcript outside the team. Tool inputs/results over {max_chars:,} chars are
truncated ({meta['truncated']} truncations here); thinking content is not stored in the
transcript, only its size.</p>

{stage_html}

<h2>Transcript</h2>
<p class="meta">Every turn as it happened. Use <b>note</b> to comment on a turn and
<b>lesson</b> to copy it as a markdown lesson for the learning ledger. Notes live in this
browser only (nothing is uploaded).</p>
{rows}
<p class="foot">FORGE · transcript rendered from the local session log ·
{now().isoformat(timespec="seconds")}</p>
</main>
<script>
const LS="forge-notes-"+location.pathname;
const notes=JSON.parse(localStorage.getItem(LS)||"{{}}");
document.querySelectorAll("textarea.note").forEach(ta=>{{
  const k=ta.dataset.note;
  if(notes[k]){{ta.value=notes[k];ta.hidden=false;}}
  ta.addEventListener("input",()=>{{notes[k]=ta.value;
    localStorage.setItem(LS,JSON.stringify(notes));}});
}});
document.querySelectorAll(".note-btn").forEach(b=>b.onclick=()=>{{
  const ta=document.querySelector(`textarea[data-note="${{b.dataset.turn}}"]`);
  ta.hidden=!ta.hidden; if(!ta.hidden)ta.focus();
}});
document.querySelectorAll(".lesson-btn").forEach(b=>b.onclick=()=>{{
  const turn=document.getElementById("t"+b.dataset.turn);
  const txt=turn.querySelector(".btext")?.textContent||"";
  const tool=turn.querySelector(".btool summary")?.textContent||"";
  const note=turn.querySelector("textarea.note")?.value||"";
  const md=["## Lesson from "+document.title,
            "",
            "**Turn:** "+b.dataset.turn+(tool?" ("+tool.trim()+")":""),
            "**Source:** "+location.href+"#t"+b.dataset.turn,
            "",
            note?"**Commentary:** "+note:"**Commentary:** (add yours)",
            "",
            "> "+txt.trim().slice(0,600).replace(/\\n/g,"\\n> ")].join("\\n");
  const done=()=>{{const o=b.textContent;b.textContent="copied";
    setTimeout(()=>b.textContent=o,1200);}};
  if(navigator.clipboard)navigator.clipboard.writeText(md).then(done,done);
}});
document.getElementById("collapse").onclick=e=>{{
  const any=[...document.querySelectorAll("details")].some(d=>d.open);
  document.querySelectorAll("details").forEach(d=>d.open=!any);
  e.target.textContent=any?"Expand all tools":"Collapse all tools";
}};
document.getElementById("export").onclick=()=>{{
  const out=Object.entries(notes).filter(([,v])=>v.trim())
    .map(([k,v])=>`- **turn ${{k}}** (${{location.href}}#t${{k}}): ${{v}}`).join("\\n");
  const md="# Notes on "+document.title+"\\n\\n"+(out||"_no notes yet_");
  const blob=new Blob([md],{{type:"text/markdown"}});
  const a=document.createElement("a");a.href=URL.createObjectURL(blob);
  a.download="session-notes.md";a.click();URL.revokeObjectURL(a.href);
}};
document.getElementById("share").onclick=()=>{{
  const b=document.getElementById("share");
  navigator.clipboard?.writeText(location.href).then(()=>{{
    b.textContent="Link copied";setTimeout(()=>b.textContent="Share",1400);}});
}};
</script>
</body>
</html>"""


def session_detail(rid, log_dir, dashboard_href="../index.html"):
    """One standalone session page (the pi.dev-shaped unit of sharing).

    Self-contained: its own <style>, no dependency on the dashboard bundle, so a
    shared link opens fast and works on its own. Renders the routing decision,
    the full gate timeline with reasons, expected-vs-actual ghost rows, ship
    outcomes, debt markers, and the replay command."""
    path = Path(log_dir) / "runs" / f"{rid}.log"
    if not path.exists():
        return None
    meta, timeline, outcomes, debts = {}, [], [], []
    t0 = t1 = None
    for line in path.read_text().splitlines():
        parts = [x.strip() for x in line.split(" | ", 3)]
        if len(parts) < 3:
            continue
        try:
            ts = dtm.datetime.fromisoformat(parts[0].replace("Z", "+00:00"))
        except ValueError:
            continue
        t0, t1 = t0 or ts, ts
        kind = parts[1]
        if kind == "START":
            for tok in parts[2].split():
                k, _, v = tok.partition("=")
                meta.setdefault(k, v)
        elif kind == "GATE" and len(parts) == 4:
            status, _, reason = parts[3].partition(" | ")
            timeline.append({"ts": ts, "phase": parts[2], "status": status.strip(),
                             "reason": reason.strip()})
        elif kind == "OUTCOME" and len(parts) == 4:
            outcomes.append({"ts": ts, "phase": parts[2], "detail": parts[3]})
        elif kind == "DEBT":
            debts.append({"ts": ts, "detail": parts[2].replace("-", " ")})

    lane = meta.get("lane", "")
    plan = expected_plan(lane) if lane else []
    recorded = {e["phase"] for e in timeline}
    req = [ph for ph, lvl in plan if "required" in lvl]
    seen_last = {}
    for e in timeline:
        seen_last[e["phase"]] = e["status"]
    present = sum(1 for ph in req if seen_last.get(ph) in ("ran", "override"))
    missed = [ph for ph, lvl in plan if ph not in recorded]
    misfire = bool(lane and meta.get("classified") and lane != meta["classified"])
    mins = round((t1 - t0).total_seconds() / 60) if t0 and t1 else 0
    conf_ok = req and present == len(req)

    # The lane's expected plan as a visual stepper: what the kit promised this
    # run would walk through, decorated with what actually happened.
    stepper = ""
    if plan:
        glyph = {"ran": ("ok", "●"), "override": ("ovr", "⚑"), "skipped": ("skip", "○")}
        nodes = ""
        for ph, lvl in plan:
            st = seen_last.get(ph)
            required = "required" in lvl
            cls, g = glyph.get(st, ("miss", "◌") if required else ("opt", "·"))
            tag = "" if st or not required else " never recorded"
            nodes += (f'<div class="step {cls}" title="{H.escape(ph)}: '
                      f'{H.escape(st or ("expected" + tag) if required else (st or "optional"))}">'
                      f'<span class="g">{g}</span><span class="l">{H.escape(ph)}</span></div>')
        stepper = f"""<h2>Lane plan · {H.escape(lane)}</h2>
<p class="meta">The workflow this run was classified into, decorated with the record:
● ran · ○ skipped with reason · ⚑ overridden with reason · ◌ expected but never
recorded · <span class=dim>· optional, not exercised</span>.</p>
<div class="stepper">{nodes}</div>"""

    rows = ""
    for e in timeline:
        rows += (f'<tr class="s-{e["status"]}"><td class=mono>{e["ts"].strftime("%m-%d %H:%M:%S")}</td>'
                 f'<td class=mono>{H.escape(e["phase"])}</td><td>{_chip(e["status"])}</td>'
                 f'<td>{H.escape(e["reason"]) or "<span class=dim>no reason recorded</span>"}</td></tr>')
    for ph in missed:
        lvl = dict(plan).get(ph, "")
        rows += (f'<tr class="s-missed"><td class=mono>&mdash;</td><td class=mono>{H.escape(ph)}</td>'
                 f'<td><span class="chip bad">◌ MISSED</span></td>'
                 f'<td class=dim>expected by the {H.escape(lane)} lane ({H.escape(lvl)}), '
                 f"never recorded</td></tr>")
    out_rows = "".join(
        f'<tr><td class=mono>{o["ts"].strftime("%m-%d %H:%M:%S")}</td>'
        f'<td class=mono>{H.escape(o["phase"])}</td><td class=mono>{H.escape(o["detail"])}</td></tr>'
        for o in outcomes) or '<tr><td colspan=3 class=dim>no ship outcomes recorded</td></tr>'
    debt_rows = "".join(
        f'<tr><td class=mono>{d["ts"].date()}</td><td>{H.escape(d["detail"][:400])}</td></tr>'
        for d in debts)
    debt_block = (f"<h2>Understanding debt</h2><table>{debt_rows}</table>" if debts else "")

    conf_chip = (f'<span class="chip {"ok" if conf_ok else "bad"}">{present}/{len(req)}</span>'
                 if req else '<span class="chip dim">n/a</span>')
    ran = sum(1 for e in timeline if e["status"] == "ran")
    skipped = sum(1 for e in timeline if e["status"] == "skipped")
    over = sum(1 for e in timeline if e["status"] == "override")

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{H.escape(rid)} · Forge session</title>
<meta name="description" content="Forge session log for run {H.escape(rid)}: gate timeline, conformance, outcomes.">
{SESSION_STYLE}
</head>
<body>
<div class="spine"></div>
<main>
<div class="crumb"><a href="{dashboard_href}">&larr; control plane</a>
<button id="share">Share this session</button></div>
<div class="eyebrow">Session log</div>
<h1>{H.escape(rid)}</h1>
<p class="meta">{H.escape(meta.get("repo", "unknown repo"))} ·
{H.escape(meta.get("type", "unknown type"))} ·
{t0.date() if t0 else "?"} · {mins} min
{' · <span class="chip warn">lane misfire</span>' if misfire else ''}</p>

<div class="tiles">
<div class="tile"><b>{H.escape(lane) or "?"}</b><span>lane
{"(classifier said " + H.escape(meta.get("classified", "")) + ")" if misfire else "(classifier agreed)"}</span></div>
<div class="tile"><b>{conf_chip}</b><span>required gates present</span></div>
<div class="tile"><b>{ran} ● {skipped} ○ {over} ⚑</b><span>ran / skipped / overridden</span></div>
<div class="tile"><b>{len(timeline)}</b><span>gate events</span></div>
</div>

{stepper}

<h2>Gate timeline</h2>
<p class="meta">Every recorded decision, in order, with the reason it carried. Rows marked
<span class="chip bad">◌ MISSED</span> are gates the lane expected that this run never recorded.</p>
<div class="scroll"><table><tr><th>time</th><th>gate</th><th>verdict</th><th>reason</th></tr>
{rows}</table></div>

<h2>Ship outcomes</h2>
<table><tr><th>time</th><th>phase</th><th>detail</th></tr>{out_rows}</table>
{debt_block}

<h2>Reproduce</h2>
<pre>forge-tui run {H.escape(rid)}
bash lib/telemetry/lane-telemetry.sh trace {H.escape(rid)}</pre>
<p class="foot">FORGE · session log rendered from the append-only gate ledger ·
{now().isoformat(timespec="seconds")}</p>
</main>
<script>
document.getElementById("share").onclick=()=>{{
  const u=location.href;
  const b=document.getElementById("share");
  const done=()=>{{b.textContent="Link copied";setTimeout(()=>b.textContent="Share this session",1400);}};
  if(navigator.clipboard)navigator.clipboard.writeText(u).then(done,done);
  else{{const t=document.createElement("textarea");t.value=u;document.body.appendChild(t);
    t.select();document.execCommand("copy");t.remove();done();}}
}};
</script>
</body>
</html>"""


def session_index(rids, out_dir):
    rows = "".join(f'<tr><td><a href="{H.escape(r)}.html"><code>{H.escape(r)}</code></a></td></tr>'
                   for r in sorted(rids))
    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Forge session logs</title>{SESSION_STYLE}</head><body>
<div class="spine"></div><main>
<div class="crumb"><a href="../index.html">&larr; control plane</a></div>
<div class="eyebrow">Session logs</div><h1>All sessions</h1>
<p class="meta">{len(rids)} recorded runs. Each page is standalone and shareable.</p>
<div class="scroll"><table><tr><th>run</th></tr>{rows}</table></div>
</main></body></html>"""


# Behavior for the exported fleet sections. Runs inside the forge SPA after the
# fragments are injected; the SPA supplies routing via window.forgeShow and calls
# window.forgeFleetInit() exactly once per data load.
FLEET_JS = r"""
window.forgeFleetInit=function(){
function show(id){if(window.forgeShow)window.forgeShow(id);}
function openRun(rid,scroll){
  show("explorer");
  const row=document.querySelector(`tr.exrow[data-rid="${rid.toLowerCase()}"]`);
  const det=document.querySelector(`tr.detail[data-detail="${rid.toLowerCase()}"]`);
  if(det)det.hidden=false;
  if(row){row.style.outline="2px solid var(--ember)";
    if(scroll)row.scrollIntoView({block:"center"});}
  return !!row;
}
window.forgeOpenRun=openRun;
document.querySelectorAll("button.share").forEach(b=>b.onclick=e=>{
  e.stopPropagation();
  const url=location.origin+location.pathname+"#run/"+encodeURIComponent(b.dataset.share);
  const done=()=>{const t=b.textContent;b.textContent="copied";
    setTimeout(()=>b.textContent=t,1200);};
  if(navigator.clipboard)navigator.clipboard.writeText(url).then(done,done);
  else{const ta=document.createElement("textarea");ta.value=url;document.body.appendChild(ta);
    ta.select();document.execCommand("copy");ta.remove();done();}
  history.replaceState(null,"","#run/"+encodeURIComponent(b.dataset.share));
});
let seg="";
const q=document.getElementById("q");
function filt(){
  if(!q)return;
  const t=q.value.toLowerCase();
  document.querySelectorAll("#ex tr[data-k]").forEach(r=>{
    const k=r.dataset.k;
    r.style.display=(k.includes(t)&&(seg===""||k.includes(seg)))?"":"none";
  });
}
if(q)q.oninput=filt;
document.querySelectorAll(".seg-bar button[data-seg]").forEach(b=>b.onclick=()=>{
  seg=b.dataset.seg;
  document.querySelectorAll(".seg-bar button[data-seg]").forEach(x=>x.classList.toggle("on",x===b));
  filt();
});
document.querySelectorAll("tr.exrow").forEach(r=>{
  const open=()=>{const d=document.querySelector(`tr.detail[data-detail="${r.dataset.rid}"]`);
    if(d)d.hidden=!d.hidden;};
  r.onclick=e=>{if(!e.target.closest("a"))open();};
  r.onkeydown=e=>{if(e.key==="Enter"||e.key===" "){e.preventDefault();open();}};
});
const red=document.getElementById("redact-toggle");
if(red)red.onclick=()=>{
  const on=document.body.classList.toggle("redacted");
  red.setAttribute("aria-pressed",String(on));
  red.textContent=on?"Redacted (click to show)":"Redact mode";
};
const csvBtn=document.getElementById("audit-csv");
if(csvBtn)csvBtn.onclick=()=>{
  const rows=[["time","rid","gate","verdict","reason"]];
  document.querySelectorAll("#stream table tr").forEach(tr=>{
    const c=tr.querySelectorAll("td");
    if(c.length===5)rows.push([...c].map(td=>'"'+td.textContent.trim().replace(/"/g,'""')+'"'));
  });
  const blob=new Blob([rows.map(r=>r.join(",")).join("\n")],{type:"text/csv"});
  const a=document.createElement("a");
  a.href=URL.createObjectURL(blob);a.download="forge-audit.csv";a.click();
  URL.revokeObjectURL(a.href);
};
document.querySelectorAll(".rule-add").forEach(b=>b.onclick=()=>{
  const cap=b.dataset.cap;
  const inp=document.querySelector(`.rule-match[data-cap="${cap}"]`);
  const m=(inp.value||"").trim();
  if(!m)return;
  const tbl=document.querySelector(`.cap-table[data-cap="${cap}"]`);
  const tr=document.createElement("tr");
  tr.dataset.cap=cap;tr.dataset.custom="1";
  tr.innerHTML=`<td>custom rule</td><td><code>${m}</code></td>`+
    `<td><select class="prov-act"><option>allow</option><option selected>ask</option>`+
    `<option>deny</option></select></td><td><button class="act rule-rm">remove</button></td>`;
  tbl.appendChild(tr);
  inp.value="";
  tr.querySelector(".rule-rm").onclick=()=>tr.remove();
});
document.querySelectorAll(".rule-rm").forEach(b=>b.onclick=()=>b.closest("tr").remove());
const pex=document.getElementById("policy-export");
if(pex)pex.onclick=()=>{
  const base=JSON.parse(document.getElementById("policy-data").textContent);
  const caps=base.capabilities||{};
  for(const cid of Object.keys(caps)){
    const cap=caps[cid];
    const pref=document.querySelector(`.cap-pref[data-cap="${cid}"]`);
    if(pref)cap.preferred=pref.value;
    document.querySelectorAll(`.cap-table[data-cap="${cid}"] tr[data-provider]`).forEach(tr=>{
      const pv=(cap.providers||[]).find(x=>x.id===tr.dataset.provider);
      const s=tr.querySelector("select.prov-act");
      if(pv&&s)pv.action=s.value;
    });
    cap.rules=[];
    document.querySelectorAll(`.cap-table[data-cap="${cid}"] tr[data-custom],`+
      `.cap-table[data-cap="${cid}"] tr[data-rule]`).forEach(tr=>{
      const m=tr.querySelector("code");
      const s=tr.querySelector("select.prov-act");
      if(m&&s)cap.rules.push({match:m.textContent,action:s.value});
    });
  }
  const out=document.getElementById("policy-out");
  out.style.display="block";
  out.value=JSON.stringify(base,null,2);
  out.select();
  const blob=new Blob([out.value],{type:"application/json"});
  const a=document.createElement("a");
  a.href=URL.createObjectURL(blob);a.download="tool-policy.json";a.click();
  URL.revokeObjectURL(a.href);
};
const cex=document.getElementById("cfg-export");
if(cex)cex.onclick=()=>{
  const changed={};
  document.querySelectorAll("input.cfg-key").forEach(i=>{
    if(i.value!==i.dataset.orig){
      (changed[i.dataset.section]=changed[i.dataset.section]||{})[i.dataset.key]=i.value;
    }
  });
  let toml="# .kit.toml , per-project overrides (changed keys only; the rest inherit)\n";
  for(const sec of Object.keys(changed)){
    toml+=`\n[${sec}]\n`;
    for(const k of Object.keys(changed[sec])){
      const v=changed[sec][k];
      toml+=`${k} = ${/^(true|false|-?\d+(\.\d+)?)$/.test(v)?v:JSON.stringify(v)}\n`;
    }
  }
  const out=document.getElementById("cfg-out");
  out.hidden=false;
  out.value=Object.keys(changed).length?toml:"# no keys changed";
  out.select();
};
};
"""


def render_sections(runs, events, sessions, bench_rows, metrics, alerts, money=None,
                    debt=None, config=None, policy=None, runtimes=None, alloc=None):
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
        + area_chart(m["trend_conf"], m["days"], "Full-conformance runs per day")
        + stacked_weeks(m["lane_weeks"], "Runs by lane · weekly")
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
                    f'<td><a class="rid-link" href="sessions/{H.escape(r["rid"])}.html">'
                    f'<code>{H.escape(r["rid"])}</code></a>{mis}</td>'
                    f"<td>{r['t1'].date()}</td><td>{H.escape(r['meta'].get('repo', ''))}</td>"
                    f"<td>{H.escape(lane)}</td><td>{H.escape(r['meta'].get('type', ''))}</td>"
                    f"<td>{counts}</td><td>{conf_html}</td><td>{mins:.0f}m "
                    f'<button class="act share" data-share="{H.escape(r["rid"])}"'
                    f' title="copy permalink">share</button></td></tr>') + detail

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
        f'<tr><td><a class="rid-link" href="transcripts/{H.escape(s["session"])}.html">'
        f'<code>{H.escape(s["session"])}</code></a></td><td>{H.escape(s["project"])}</td>'
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
    cost_sec, runtime_sec = money_sections(mm)
    eff_rank = efficiency_rankings(sessions)
    eff_sec = efficiency_section(eff_rank)
    alloc_sec = allocation_section(alloc)
    debt_sec = debt_section(dm)
    config_sec = config_section(config, policy, runtimes)

    sections = {
        "fleet": f"""<section id="fleet">
<div class="eyebrow">Control plane</div>
<h1>Fleet</h1>
<p class="meta">Every number reads from the append-only run ledgers. Nothing on this
page is hand-entered; a correction is a new run, never an edit.</p>
<div class="tiles">{tiles}</div>
<div class="charts">{charts}</div>
</section>""",
        "explorer": f"""<section id="explorer">
<div class="eyebrow">Observe</div>
<h1>Run explorer</h1>
<p class="meta">{len(runs)} recorded runs. Click a run id for its standalone session-log page (shareable on its own); click the row to expand the log inline. Segments are saved filters; conformance =
required gates present for the run's lane. Replay any row:
<span class=mono>forge-tui run &lt;rid&gt;</span>.</p>
<div class="seg-bar"><input id="q" placeholder="filter rid / repo / lane...">{segs}</div>
<div class="scroll"><table id="ex"><tr><th>rid</th><th>last event</th><th>repo</th>
<th>lane</th><th>type</th><th>gates</th><th>conformance</th><th>span</th></tr>
{ex_rows}</table></div>
</section>""",
        "stream": f"""<section id="stream">
<div class="eyebrow">Observe</div>
<h1>Event stream</h1>
<p class="meta">Latest {len(stream)} gate verdicts across every run; the reason is the
audit trail.</p>
<div class="seg-bar">
<button id="audit-csv">Download audit CSV</button>
</div>
<div class="scroll"><table><tr><th>time</th><th>rid</th><th>gate</th><th>verdict</th>
<th>reason</th></tr>{ev_rows}</table></div>
</section>""",
        "tools": f"""<section id="tools">
<div class="eyebrow">Observe</div>
<h1>Tool activity</h1>
<p class="meta">{len(sessions)} recent sessions from this host's Claude Code transcripts,
counts only: tool names, models, timing. Message content is never read into this page.
A session id opens its full-transcript page when rendered
(<span class=mono>dashboard.py transcripts</span> alongside the export).
MCP servers seen: {mcp_html}.</p>
<div class="charts">{top_tools}</div>
<div class="scroll"><table><tr><th>session</th><th>project</th><th>model</th><th>span</th>
<th>tool calls</th><th>top tools</th></tr>{sess_rows}</table></div>
</section>""",
        "cost": cost_sec,
        "efficiency": eff_sec,
        "allocation": alloc_sec,
        "runtime": runtime_sec,
        "debt": debt_sec,
        "config": (f'<script type="application/json" id="policy-data">{policy_json}</script>'
                   + config_sec),
        "bench": f"""<section id="bench">
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
</section>""",
        "alerts": f"""<section id="alerts">
<div class="eyebrow">Verify</div>
<h1>Alerts</h1>
<p class="meta">Template rules from a plain JSON file, evaluated at export over the
{m['window_days']}-day window. Propose-first: no daemon, no auto-fix. {len(firing)} firing.</p>
<table><tr><th>rule</th><th>condition</th><th>value</th><th>state</th><th>note</th></tr>
{al_rows}</table>
</section>""",
    }
    counts = {"runs": len(runs), "events": len(events), "sessions": len(sessions),
              "bench_cells": len(bench_rows), "alerts_firing": len(firing)}
    return {"schema": 1, "generated_at": gen, "window_days": m["window_days"],
            "counts": counts, "sections": sections, "js": FLEET_JS}


def main():
    ap = argparse.ArgumentParser(prog="bench-dashboard", description=__doc__)
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("export", help="emit the fleet data payload (sections.json) "
                                      "consumed by the forge dashboard SPA")
    b.add_argument("--log-dir", default=os.environ.get(
        "DWARVES_KIT_LOG_DIR", str(Path.home() / ".local/state/dwarves-kit/logs")))
    b.add_argument("--transcripts-dir", default=str(Path.home() / ".claude/projects"))
    b.add_argument("--max-transcripts", type=int, default=25)
    b.add_argument("--alerts", default=None, help="JSON rules file; default built-ins")
    b.add_argument("--window-days", type=int, default=30)
    b.add_argument("--period", choices=("week", "month"), default="week",
                   help="bucket size for the allocation view")
    b.add_argument("--monthly-budget", type=float, default=None,
                   help="USD budget for the pool-headroom gauge (operator input)")
    b.add_argument("--tool-policy", default=None,
                   help="tool-policy JSON to render (default: ~/.claude/dwarves-kit/tool-policy.json)")
    b.add_argument("--out", default="sections.json")
    b.add_argument("--push", default=None, metavar="API_URL",
                   help="also PUT the payload to <API_URL>/admin/observe "
                        "(Bearer token from FORGE_ADMIN_TOKEN)")
    b.add_argument("--repos", default=None, metavar="A,B",
                   help="TEAM scope: only these repos' runs + sessions enter the "
                        "payload (default: personal scope, the whole host)")
    old = sub.add_parser("build", help="RETIRED: the page is the forge SPA; use export")
    old.add_argument("--out", default=None, help=argparse.SUPPRESS)
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
    al = sub.add_parser("allocation", help="pool -> member -> feature report + plan")
    al.add_argument("--period", choices=("week", "month"), default="week")
    al.add_argument("--budget", type=float, default=None,
                    help="next-period pool; enables the proposed allowance plan")
    al.add_argument("--format", choices=("text", "json", "md"), default="text")
    al.add_argument("--transcripts-dir", default=str(Path.home() / ".claude/projects"))
    al.add_argument("--max-transcripts", type=int, default=120)
    tr = sub.add_parser("transcript", help="render ONE full-transcript page (opt-in: reads content)")
    tr.add_argument("session", help="session id (or a path to the .jsonl)")
    tr.add_argument("--out", default="transcript.html")
    tra = sub.add_parser("transcripts", help="render the most recent N transcript pages + index")
    tra.add_argument("--out-dir", default="transcripts")
    tra.add_argument("--limit", type=int, default=20)
    for x in (tr, tra):
        x.add_argument("--transcripts-dir", default=str(Path.home() / ".claude/projects"))
        x.add_argument("--max-chars", type=int, default=4000,
                       help="truncate tool inputs/results past this many chars")
        x.add_argument("--dashboard", default="../index.html")
    sess = sub.add_parser("session", help="render ONE standalone session detail page")
    sess.add_argument("rid")
    sess.add_argument("--out", default="session.html")
    sessa = sub.add_parser("sessions", help="render a session page per run + an index")
    sessa.add_argument("--out-dir", default="sessions")
    for x in (sess, sessa):
        x.add_argument("--log-dir", default=os.environ.get(
            "DWARVES_KIT_LOG_DIR", str(Path.home() / ".local/state/dwarves-kit/logs")))
        x.add_argument("--dashboard", default="../index.html",
                       help="href back to the control plane")
    a = ap.parse_args()

    if a.cmd == "build":
        print("build is retired (one-page rule, 2026-07-25): the dashboard page is the\n"
              "forge SPA at forge/site/dashboard/. Emit its data with:\n"
              "  python3 dashboard.py export --out <site>/dashboard/data/sections.json\n"
              "Single-file bundle for sharing: forge site/dashboard/bundle.py",
              file=sys.stderr)
        sys.exit(2)

    if a.cmd == "allocation":
        sess = collect_sessions(a.transcripts_dir, a.max_transcripts)
        al = allocation_metrics(sess, a.period, a.budget)
        if a.format == "json":
            print(json.dumps(al, indent=1, default=str))
        elif a.format == "md":
            print(allocation_markdown(al))
        elif not al:
            print("no dated sessions to allocate", file=sys.stderr)
        else:
            print(f"pool {al['current_key']} ({al['period']}ly): ${al['current_total']:,.2f}"
                  + (f"  ({al['current_total'] - al['prev_total']:+,.2f} vs {al['prev_key']})"
                     if al["prev_total"] else ""))
            for m in al["members"]:
                top = ", ".join(f"{f['name']}:${f['cost']:,.0f}" for f in m["features"][:3])
                print(f"  {m['member'][:22]:22} ${m['cost']:>9,.2f} {m['share']:>4.0%} "
                      f"[{m['grade'] or '-'}]  {top}")
            for p_ in al["plan"]:
                print(f"  plan {p_['member'][:20]:20} ${p_['current']:>9,.2f} -> "
                      f"${p_['proposed']:>9,.2f}  {p_['reason'][:70]}")
            if al.get("unallocated"):
                print(f"  unallocated headroom: ${al['unallocated']:,.2f}")
        return

    if a.cmd == "transcript":
        path = find_transcript(a.session, a.transcripts_dir)
        if not path:
            print(f"no transcript found for {a.session}", file=sys.stderr)
            return
        page = transcript_page(path, a.dashboard, a.max_chars)
        if not page:
            print(f"transcript {path} has no renderable turns", file=sys.stderr)
            return
        Path(a.out).write_text(page)
        print(f"transcript page written to {a.out} (from {path.name})", file=sys.stderr)
        return

    if a.cmd == "transcripts":
        root = Path(a.transcripts_dir).expanduser()
        outdir = Path(a.out_dir)
        outdir.mkdir(parents=True, exist_ok=True)
        files = sorted(root.glob("*/*.jsonl"), key=lambda f: f.stat().st_mtime, reverse=True)
        made, rows = 0, []
        for f in files[:a.limit]:
            page = transcript_page(f, a.dashboard, a.max_chars)
            if not page:
                continue
            (outdir / f"{f.stem}.html").write_text(page)
            made += 1
            rows.append(f.stem)
        idx = "".join(f'<tr><td><a href="{r}.html"><code>{r[:24]}</code></a></td></tr>'
                      for r in rows)
        (outdir / "index.html").write_text(f"""<!DOCTYPE html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Forge transcripts</title>{SESSION_STYLE}</head>
<body><div class="spine"></div><main>
<div class="crumb"><a href="{a.dashboard}">&larr; control plane</a></div>
<div class="eyebrow">Transcripts</div><h1>Session transcripts</h1>
<p class="meta">{made} rendered. Content is redacted best-effort; treat as internal.</p>
<div class="scroll"><table><tr><th>session</th></tr>{idx}</table></div></main></body></html>""")
        print(f"{made} transcript pages + index written to {outdir}", file=sys.stderr)
        return

    if a.cmd == "session":
        page = session_detail(a.rid, a.log_dir, a.dashboard)
        if page is None:
            print(f"no run ledger for {a.rid}", file=sys.stderr)
            return
        Path(a.out).write_text(page)
        print(f"session page written to {a.out}", file=sys.stderr)
        return

    if a.cmd == "sessions":
        outdir = Path(a.out_dir)
        outdir.mkdir(parents=True, exist_ok=True)
        rids = [f.stem for f in (Path(a.log_dir) / "runs").glob("*.log")]
        made = 0
        for rid in rids:
            page = session_detail(rid, a.log_dir, a.dashboard)
            if page:
                (outdir / f"{rid}.html").write_text(page)
                made += 1
        (outdir / "index.html").write_text(session_index(rids, outdir))
        print(f"{made} session pages + index written to {outdir}", file=sys.stderr)
        return

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
    runs, events, sessions, scope = scope_filter(
        runs, events, sessions, getattr(a, "repos", None))
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
    payload = render_sections(runs, events, sessions, bench_rows, metrics, alerts, money,
                              debt=dm, config=collect_config(), policy=policy,
                              runtimes=collect_runtimes(),
                              alloc=allocation_metrics(sessions, a.period, a.monthly_budget))
    payload["scope"] = scope
    body = json.dumps(payload)
    Path(a.out).write_text(body)
    c = payload["counts"]
    print(f"fleet payload written to {a.out}: {c['runs']} runs, {c['events']} events, "
          f"{c['sessions']} sessions, {c['bench_cells']} bench cells, "
          f"{c['alerts_firing']} alerts firing", file=sys.stderr)
    if a.push:
        token = os.environ.get("FORGE_ADMIN_TOKEN")
        if not token:
            print("--push needs FORGE_ADMIN_TOKEN in the environment", file=sys.stderr)
            sys.exit(1)
        import urllib.request
        req = urllib.request.Request(
            a.push.rstrip("/") + "/admin/observe", data=body.encode(),
            # UA matters: Cloudflare's bot filter 403s the default Python-urllib UA
            headers={"Authorization": f"Bearer {token}",
                     "Content-Type": "application/json",
                     "User-Agent": "dwarves-kit-observe/1"}, method="PUT")
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"pushed to {a.push}/admin/observe: HTTP {resp.status}", file=sys.stderr)


if __name__ == "__main__":
    main()
