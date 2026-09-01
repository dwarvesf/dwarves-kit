"""Notion adapter tests against a fake ntn transport (no network)."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.notion import NotionSource, _rich  # noqa: E402
from sync_core import Plan, Row  # noqa: E402


class FakeNtn:
    def __init__(self, responses=None):
        self.calls = []          # [(args_tuple, data)]
        self.responses = responses or {}
        self.page_seq = 0

    def __call__(self, args, data=None):
        self.calls.append((tuple(args), data))
        key = " ".join(args[:3])
        for prefix, resp in self.responses.items():
            if key.startswith(prefix):
                return resp(data) if callable(resp) else resp
        if args[0] == "api" and args[1] == "v1/pages" and "-X" in args:
            self.page_seq += 1
            return {"id": f"pg{self.page_seq}"}
        return {}

    def bodies(self, path_prefix):
        return [d for a, d in self.calls if a[0] == "api"
                and a[1].startswith(path_prefix) and d is not None]


SELECT_SCHEMA = {"properties": {
    "Task": {"type": "title", "title": {}},
    "Status": {"type": "select", "select": {"options": [{"name": "queued"}]}},
}}

STATUS_SCHEMA = {"properties": {
    "Name": {"type": "title", "title": {}},
    "Status": {"type": "status", "status": {
        "options": [{"id": "o1", "name": "Not started"},
                    {"id": "o2", "name": "In progress"},
                    {"id": "o3", "name": "Done"},
                    {"id": "o4", "name": "queued"}],
        "groups": [{"name": "To-do", "option_ids": ["o1", "o4"]},
                   {"name": "In progress", "option_ids": ["o2"]},
                   {"name": "Complete", "option_ids": ["o3"]}]}},
    "Notes": {"type": "rich_text", "rich_text": {}},
    "Tags": {"type": "multi_select", "multi_select": {}},
}}


def test_bootstrap_creates_database_with_full_schema():
    fake = FakeNtn({"api v1/databases -X": {
        "id": "db1", "data_sources": [{"id": "ds1"}]}})
    src = NotionSource(parent="page-1", runner=fake)
    b = src.ensure_binding()
    assert b["ds_id"] == "ds1" and b["created"]
    (_args, body) = fake.calls[0]
    assert body["parent"]["page_id"] == "page-1"
    # 2025-09+ API: schema rides on initial_data_source, never top-level
    assert "properties" not in body
    props = body["initial_data_source"]["properties"]
    assert set(props) == {"Name", "Status", "Tags", "Notes"}
    names = {o["name"] for o in props["Status"]["select"]["options"]}
    assert "queued" in names and "shipped" in names and "parked" in names


def test_bind_existing_discovers_and_patches_missing_props():
    fake = FakeNtn({
        "datasources resolve db2": {"data_sources": [{"id": "ds2"}]},
        "api v1/data_sources/ds2": SELECT_SCHEMA,
    })
    src = NotionSource(db="db2", runner=fake)
    b = src.ensure_binding()
    assert b["props"]["title"] == "Task"          # discovered, not assumed
    assert b["props"]["status_type"] == "select"
    patches = fake.bodies("v1/data_sources/ds2")
    assert patches and set(patches[0]["properties"]) == {"Notes", "Tags"}


def test_bind_status_type_maps_by_group():
    fake = FakeNtn({
        "datasources resolve db3": {"data_sources": [{"id": "ds3"}]},
        "api v1/data_sources/ds3": STATUS_SCHEMA,
    })
    src = NotionSource(db="db3", runner=fake)
    b = src.ensure_binding()
    assert b["props"]["status_type"] == "status"
    # exact option exists -> exact; unknown active -> To-do default;
    # unknown terminal -> Complete default
    assert src._status_value("queued", b) == {"status": {"name": "queued"}}
    assert src._status_value("claimed", b) == {"status": {"name": "Not started"}}
    assert src._status_value("shipped", b) == {"status": {"name": "Done"}}


def query_page(rid, title, status_name, notes="", status_key="select"):
    return {"id": rid, "properties": {
        "Name": {"title": [{"plain_text": title}]},
        "Status": {status_key: {"name": status_name} if status_name else None},
        "Notes": {"rich_text": [{"plain_text": notes}] if notes else []},
    }}


def binding_select():
    return {"ds_id": "ds1", "db_id": "db1", "created": True,
            "props": {"title": "Name", "status": "Status",
                      "status_type": "select", "notes": "Notes",
                      "tags": "Tags"}}


def test_read_paginates_and_normalizes():
    pages1 = {"results": [query_page("p1", "ID-10 · Fix it", "queued"),
                          query_page("p2", "ID-12 · Old", "shipped")],
              "has_more": True, "next_cursor": "c2"}
    pages2 = {"results": [query_page("p3", "loose card", "weird-option",
                                     notes="desc here")],
              "has_more": False}
    seq = iter([pages1, pages2])
    fake = FakeNtn({"api v1/data_sources/ds1/query": lambda d: next(seq)})
    src = NotionSource(binding=binding_select(), runner=fake)
    items = src.read()
    assert [(i["rid"], i["status"], i["done"]) for i in items] == [
        ("p1", "queued", False), ("p2", "shipped", True), ("p3", None, False)]
    assert items[2]["body"] == "desc here"
    # second query call carried the cursor
    assert fake.bodies("v1/data_sources/ds1/query")[1]["start_cursor"] == "c2"


def test_apply_create_chunks_body_and_derives_tags():
    fake = FakeNtn()
    src = NotionSource(binding=binding_select(), runner=fake)
    long_body = "x" * 4500 + " #infra #u-hi"
    plan = Plan(src_create=[("ID-10", "ID-10 · Fix it", long_body, "queued")])
    created = src.apply(plan, {}, {})
    assert created == {"ID-10": "pg1"}
    body = fake.bodies("v1/pages")[0]
    props = body["properties"]
    assert body["parent"] == {"type": "data_source_id", "data_source_id": "ds1"}
    chunks = props["Notes"]["rich_text"]
    assert len(chunks) == 3 and all(
        len(c["text"]["content"]) <= 2000 for c in chunks)
    assert {t["name"] for t in props["Tags"]["multi_select"]} == {"infra", "u-hi"}
    # tags live in the Tags field ONLY; the notes text is stripped of them
    assert "#infra" not in "".join(c["text"]["content"] for c in chunks)
    assert props["Status"] == {"select": {"name": "queued"}}


def test_apply_status_title_and_adopted_retitle():
    fake = FakeNtn()
    src = NotionSource(binding=binding_select(), runner=fake)
    plan = Plan(src_set_status=[("p1", "shipped")],
                src_set_title=[("p2", "ID-11 · New title")],
                board_add=[("p9", "loose card", "d", "queued")])
    rows_after = {"ID-99": Row("ID-99", "loose card", "queued", 0,
                               "d ; added from spoke 2026-07-16")}
    src.apply(plan, {"p9": "ID-99"}, rows_after)
    patched = {a[1]: d for a, d in fake.calls if "PATCH" in a}
    assert patched["v1/pages/p1"]["properties"]["Status"] == {
        "select": {"name": "shipped"}}
    assert patched["v1/pages/p2"]["properties"]["Name"]["title"][0][
        "text"]["content"] == "ID-11 · New title"
    adopted = patched["v1/pages/p9"]["properties"]
    assert adopted["Name"]["title"][0]["text"]["content"] == "ID-99 · loose card"
    assert adopted["Status"] == {"select": {"name": "queued"}}


def test_read_folds_field_tags_back_for_inbox_capture():
    page = query_page("p9", "loose card", "queued", notes="desc")
    page["properties"]["Tags"] = {"multi_select": [{"name": "infra"},
                                                   {"name": "e2e"}]}
    fake = FakeNtn({"api v1/data_sources/ds1/query":
                    {"results": [page], "has_more": False}})
    src = NotionSource(binding=binding_select(), runner=fake)
    assert src.read()[0]["body"] == "desc #infra #e2e"


def test_rich_never_empty_and_json_safe():
    assert _rich("")[0]["text"]["content"] == ""
    json.dumps(_rich("a" * 5000))


def test_rich_chunks_by_utf16_units_not_codepoints():
    # 1999 ASCII + one astral char = 2000 codepoints but 2001 UTF-16 units;
    # a len()-based chunk ships it whole and Notion 400s the request.
    text = "a" * 1999 + "\U0001F4CA"
    chunks = _rich(text)
    utf16 = [sum(2 if ord(c) > 0xFFFF else 1 for c in ch["text"]["content"])
             for ch in chunks]
    assert all(u <= 2000 for u in utf16)
    assert "".join(ch["text"]["content"] for ch in chunks) == text
    # plain ASCII still packs a full 2000 per chunk
    assert _rich("a" * 2000)[0]["text"]["content"] == "a" * 2000


def test_unbound_without_flags_exits_with_guidance():
    src = NotionSource(runner=FakeNtn())
    with pytest.raises(SystemExit, match="notion-db"):
        src.ensure_binding()
