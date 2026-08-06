"""Offline self-check for report.py: ledger summary, matrix, timeline geometry."""
import re
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import report  # noqa: E402

L1 = """\
2026-07-04T08:00:00Z | START | lane=full classified=full type=spec-feature repo=demo
2026-07-04T08:00:10Z | GATE | think | ran | context read
2026-07-04T08:20:00Z | GATE | build | ran | code written
2026-07-04T08:30:00Z | GATE | ship | ran | PR opened
"""
L2 = """\
2026-07-04T08:15:00Z | GATE | build | skipped | docs-only
2026-07-04T09:00:00Z | GATE | ship | override | operator call
"""


def _write(d, name, text):
    p = Path(d, name)
    p.write_text(text)
    return p


def test_run_summary():
    with tempfile.TemporaryDirectory() as d:
        s = report.run_summary(_write(d, "a.log", L1))
        assert s["rid"] == "a" and s["meta"]["lane"] == "full"
        assert s["gates"]["build"] == ("pass", "code written")
        assert (s["t1"] - s["t0"]).total_seconds() == 30 * 60


def test_render_report():
    with tempfile.TemporaryDirectory() as d:
        runs = [report.run_summary(_write(d, "a.log", L1)),
                report.run_summary(_write(d, "b.log", L2))]
        out = Path(d, "r.html")
        overlay = {"title": "t", "runs": {"a": {"model": "sonnet", "lane": "L", "label": "A1"}},
                   "incidents": [{"label": "X", "detail": "y"}],
                   "waves": {"title": "w", "rows": [{"name": "01", "state": "dispatched"}]}}
        report.render(runs, overlay, out)
        html = out.read_text()
        assert "A1" in html and "m-sonnet" in html and "m-unknown" in html
        assert "⚑" in html and "○" in html and "●" in html
        assert "Incidents" in html and "Wave board" in html
        # timeline bars stay inside the track
        for m in re.finditer(r'left:([\d.]+)%;width:([\d.]+)%', html):
            left, width = float(m.group(1)), float(m.group(2))
            assert 0 <= left <= 100 and 0 < width <= 100.5 and left + width <= 101


def test_phase_columns_follow_canonical_order():
    with tempfile.TemporaryDirectory() as d:
        runs = [report.run_summary(_write(d, "a.log", L1)),
                report.run_summary(_write(d, "b.log", L2))]
        out = Path(d, "r.html")
        report.render(runs, {}, out)
        html = out.read_text()
        assert html.index(">th<") < html.index(">bu<") < html.index(">sh<")


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
