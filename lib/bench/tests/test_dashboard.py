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
        m = dashboard.fleet_metrics(runs, 30)
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
        m = dashboard.fleet_metrics(runs, 30)
        out = Path(d, "dash.html")
        dashboard.render(runs, dashboard.collect_events(d),
                         [{"session": "abc", "project": "demo",
                           "models": Counter({"claude-sonnet-5": 1}),
                           "tools": Counter({"Bash": 3, "mcp__figma__get": 1}), "mins": 10}],
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


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
