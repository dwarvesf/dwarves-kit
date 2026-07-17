"""Multica adapter tests against a fake HTTP transport (no network)."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.multica import (MulticaSource, split_marker,  # noqa: E402
                             with_marker)
from sync_core import Plan, Row  # noqa: E402

WS = "ws-uuid"
PJ = "pj-uuid"


class FakeHttp:
    def __init__(self, pages=None):
        self.calls = []
        self.pages = list(pages or [])
        self.create_seq = 0

    def __call__(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method == "GET":
            issues = self.pages.pop(0) if self.pages else []
            return {"issues": issues, "total": len(issues)}
        if method == "POST":
            self.create_seq += 1
            return {"id": f"mi_{self.create_seq}"}
        return {}


def make_src(pages=None):
    fake = FakeHttp(pages)
    return MulticaSource("https://x.example", WS, PJ, runner=fake), fake


def test_marker_roundtrip():
    assert split_marker(with_marker("body text", "speccing")) == \
        ("body text", "speccing")
    assert split_marker("no marker here") == ("no marker here", None)
    assert split_marker(with_marker("", "queued")) == ("", "queued")
    # unknown keyword in the marker slot is not a marker
    assert split_marker("x\n\n<!-- board:bogus -->") == \
        ("x\n\n<!-- board:bogus -->", None)


def test_read_trusts_marker_until_multica_status_moves():
    issues = [
        # untouched: marker speccing, status still its forward image (todo)
        {"id": "a", "title": "ID-1 · Spec it", "status": "todo",
         "description": with_marker("notes", "speccing")},
        # moved on the Multica board: marker says speccing, status now
        # in_progress -> reverse map speaks (executing)
        {"id": "b", "title": "ID-2 · Build it", "status": "in_progress",
         "description": with_marker("", "speccing")},
        # foreign issue, no marker: plain reverse map
        {"id": "c", "title": "team idea", "status": "backlog",
         "description": "raw"},
        {"id": "d", "title": "ID-3 · Old", "status": "done",
         "description": with_marker("", "shipped")},
    ]
    src, fake = make_src([issues])
    items = src.read()
    assert [(i["rid"], i["status"], i["done"]) for i in items] == [
        ("a", "speccing", False), ("b", "executing", False),
        ("c", "queued", False), ("d", "shipped", True)]
    # body comes back without the marker
    assert items[0]["body"] == "notes"
    assert "workspace_id=ws-uuid" in fake.calls[0][1]
    assert "project_id=pj-uuid" in fake.calls[0][1]


def test_read_paginates():
    page1 = [{"id": f"i{n}", "title": f"t{n}", "status": "backlog",
              "description": ""} for n in range(100)]
    page2 = [{"id": "last", "title": "t", "status": "backlog",
              "description": ""}]
    src, fake = make_src([page1, page2])
    items = src.read()
    assert len(items) == 101
    assert "offset=0" in fake.calls[0][1] and "offset=100" in fake.calls[1][1]


def test_apply_creates_with_marker_and_mapped_status():
    src, fake = make_src([[]])
    src.read()
    plan = Plan(src_create=[("ID-10", "ID-10 · New thing", "the notes",
                             "queued")])
    created = src.apply(plan, {}, {})
    assert created == {"ID-10": "mi_1"}
    method, path, body = fake.calls[-1]
    assert (method, body["status"]) == ("POST", "backlog")
    assert body["project_id"] == PJ
    assert split_marker(body["description"]) == ("the notes", "queued")


def test_apply_status_change_rewrites_marker_without_clobbering_body():
    issues = [{"id": "a", "title": "ID-1 · X", "status": "backlog",
               "description": with_marker("keep me", "queued")}]
    src, fake = make_src([issues])
    src.read()
    src.apply(Plan(src_set_status=[("a", "executing")]), {}, {})
    method, path, body = fake.calls[-1]
    assert (method, body["status"]) == ("PUT", "in_progress")
    assert split_marker(body["description"]) == ("keep me", "executing")


def test_apply_body_change_keeps_current_marker():
    issues = [{"id": "a", "title": "ID-1 · X", "status": "todo",
               "description": with_marker("old", "claimed")}]
    src, fake = make_src([issues])
    src.read()
    src.apply(Plan(src_set_body=[("a", "new body")]), {}, {})
    _, _, body = fake.calls[-1]
    assert split_marker(body["description"]) == ("new body", "claimed")
    assert "status" not in body


def test_apply_adopts_board_add_with_assigned_id():
    issues = [{"id": "m9", "title": "team idea", "status": "backlog",
               "description": "raw"}]
    src, fake = make_src([issues])
    src.read()
    plan = Plan(board_add=[("m9", "team idea", "raw", "queued")])
    rows_after = {"ID-42": Row("ID-42", "team idea", "queued", 0, "raw")}
    src.apply(plan, {"m9": "ID-42"}, rows_after)
    _, path, body = fake.calls[-1]
    assert path.startswith("/api/issues/m9")
    assert body["title"] == "ID-42 · team idea"
    assert split_marker(body["description"]) == ("raw", "queued")


def test_missing_config_or_token_fails_closed():
    import pytest
    with pytest.raises(SystemExit):
        MulticaSource("https://x.example", WS, PJ, token=None)  # no env token
