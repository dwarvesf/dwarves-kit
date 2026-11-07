"""atomic_write keeps the board's file mode.

mkstemp opens 0600; an os.replace of that file locked other accounts out of
BACKLOG.md (a cron running as another user could not read the board).
"""
import os
import stat
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import backlog_sync  # noqa: E402


def mode_of(path):
    return stat.S_IMODE(os.stat(path).st_mode)


def test_existing_board_keeps_its_mode(tmp_path):
    board = tmp_path / "BACKLOG.md"
    board.write_text("old")
    os.chmod(board, 0o644)
    backlog_sync.atomic_write(board, "new")
    assert board.read_text() == "new"
    assert mode_of(board) == 0o644


def test_a_private_board_stays_private(tmp_path):
    board = tmp_path / "BACKLOG.md"
    board.write_text("old")
    os.chmod(board, 0o600)
    backlog_sync.atomic_write(board, "new")
    assert mode_of(board) == 0o600


def test_a_new_board_is_world_readable(tmp_path):
    board = tmp_path / "BACKLOG.md"
    backlog_sync.atomic_write(board, "new")
    assert mode_of(board) == 0o644


def test_a_new_state_file_stays_private(tmp_path):
    state = tmp_path / "state.json"
    backlog_sync.atomic_write(state, "{}", new_mode=0o600)
    assert mode_of(state) == 0o600


def test_no_temp_file_is_left_behind(tmp_path):
    board = tmp_path / "BACKLOG.md"
    backlog_sync.atomic_write(board, "new")
    assert [p.name for p in tmp_path.iterdir()] == ["BACKLOG.md"]
