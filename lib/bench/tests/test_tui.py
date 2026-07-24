"""Offline self-check for tui.py: state machine + renderers, no timing, no TTY."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import tui  # noqa: E402


def _finished_state():
    st = tui.RunState()
    for ev in tui.demo_events():
        st.apply(ev)
    return st


def test_state_machine_full_demo():
    st = _finished_state()
    assert st.done and st.result == "pass"
    assert [s["name"] for s in st.stages][:2] == ["classify", "grill"]
    ex = st.by_name["execute"]
    assert ex["attempt"] == 2, "retry event must bump the attempt counter"
    assert ex["status"] == "pass"
    assert st.totals["retries"] == 1


def test_render_frame_mid_run():
    st = tui.RunState()
    evs = tui.demo_events()
    for ev in evs[:12]:  # stop mid-execute so a stage is running
        st.apply(ev)
    lines = tui.render_frame(st, tick=3)
    joined = "\n".join(lines)
    assert "execute" in joined and "classify" in joined
    assert any(s["status"] == "running" for s in st.stages)


def test_final_report_prints(capsys=None):
    st = _finished_state()
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tui.final_report(st)
    out = buf.getvalue()
    assert "PASS" in out and "ship-gate" in out and "$0.5" in out


def test_events_roundtrip(tmp=None):
    import json
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = Path(d, "run.events.jsonl")
        p.write_text("".join(json.dumps(e) + "\n" for e in tui.demo_events()))
        st = tui.RunState()
        for ev in tui.read_jsonl(p):
            st.apply(ev)
        assert st.done and st.result == "pass"


def test_fail_run_reports_fingerprint():
    st = tui.RunState()
    st.apply({"ev": "run_start", "run_id": "x", "scenario": "s", "stages": ["build"]})
    st.apply({"ev": "stage_start", "stage": "build"})
    st.apply({"ev": "item", "stage": "build", "name": "check", "status": "fail",
              "fingerprint": "FAIL case 7: expected None"})
    st.apply({"ev": "stage_end", "stage": "build", "status": "fail", "detail": "1 case failed"})
    st.apply({"ev": "run_end", "status": "fail", "totals": {}})
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        tui.final_report(st)
    out = buf.getvalue()
    assert "FAIL" in out and "FAIL case 7" in out


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
