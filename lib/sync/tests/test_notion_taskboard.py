"""One-way Task Board sink tests against a fake ntn transport (no network,
no live writes). SPEC-003 test plan."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.notion_taskboard import (NotionTaskBoardSource, _rich,  # noqa: E402
                                      parse_map)
from sources.notion_taskboard_pull import MARKER_PREFIX  # noqa: E402
from sync_core import (PULL_MARKER_RE, Plan, Row,  # noqa: E402
                       plan_create_only)


class FakeNtn:
    def __init__(self, responses=None):
        self.calls = []
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

    def page_bodies(self):
        return [d for a, d in self.calls
                if a[0] == "api" and a[1] == "v1/pages" and d is not None]


DF_STATUS = {"queued": "Backlog", "executing": "In progress",
             "parked": "Waiting", "shipped": "Done"}
DF_PRIORITY = {"u-hi": "P0", "u-mid": "P1", "u-lo": "P2"}
DF_WEIGHT = {"f-hi": "2", "f-mid": "5", "f-lo": "13"}


def binding():
    return {"db_id": "db1", "ds_id": "ds1"}


def make_src(**kw):
    defaults = dict(db="db1", status_map=dict(DF_STATUS), binding=binding(),
                    runner=FakeNtn())
    defaults.update(kw)
    src = NotionTaskBoardSource(**defaults)
    return src, src.runner


# --- parse_map -----------------------------------------------------------


def test_parse_map_basic_and_blank():
    assert parse_map("queued=Backlog, executing=In progress") == {
        "queued": "Backlog", "executing": "In progress"}
    assert parse_map("") == {} and parse_map(None) == {}


def test_parse_map_rejects_valueless_entry():
    with pytest.raises(SystemExit, match="bad map entry"):
        parse_map("queued")


# --- create-only planner (case 2, 3, 5) ----------------------------------


def rows(*specs):
    return {bid: Row(bid, item, kw, i, notes)
            for i, (bid, item, kw, notes) in enumerate(specs)}


def test_dropped_row_is_never_pushed():
    r = rows(("DF-1", "keep", "queued", ""), ("DF-2", "gone", "dropped", ""))
    plan = plan_create_only(r, {})
    assert [c[0] for c in plan.src_create] == ["DF-1"]


def test_already_pushed_row_is_frozen():
    r = rows(("DF-1", "a", "queued", ""), ("DF-2", "b", "executing", ""))
    state = {"map": {"DF-1": {"rid": "pg1"}}}
    plan = plan_create_only(r, state)
    assert [c[0] for c in plan.src_create] == ["DF-2"]


def test_skip_tag_down_filter():
    r = rows(("DF-1", "pub", "queued", "#ops"),
             ("DF-2", "sec", "queued", "#family"))
    plan = plan_create_only(r, {}, filt={"skip_tags": {"family"}})
    assert [c[0] for c in plan.src_create] == ["DF-1"]


def test_custom_skip_kw_extends_dropped():
    r = rows(("DF-1", "a", "shipped", ""), ("DF-2", "b", "queued", ""))
    plan = plan_create_only(r, {}, skip_kw={"dropped", "shipped"})
    assert [c[0] for c in plan.src_create] == ["DF-2"]


# --- marker-aware adoption: never re-create a row the pull leg made ------

PULL_PID = "0123456789abcdef0123456789abcdef"


def test_marker_row_adopts_instead_of_creating():
    r = rows(("DF-1", "intake row", "queued",
              f"notion-intake ; notion-page:{PULL_PID} ; some body"))
    plan = plan_create_only(r, {})
    assert plan.src_create == []
    assert plan.src_adopt == [("DF-1", PULL_PID)]


def test_normal_row_without_marker_still_creates():
    r = rows(("DF-1", "plain row", "queued", "no marker here"))
    plan = plan_create_only(r, {})
    assert [c[0] for c in plan.src_create] == ["DF-1"]
    assert plan.src_adopt == []


def test_dropped_or_filtered_marker_row_plans_nothing():
    r = rows(("DF-1", "dropped intake", "dropped", f"notion-page:{PULL_PID}"),
             ("DF-2", "filtered intake", "queued",
              f"#family notion-page:{PULL_PID}"))
    plan = plan_create_only(r, {}, filt={"skip_tags": {"family"}})
    assert plan.src_create == [] and plan.src_adopt == []


def test_adoption_persists_to_state_and_second_run_is_empty(tmp_path):
    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(
        "| ID | Item | Notes & source | Status |\n|---|---|---|---|\n"
        f"| DF-1 | intake row | notion-page:{PULL_PID} | queued |\n")
    state = tmp_path / "s.json"

    src, fake = make_src()
    backlog_sync.sync_create_only(src, board, state, dry_run=False)
    assert fake.page_bodies() == []
    saved = json.loads(state.read_text())
    assert saved["map"]["DF-1"] == {"rid": PULL_PID, "via": "pull-marker"}

    src2, fake2 = make_src()
    backlog_sync.sync_create_only(src2, board, state, dry_run=False)
    assert fake2.page_bodies() == []  # no ntn write call for the adopted row


def test_marker_pattern_matches_pull_adapter_prefix():
    # A rename on either side (this pattern or the pull adapter's own
    # constant) must turn this test red before it can turn any row red.
    text = MARKER_PREFIX + PULL_PID
    m = PULL_MARKER_RE.search(text)
    assert m and m.group(1) == PULL_PID


# --- apply: field mapping (case 1, 4) ------------------------------------


def test_create_maps_all_fields():
    src, fake = make_src(priority_map=dict(DF_PRIORITY),
                         weight_map=dict(DF_WEIGHT), owner="user-han")
    plan = Plan(src_create=[("DF-9", "DF-9 · Fix vault", "harden it #u-hi #f-mid",
                             "executing")])
    created = src.apply(plan, {}, {})
    assert created == {"DF-9": "pg1"}
    body = fake.page_bodies()[0]
    assert body["parent"] == {"type": "data_source_id", "data_source_id": "ds1"}
    props = body["properties"]
    assert props["Task"]["title"][0]["text"]["content"] == "DF-9 · Fix vault"
    assert props["Status"] == {"status": {"name": "In progress"}}
    assert props["Priority"] == {"select": {"name": "P0"}}
    assert props["Weight"] == {"number": 5}
    assert props["Owner"] == {"people": [{"id": "user-han"}]}
    # tags belong to Priority/Weight, not the Notes text
    assert "#u-hi" not in props["Notes"]["rich_text"][0]["text"]["content"]


def test_priority_and_weight_omitted_when_no_tag():
    src, fake = make_src(priority_map=dict(DF_PRIORITY),
                         weight_map=dict(DF_WEIGHT))
    plan = Plan(src_create=[("DF-1", "DF-1 · plain", "no tags here", "queued")])
    src.apply(plan, {}, {})
    props = fake.page_bodies()[0]["properties"]
    assert "Priority" not in props and "Weight" not in props
    assert props["Status"] == {"status": {"name": "Backlog"}}


def test_prop_and_type_overrides():
    src, fake = make_src(
        props={"status": "Stage", "weight": "Points"},
        types={"status": "select", "weight": "select"},
        weight_map=dict(DF_WEIGHT))
    plan = Plan(src_create=[("DF-1", "t", "x #f-hi", "queued")])
    src.apply(plan, {}, {})
    props = fake.page_bodies()[0]["properties"]
    assert props["Stage"] == {"select": {"name": "Backlog"}}
    assert props["Points"] == {"select": {"name": "2"}}


# --- status default / hard error (case 6, 7) -----------------------------


def test_unmapped_status_without_default_errors():
    src, _ = make_src()  # DF_STATUS has no "claimed"
    plan = Plan(src_create=[("DF-1", "t", "x", "claimed")])
    with pytest.raises(SystemExit, match="no Status mapping"):
        src.apply(plan, {}, {})


def test_status_default_catches_unmapped_state():
    src, fake = make_src(status_default="Backlog")
    plan = Plan(src_create=[("DF-1", "t", "x", "speccing")])
    src.apply(plan, {}, {})
    assert fake.page_bodies()[0]["properties"]["Status"] == {
        "status": {"name": "Backlog"}}


# --- write-only sink (read + binding) ------------------------------------


def test_read_returns_nothing():
    src, fake = make_src()
    assert src.read() == []
    assert fake.calls == []  # never touches the board


def test_binding_resolves_data_source_read_only():
    fake = FakeNtn({"datasources resolve db1": {"data_sources": [{"id": "ds9"}]}})
    src = NotionTaskBoardSource(db="db1", status_map=dict(DF_STATUS),
                                runner=fake)
    b = src.ensure_binding()
    assert b["ds_id"] == "ds9"
    # only a resolve read happened; no PATCH, no page write
    assert all("PATCH" not in a and a[:2] != ("api", "v1/pages")
               for a, _ in fake.calls)


def test_unbound_without_db_exits_with_guidance():
    src = NotionTaskBoardSource(status_map=dict(DF_STATUS), runner=FakeNtn())
    with pytest.raises(SystemExit, match="notion_taskboard_db"):
        src.ensure_binding()


def test_number_weight_rejects_non_numeric():
    src, _ = make_src(weight_map={"f-hi": "heavy"})
    plan = Plan(src_create=[("DF-1", "t", "x #f-hi", "queued")])
    with pytest.raises(SystemExit, match="not a number"):
        src.apply(plan, {}, {})


# --- engine path: board never written, state map is the identity (case 8) --

BOARD = (
    "| ID | Item | Notes & source | Status |\n"
    "|---|---|---|---|\n"
    "| DF-1 | Lock the vault | harden #u-hi | queued |\n"
    "| DF-2 | Drop this | old idea | dropped |\n"
)


def test_create_only_path_never_writes_board_and_is_idempotent(tmp_path):
    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(BOARD)
    state = tmp_path / "notion-taskboard.state.json"
    before = board.read_text()

    src, fake = make_src(priority_map=dict(DF_PRIORITY))
    backlog_sync.sync_create_only(src, board, state, dry_run=False)

    # board file byte-identical: strictly one-way
    assert board.read_text() == before
    # exactly one page created (DF-1); DF-2 dropped is skipped
    assert len(fake.page_bodies()) == 1
    saved = json.loads(state.read_text())
    assert list(saved["map"]) == ["DF-1"]

    # second run with the persisted state: nothing new (idempotent)
    src2, fake2 = make_src(priority_map=dict(DF_PRIORITY))
    backlog_sync.sync_create_only(src2, board, state, dry_run=False)
    assert fake2.page_bodies() == []
    assert board.read_text() == before


def test_create_only_dry_run_writes_nothing(tmp_path):
    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(BOARD)
    state = tmp_path / "s.json"
    src, fake = make_src()
    backlog_sync.sync_create_only(src, board, state, dry_run=True)
    assert fake.page_bodies() == [] and not state.exists()


# --- build_source wiring (case 9) ----------------------------------------


def args_ns(**over):
    from types import SimpleNamespace
    base = dict(notion_taskboard_db="db1",
                notion_taskboard_status_map="queued=Backlog,executing=In progress",
                notion_taskboard_status_default=None,
                notion_taskboard_priority_map="u-hi=P0,u-mid=P1",
                notion_taskboard_weight_map="f-hi=2,f-mid=5",
                notion_taskboard_owner="user-han",
                notion_taskboard_props=None, notion_taskboard_types=None)
    base.update(over)
    return SimpleNamespace(**base)


def test_build_source_wires_maps_from_flags():
    import backlog_sync

    src = backlog_sync.build_source("notion-taskboard", args_ns())
    assert isinstance(src, NotionTaskBoardSource)
    assert src.status_map == {"queued": "Backlog", "executing": "In progress"}
    assert src.priority_map == {"u-hi": "P0", "u-mid": "P1"}
    assert src.weight_map == {"f-hi": "2", "f-mid": "5"}
    assert src.owner == "user-han"


def test_build_source_requires_db():
    import backlog_sync

    with pytest.raises(SystemExit, match="notion_taskboard_db"):
        backlog_sync.build_source("notion-taskboard",
                                  args_ns(notion_taskboard_db=None))


def test_build_source_requires_status_map_or_default():
    import backlog_sync

    with pytest.raises(SystemExit, match="notion_taskboard_status_map"):
        backlog_sync.build_source(
            "notion-taskboard",
            args_ns(notion_taskboard_status_map=None,
                    notion_taskboard_status_default=None))


def test_build_source_status_default_alone_is_enough():
    import backlog_sync

    src = backlog_sync.build_source(
        "notion-taskboard",
        args_ns(notion_taskboard_status_map=None,
                notion_taskboard_status_default="Backlog"))
    assert src.status_default == "Backlog" and src.status_map == {}


def test_build_source_props_and_types_json():
    import backlog_sync

    src = backlog_sync.build_source(
        "notion-taskboard",
        args_ns(notion_taskboard_props='{"status": "Stage"}',
                notion_taskboard_types='{"status": "select"}'))
    assert src.props["status"] == "Stage" and src.types["status"] == "select"


def test_cli_end_to_end_pushes_through_main(tmp_path, monkeypatch):
    """Full CLI path: argparse -> dispatch -> create-only push, fake ntn."""
    import functools

    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(BOARD)
    fake = FakeNtn()
    monkeypatch.setattr(
        backlog_sync, "NotionTaskBoardSource",
        functools.partial(NotionTaskBoardSource, runner=fake,
                          binding=binding()))
    backlog_sync.main([
        "--apps", "notion-taskboard",
        "--backlog", str(board),
        "--state-root", str(tmp_path / "state"),
        "--notion-taskboard-db", "db1",
        "--notion-taskboard-status-map", "queued=Backlog,executing=In progress",
        "--notion-taskboard-priority-map", "u-hi=P0",
    ])
    # DF-1 (queued, #u-hi) pushed; DF-2 (dropped) skipped; board untouched
    bodies = fake.page_bodies()
    assert len(bodies) == 1
    props = bodies[0]["properties"]
    assert props["Status"] == {"status": {"name": "Backlog"}}
    assert props["Priority"] == {"select": {"name": "P0"}}
    assert board.read_text() == BOARD


# --- schema-aware validation (never auto-create a team option) ------------

SCHEMA = {"properties": {
    "Task": {"type": "title", "title": {}},
    "Status": {"type": "status", "status": {"options": [
        {"name": "Backlog"}, {"name": "In progress"}, {"name": "Waiting"},
        {"name": "Done"}]}},
    "Priority": {"type": "select", "select": {"options": [
        {"name": "P0"}, {"name": "P1"}, {"name": "P2"}]}},
    "Notes": {"type": "rich_text", "rich_text": {}},
}}


def schema_src(**kw):
    fake = FakeNtn({"api v1/data_sources/ds1": SCHEMA})
    defaults = dict(db="db1", status_map=dict(DF_STATUS), binding=binding(),
                    runner=fake)
    defaults.update(kw)
    return NotionTaskBoardSource(**defaults), fake


def test_preflight_rejects_unknown_select_option():
    # a typo'd Priority value would otherwise auto-create a team option
    src, _ = schema_src(priority_map={"u-hi": "P-zero"})
    plan = Plan(src_create=[("DF-1", "t", "x #u-hi", "queued")])
    with pytest.raises(SystemExit, match="not an option of the 'Priority'"):
        src.preflight(plan)


def test_preflight_passes_known_options_and_learns_types():
    src, _ = schema_src(priority_map={"u-hi": "P0"})
    plan = Plan(src_create=[("DF-1", "t", "x #u-hi", "queued")])
    src.preflight(plan)  # no raise
    # types discovered from the schema (not the fallback guesses)
    assert src._eff_type("status") == "status"
    assert src._eff_type("priority") == "select"


def test_preflight_surfaces_unmapped_status_on_dry_run(tmp_path):
    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(
        "| ID | Item | Notes & source | Status |\n|---|---|---|---|\n"
        "| DF-1 | mid-flight | x | speccing |\n")   # speccing not mapped
    src, _ = schema_src()  # no status_default
    with pytest.raises(SystemExit, match="no Status mapping"):
        backlog_sync.sync_create_only(src, board, tmp_path / "s.json",
                                      dry_run=True)


def test_stale_binding_for_a_different_db_is_rediscarded():
    fake = FakeNtn({"datasources resolve db-new": {"data_sources": [{"id": "ds-new"}]}})
    src = NotionTaskBoardSource(db="db-new", status_map=dict(DF_STATUS),
                                binding={"db_id": "db-old", "ds_id": "ds-old"},
                                runner=fake)
    b = src.ensure_binding()
    assert b["db_id"] == "db-new" and b["ds_id"] == "ds-new"


# --- partial-batch failure never re-pushes (checkpoint per create) --------


class FailOnNth(FakeNtn):
    def __init__(self, nth, responses=None):
        super().__init__(responses)
        self.nth = nth

    def __call__(self, args, data=None):
        if args[0] == "api" and args[1] == "v1/pages" and "-X" in args:
            if self.page_seq + 1 == self.nth:
                raise SystemExit("ntn api v1/pages failed: 429 rate limited")
        return super().__call__(args, data)


TWO_ROW_BOARD = (
    "| ID | Item | Notes & source | Status |\n|---|---|---|---|\n"
    "| DF-1 | first | x | queued |\n"
    "| DF-2 | second | y | queued |\n"
)


def test_partial_batch_failure_checkpoints_and_never_duplicates(tmp_path):
    import backlog_sync

    board = tmp_path / "BACKLOG.md"
    board.write_text(TWO_ROW_BOARD)
    state = tmp_path / "s.json"

    # run 1: second create fails after the first succeeded
    fake = FailOnNth(2, {"api v1/data_sources/ds1": {"properties": {}}})
    src = NotionTaskBoardSource(db="db1", status_map=dict(DF_STATUS),
                                binding=binding(), runner=fake)
    with pytest.raises(SystemExit, match="429"):
        backlog_sync.sync_create_only(src, board, state, dry_run=False)
    # DF-1's page was persisted even though the batch aborted
    saved = json.loads(state.read_text())
    assert list(saved["map"]) == ["DF-1"]

    # run 2 (recovery): only DF-2 is created; DF-1 is NOT re-pushed
    fake2 = FakeNtn({"api v1/data_sources/ds1": {"properties": {}}})
    src2 = NotionTaskBoardSource(db="db1", status_map=dict(DF_STATUS),
                                 binding=binding(), runner=fake2)
    backlog_sync.sync_create_only(src2, board, state, dry_run=False)
    assert len(fake2.page_bodies()) == 1
    assert sorted(json.loads(state.read_text())["map"]) == ["DF-1", "DF-2"]


def test_rich_chunks_by_utf16_units_not_codepoints():
    # The dfoundation board carried a Notes cell with one emoji inside its
    # first 2000 codepoints: 2001 UTF-16 units, Notion 400'd every hourly
    # sync (2026-08-18). Chunks must weigh <= 2000 UTF-16 units.
    text = "a" * 1999 + "\U0001F4CA" + "b" * 50
    chunks = _rich(text)
    utf16 = [sum(2 if ord(c) > 0xFFFF else 1 for c in ch["text"]["content"])
             for ch in chunks]
    assert all(u <= 2000 for u in utf16)
    assert "".join(ch["text"]["content"] for ch in chunks) == text


def test_warn_duplicate_ids_general_prefix():
    import backlog_sync

    text = ("| DF-1 | a | x | queued |\n"
            "| DF-1 | dup | y | queued |\n")
    # strict (ID-only) sees no DF dup; general prefix catches it
    backlog_sync.warn_duplicate_ids(text, strict_id=True)   # silent
    import io
    import contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        backlog_sync.warn_duplicate_ids(text, strict_id=False)
    assert "duplicate board rows for DF-1" in buf.getvalue()
