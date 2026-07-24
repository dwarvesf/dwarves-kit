"""Offline self-check for dashboard.py: fixture ledgers + fixture transcripts,
no dependence on this host's real logs."""
import datetime as dtm
import json
from collections import Counter
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import dashboard  # noqa: E402

NOW = dtm.datetime.now(dtm.timezone.utc)


def _ledger(ts_offset_min, lane="full", classified="full", phases=(("build", "ran", "ok"),)):
    t = (NOW - dtm.timedelta(minutes=ts_offset_min)).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [f"{t} | START | lane={lane} classified={classified} type=spec-feature repo=demo"]
    lines += [f"{t} | GATE | {p} | {s} | {r}" for p, s, r in phases]
    return "\n".join(lines) + "\n"


def _fixture_logs(d):
    runs = Path(d, "runs")
    runs.mkdir()
    (runs / "clean.log").write_text(_ledger(60, phases=[
        ("think", "ran", "read"), ("build", "ran", "code"), ("ship", "ran", "pr")]))
    (runs / "misfired.log").write_text(_ledger(120, lane="tiny", classified="full",
                                               phases=[("build", "ran", "code")]))
    (runs / "overridden.log").write_text(_ledger(30, phases=[
        ("build", "ran", "code"), ("reflect", "override", "conductor owns retro")]))
    return d


def test_collect_and_metrics():
    with tempfile.TemporaryDirectory() as d:
        _fixture_logs(d)
        runs = dashboard.collect_runs(d)
        assert len(runs) == 3
        assert sum(1 for r in runs if r["misfire"]) == 1
        m = dashboard.fleet_metrics(runs, dashboard.collect_events(d), 30)
        assert m["runs"] == 3 and m["misfires"] == 1
        assert m["overridden"] == 1
        assert len(m["trend_runs"]) == 30 and sum(m["trend_runs"]) == 3
        evs = dashboard.collect_events(d)
        assert len(evs) == 6 and evs[0]["ts"] >= evs[-1]["ts"]


def test_alert_rules_fire():
    m = {"override_rate": 0.5, "misfire_rate": 0.0, "skip_rate": 0.1, "runs": 3}
    fired = {a["id"]: a["firing"] for a in dashboard.eval_alerts(m, dashboard.DEFAULT_ALERTS)}
    assert fired["override-rate"] is True
    assert fired["misfire-rate"] is False
    assert fired["no-runs"] is False


def test_sessions_counts_only():
    """Transcript scan must aggregate tool names and never leak content text."""
    with tempfile.TemporaryDirectory() as d:
        proj = Path(d, "proj-demo")
        proj.mkdir()
        lines = [
            {"timestamp": "2026-07-25T01:00:00Z", "message": {"model": "claude-sonnet-5",
             "content": [{"type": "tool_use", "name": "Bash"},
                         {"type": "text", "text": "SECRET-CONTENT-NEVER-RENDER"}]}},
            {"timestamp": "2026-07-25T01:10:00Z", "message": {"content": [
                {"type": "tool_use", "name": "mcp__figma__get_figma_data"}]}},
        ]
        (proj / "sess1.jsonl").write_text("\n".join(json.dumps(x) for x in lines))
        sessions = dashboard.collect_sessions(d, 5)
        assert len(sessions) == 1
        s = sessions[0]
        assert s["tools"]["Bash"] == 1 and s["mins"] == 10
        assert not any("SECRET-CONTENT" in k for k in s["tools"])


def test_render_end_to_end_with_fixtures():
    with tempfile.TemporaryDirectory() as d:
        _fixture_logs(d)
        runs = dashboard.collect_runs(d)
        m = dashboard.fleet_metrics(runs, dashboard.collect_events(d), 30)
        out = Path(d, "dash.html")
        dashboard.render(runs, dashboard.collect_events(d),
                         [{"session": "abc", "project": "demo",
                           "models": Counter({"claude-sonnet-5": 1}),
                           "tools": Counter({"Bash": 3, "mcp__figma__get": 1}), "mins": 10,
                           "day": "2026-07-25", "cost": 1.5,
                           "tok": Counter({"input_tokens": 100, "output_tokens": 200}),
                           "per_model": {"claude-sonnet-5": Counter({"input_tokens": 100,
                                                                     "output_tokens": 200})},
                           "tiers": Counter({"standard": 1}), "versions": Counter({"2.1": 1}),
                           "side": Counter({"main": 1}), "branches": Counter()}],
                         [{"ts": "2026-07-25T00:00:00", "task": "t", "model": "haiku",
                           "executor": "model", "pass": False, "cost_usd": 0.1,
                           "fail_detail": "FAIL case 1"}],
                         m, dashboard.eval_alerts(m, dashboard.DEFAULT_ALERTS), out)
        html = out.read_text()
        for probe in ["Run explorer", "misfired", "FAIL case 1", "figma", "FIRING", "ok"]:
            assert probe in html, probe
        node = shutil.which("node")
        if node:
            js = re.search(r"<script>(.*)</script>", html, re.DOTALL).group(1)
            p = Path(d, "d.js")
            p.write_text(js)
            assert subprocess.run([node, "--check", str(p)],
                                  capture_output=True).returncode == 0


def test_cost_math_and_cache_multipliers():
    """Money is computed, so the arithmetic gets a check: sonnet-5 at $3/$15 per MTok,
    with cache read at 0.1x input and cache write at 1.25x input."""
    tok = Counter({"input_tokens": 1_000_000, "output_tokens": 1_000_000,
                   "cache_read_input_tokens": 1_000_000,
                   "cache_creation_input_tokens": 1_000_000})
    # 3 (fresh) + 15 (output) + 0.30 (read) + 3.75 (write) = 22.05
    assert abs(dashboard.model_cost("claude-sonnet-5", tok) - 22.05) < 1e-9
    # dated snapshots price via longest-prefix match
    assert dashboard.price_for("claude-haiku-4-5-20251001") == (1.0, 5.0)
    # an unknown model is not silently guessed
    assert dashboard.price_for("claude-unreleased-9") is None
    assert dashboard.model_cost("claude-unreleased-9", tok) == 0.0


def test_runrate_refuses_single_day_extrapolation():
    """One day of data must not become a 30x projection."""
    one = [{"project": "p", "day": "2026-07-25", "cost": 100.0, "tok": Counter(),
            "per_model": {}, "tiers": Counter(), "versions": Counter(),
            "side": Counter(), "models": Counter(), "tools": Counter()}]
    m1 = dashboard.money_metrics(one, 30)
    assert m1["projected_30d"] is None and m1["daily_burn"] is None
    two = one + [{**one[0], "day": "2026-07-26"}]
    m2 = dashboard.money_metrics(two, 30)
    assert m2["daily_burn"] == 100.0 and m2["projected_30d"] == 3000.0


def test_session_without_usage_is_tolerated():
    """A tool-only session (no billed messages) must not crash the money plane."""
    m = dashboard.money_metrics([{"project": "p", "models": Counter(), "tools": Counter({"Bash": 1})}], 30)
    assert m["total_cost"] == 0.0 and m["sessions"] == 1


def test_debt_score_formula():
    """v1 formula per the brief: 100 - 10*hi - 4*lo - min(20, staleness)."""
    import datetime as dtm
    import tempfile
    lines = """\
2026-07-01T00:00:00Z | DEBT | significance=high worthiness=high verdict=tap response=defer reason=old-item
2026-07-10T00:00:00Z | DEBT | significance=high worthiness=high verdict=tap response=engage reason=paid via weekend batch
2026-07-20T00:00:00Z | DEBT | significance=high worthiness=high verdict=tap response=defer reason=new-high
2026-07-21T00:00:00Z | DEBT | significance=low worthiness=high verdict=tap response=defer reason=new-low
2026-07-22T00:00:00Z | DEBT | significance=low worthiness=low verdict=not-significant reason=noise
"""
    with tempfile.TemporaryDirectory() as d:
        Path(d, "runs").mkdir()
        Path(d, "runs", "x.log").write_text(lines)
        debt = dashboard.collect_debt(d)
        assert len(debt) == 5
        dm = dashboard.debt_metrics(debt)
        # open = the two defers after the 07-10 paydown; the 07-01 defer is cleared
        assert dm["open_high"] == 1 and dm["open_low"] == 1
        assert dm["last_paydown"] == "2026-07-10"
        stale = min(20, (dashboard.now() - dtm.datetime(2026, 7, 10, tzinfo=dtm.timezone.utc)).days)
        assert dm["score"] == max(0, 100 - 10 - 4 - stale)


def test_debt_never_paid():
    dm = dashboard.debt_metrics([])
    assert dm["score"] == 80 and dm["last_paydown"] is None  # 100 - 20 staleness cap


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
