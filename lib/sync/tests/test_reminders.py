"""Reminders adapter tests against a fake osascript transport."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.reminders import RemindersSource, title_with_tags  # noqa: E402
from sync_core import Plan, Row  # noqa: E402


class FakeJxa:
    def __init__(self, read_out="[]", apply_out='{"created":{}}'):
        self.calls = []
        self.read_out = read_out
        self.apply_out = apply_out

    def __call__(self, script, *args):
        self.calls.append((script, args))
        return self.apply_out if len(args) > 1 else self.read_out


def test_read_normalizes_done_as_flag_only():
    fake = FakeJxa(read_out=json.dumps([
        {"rid": "r1", "title": "ID-10 · Fix", "completed": True, "body": None},
        {"rid": "r2", "title": "open", "completed": False, "body": "d"}]))
    items = RemindersSource(runner=fake).read()
    assert items[0] == {"rid": "r1", "title": "ID-10 · Fix", "done": True,
                        "body": "", "status": None}
    assert items[1]["body"] == "d"


def test_read_strips_title_tags_and_flags_drift():
    src = RemindersSource(runner=FakeJxa(read_out=json.dumps([
        {"rid": "r1", "title": "ID-10 · Fix #infra", "completed": False,
         "body": "notes #infra"},
        {"rid": "r2", "title": "ID-11 · Ship", "completed": False,
         "body": "n #u-hi"}])))  # tags in body, missing on title -> drift
    items = src.read()
    assert items[0]["title"] == "ID-10 · Fix"  # planner sees clean titles
    assert src._drift == ["r2"]
    # drift self-heals on apply even with an otherwise empty plan
    fake = src.runner
    src.apply(Plan(), {}, {})
    payload = json.loads(fake.calls[-1][1][1])
    assert payload["rename"] == [{"rid": "r2", "title": "ID-11 · Ship #u-hi"}]


def test_title_with_tags():
    assert title_with_tags("ID-10 · Fix", "x #b #a y") == "ID-10 · Fix #a #b"
    assert title_with_tags("ID-10 · Fix", "no tags") == "ID-10 · Fix"


def test_apply_maps_statuses_to_done_flag():
    fake = FakeJxa()
    src = RemindersSource(runner=fake)
    plan = Plan(src_set_status=[("r1", "shipped"), ("r2", "parked"),
                                ("r3", "queued")],
                src_create=[("ID-10", "ID-10 · Fix", "notes #infra", "queued")],
                board_add=[("r9", "loose", "", "queued")])
    rows_after = {"ID-99": Row("ID-99", "loose", "queued", 0, "prov #e2e")}
    src.apply(plan, {"r9": "ID-99"}, rows_after)
    _script, args = fake.calls[0]
    payload = json.loads(args[1])
    assert payload["setdone"] == [{"rid": "r1", "done": True},
                                  {"rid": "r2", "done": True},
                                  {"rid": "r3", "done": False}]
    # tags from the notes ride the title on create and adopted retitle
    assert payload["create"] == [{"key": "ID-10", "title": "ID-10 · Fix #infra",
                                  "body": "notes #infra"}]
    assert {"rid": "r9", "title": "ID-99 · loose #e2e"} in payload["rename"]
    assert {"rid": "r9", "body": "prov #e2e"} in payload["setbody"]


def test_body_change_refreshes_title_tags():
    src = RemindersSource(runner=FakeJxa(read_out=json.dumps([
        {"rid": "r1", "title": "ID-10 · Fix #old", "completed": False,
         "body": "x #old"}])))
    src.read()
    fake = src.runner
    src.apply(Plan(src_set_body=[("r1", "new notes #fresh")]), {}, {})
    payload = json.loads(fake.calls[-1][1][1])
    assert payload["rename"] == [{"rid": "r1", "title": "ID-10 · Fix #fresh"}]


def test_apply_noop_skips_osascript():
    fake = FakeJxa()
    assert RemindersSource(runner=fake).apply(Plan(), {}, {}) == {}
    assert fake.calls == []


# -- fail-fast transport: a Reminders.app that never answers (2026-10-02: a
# wedged LaunchServices meant no app could launch) must cost one short probe
# per sweep, not 600s per board.

import subprocess  # noqa: E402

import pytest  # noqa: E402

from sources import reminders  # noqa: E402


class FakeRun:
    """subprocess.run stand-in: answers each call from a queue of outcomes."""

    def __init__(self, *outcomes):
        self.outcomes = list(outcomes)
        self.calls = []

    def __call__(self, cmd, **kw):
        self.calls.append((cmd, kw))
        out = self.outcomes.pop(0)
        if out == "hang":
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout"))
        return subprocess.CompletedProcess(cmd, 0, stdout=out, stderr="")


@pytest.fixture
def transport(monkeypatch, tmp_path):
    marker = tmp_path / "reminders-unresponsive"
    monkeypatch.setattr(reminders, "WEDGE_MARKER", marker)
    monkeypatch.setattr(reminders, "_probed", False)

    def install(*outcomes):
        fake = FakeRun(*outcomes)
        monkeypatch.setattr(reminders.subprocess, "run", fake)
        return fake
    return marker, install


def test_unanswered_probe_fails_fast_and_marks(transport):
    marker, install = transport
    fake = install("hang")
    with pytest.raises(SystemExit, match="did not answer"):
        reminders._osascript(reminders.JXA_READ, "Backlog")
    assert len(fake.calls) == 1  # never reached the 600s bulk read
    assert fake.calls[0][1]["timeout"] <= 60
    assert marker.exists()


def test_fresh_marker_skips_without_calling_osascript(transport):
    marker, install = transport
    marker.touch()
    fake = install()
    with pytest.raises(SystemExit, match="skipped"):
        reminders._osascript(reminders.JXA_READ, "Backlog")
    assert fake.calls == []


def test_healthy_probe_clears_stale_marker_and_probes_once(transport):
    marker, install = transport
    marker.touch()
    old = marker.stat().st_mtime - reminders.WEDGE_TTL - 1
    import os
    os.utime(marker, (old, old))
    fake = install("3", "[]", '{"created":{}}')
    assert reminders._osascript(reminders.JXA_READ, "Backlog") == "[]"
    assert reminders._osascript(reminders.JXA_APPLY, "Backlog", "{}")
    assert len(fake.calls) == 3  # one probe for the whole process
    assert not marker.exists()


def test_bulk_call_timeout_marks_and_exits_cleanly(transport):
    marker, install = transport
    install("3", "hang")
    with pytest.raises(SystemExit, match="did not answer"):
        reminders._osascript(reminders.JXA_READ, "Backlog")
    assert marker.exists()
