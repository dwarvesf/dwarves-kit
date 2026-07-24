"""Offline self-check for viewer.py: scenario validity, build output, JS syntax."""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import viewer  # noqa: E402


def test_scenarios_are_valid_streams():
    scen = viewer.demo_scenarios()
    assert len(scen) >= 4, "need task-type, workflow, and failure variants"
    for name, evs in scen.items():
        assert evs[0]["ev"] == "run_start", name
        assert evs[-1]["ev"] == "run_end", name
        planned = set(evs[0]["stages"])
        touched = {e["stage"] for e in evs if e.get("ev") in ("stage_start", "stage_end")}
        assert touched <= planned, f"{name}: events touch unplanned stages {touched - planned}"
    fails = [n for n, evs in scen.items() if evs[-1]["status"] == "fail"]
    assert fails, "at least one failure variant so the red path is designed, not hoped"


def test_build_embeds_scenarios():
    with tempfile.TemporaryDirectory() as d:
        out = Path(d, "v.html")
        viewer.build([], out)
        html = out.read_text()
        for name in viewer.demo_scenarios():
            assert name in html
        assert "__DATA__" not in html
        assert 'id="flow"' in html and 'id="tip"' in html and 'id="panel"' in html


def test_embedded_js_parses():
    node = shutil.which("node")
    if not node:
        print("  (node not found; JS syntax check skipped)")
        return
    with tempfile.TemporaryDirectory() as d:
        out = Path(d, "v.html")
        viewer.build([], out)
        m = re.search(r"<script>(.*)</script>", out.read_text(), re.DOTALL)
        assert m
        js = Path(d, "v.js")
        js.write_text(m.group(1))
        r = subprocess.run([node, "--check", str(js)], capture_output=True, text=True)
        assert r.returncode == 0, f"embedded JS does not parse:\n{r.stderr}"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
