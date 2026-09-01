"""Offline self-check for tui.py: state machine + renderers, no timing, no TTY."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import events as tui  # noqa: E402  (protocol lib; render tests live with the forge TUI)


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



LEDGER_FIXTURE = """\
2026-07-04T20:25:04Z | START | lane=full classified=tiny type=spec-feature repo=demo
2026-07-04T20:42:17Z | GATE | think | ran | read the context docs
2026-07-04T20:42:17Z | GATE | ui-design | skipped | no UI, CLI only
2026-07-04T20:42:17Z | GATE | build | ran | code + tests written
2026-07-04T20:42:28Z | GATE | build | ran | re-recorded batch
2026-07-04T20:43:23Z | GATE | reflect | override | retro owned by the conductor
2026-07-04T20:44:10Z | GATE | ship | ran | PR opened
2026-07-04T20:44:14Z | OUTCOME | ship | start | at=1
2026-07-04T20:44:14Z | OUTCOME | ship | end | at=1 caught=false dur_s=0
"""


def test_ledger_adapter():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        p = Path(d, "demo-run.log")
        p.write_text(LEDGER_FIXTURE)
        evs = tui.ledger_to_events(p, expected=[])  # overlay off: raw adapter behavior
        st = tui.RunState()
        for ev in evs:
            st.apply(ev)
        assert st.done and st.result == "pass"
        # routing decision is the root node; lane != classified flags a misfire
        route = st.stages[0]
        assert route["name"] == "route" and route["status"] == "override"
        assert "MISFIRE" in route["detail"]
        # gate order preserved, batches collapsed, decisions kept with reasons
        assert [s["name"] for s in st.stages] == ["route", "think", "ui-design", "build", "reflect", "ship"]
        assert st.by_name["ui-design"]["status"] == "skip"
        assert "no UI" in st.by_name["ui-design"]["detail"]
        assert st.by_name["reflect"]["status"] == "override"
        assert st.by_name["ship"]["items"][0]["status"] == "pass"
        assert "1 skipped" in st.totals["gates"] and "1 overridden" in st.totals["gates"]


def test_ledger_conformance_overlay():
    """Expected-vs-actual: gates the lane owed but the run never recorded become
    red ghost nodes, and required-gate conformance is scored."""
    import tempfile
    expected = [("think", "required"), ("spec", "required"), ("build", "required"),
                ("review", "required"), ("ship", "required"), ("ui-design", "lite")]
    with tempfile.TemporaryDirectory() as d:
        p = Path(d, "demo-run.log")
        p.write_text(LEDGER_FIXTURE)  # records think/ui-design/build/reflect/ship, no spec, no review
        st = tui.RunState()
        for ev in tui.ledger_to_events(p, expected=expected):
            st.apply(ev)
        assert st.by_name["spec"]["status"] == "missed"
        assert st.by_name["review"]["status"] == "missed"
        assert "expected by the full lane" in st.by_name["spec"]["detail"]
        # spine follows plan order: spec slots before build, review before ship
        names = [s["name"] for s in st.stages]
        assert names.index("spec") < names.index("build")
        assert names.index("review") < names.index("ship")
        assert st.totals["conformance"] == "3/5 required gates present"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok {fn.__name__}")
    print(f"PASSED {len(fns)}/{len(fns)}")
