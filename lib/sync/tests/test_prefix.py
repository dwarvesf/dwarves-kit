"""Per-board prefix support in the two-way mesh.

The cockpit gives every repo a unique row prefix (WS-, BK-, DS-, ...), but the
mesh was hardwired to ID-: on any non-ID board `board sync` read zero rows and
planned duplicate intake for every already-rowed spoke item (found live on
whetstone's first sync). These pin the fix: the prefix is detected from the
board itself and threaded through parse, mint, and apply.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sync_core import (Plan, apply_board, detect_prefix,  # noqa: E402
                       next_id, parse_board)

WS_BOARD = """# BACKLOG

| ID | Item | Notes & source | Status |
|---|---|---|---|
| WS-3 | review panel model | adopted gh#7 | queued |
| WS-1 | newline trap | adopted gh#9 | queued |
"""


def test_detect_prefix_ws_and_empty_default():
    assert detect_prefix(WS_BOARD) == "WS"
    assert detect_prefix("# empty\n") == "ID"


def test_detect_prefix_majority_wins():
    mixed = WS_BOARD + "| ID-9 | stray | n | queued |\n"
    assert detect_prefix(mixed) == "WS"


def test_strict_parse_sees_prefixed_rows():
    # the live bug: strict default (ID) reads 0 rows off a WS board
    assert parse_board(WS_BOARD) == {}
    rows = parse_board(WS_BOARD, prefix="WS")
    assert set(rows) == {"WS-3", "WS-1"}


def test_next_id_is_prefix_scoped():
    assert next_id(WS_BOARD, "WS") == 4
    assert next_id(WS_BOARD, "ID") == 1  # foreign prefix never inflates


def test_apply_board_mints_with_board_prefix():
    plan = Plan(board_add=[("77", "from spoke", "body", "queued")])
    new_text, assigned = apply_board(WS_BOARD, plan, prefix="WS")
    assert assigned == {"77": "WS-4"}
    assert "| WS-4 | from spoke |" in new_text


# --- binary-spoke doneness merge (the WS-5 oscillation) ----------------------

from sync_core import plan_sync  # noqa: E402

DROPPED_BOARD = """| ID | Item | Notes & source | Status |
|---|---|---|---|
| WS-5 | live test | e2e | dropped |
"""


def _state(status):
    return {"map": {"WS-5": {"rid": "12", "title": "live test",
                             "notes": "e2e", "status": status}}}


def test_binary_spoke_dropped_row_closed_item_is_stable():
    # closed issue + dropped row + snapshot dropped: NOTHING may move. The
    # keyword compare re-derived shipped != dropped and flipped the board on
    # every sync (live WS-5 bug); doneness compare holds it still.
    rows = parse_board(DROPPED_BOARD, prefix="WS")
    item = {"rid": "12", "title": "WS-5 · live test", "done": True,
            "body": "e2e", "status": None}
    p = plan_sync(rows, [item], _state("dropped"), sync_fields=False)
    assert not p.board_set_status and not p.src_set_status


def test_binary_spoke_reopen_flows_to_board_as_queued():
    rows = parse_board(DROPPED_BOARD, prefix="WS")
    item = {"rid": "12", "title": "WS-5 · live test", "done": False,
            "body": "e2e", "status": None}
    p = plan_sync(rows, [item], _state("dropped"), sync_fields=False)
    assert p.board_set_status == [("WS-5", "queued")]
