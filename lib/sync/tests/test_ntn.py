"""The shared `ntn` runner: which calls retry, and which must not."""
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sources import ntn, notion, notion_taskboard, notion_taskboard_pull  # noqa: E402

BARE = "error: Failed to execute public API request"
BAD_GATEWAY = "error: Public API request failed: 502 Bad Gateway <html></html>"
INTERNAL = "error: Public API request failed (500 Internal Server Error internal_server_error)"
RATE = "error: Public API request failed (429 Too Many Requests rate_limited)"
UNAUTH = "error: Public API request failed (401 Unauthorized unauthorized)"
NOT_FOUND = "error: Public API request failed (404 Not Found object_not_found)"

QUERY = ["api", "v1/data_sources/ds1/query", "-X", "POST"]
RESOLVE = ["datasources", "resolve", "db1", "--json"]
SCHEMA = ["api", "v1/data_sources/ds1"]
BLOCKS = ["api", "v1/blocks/p1/children", "page_size==100"]
CREATE = ["api", "v1/pages", "-X", "POST"]
PATCH = ["api", "v1/pages/p1", "-X", "PATCH"]


class Script:
    """Replays outcomes for subprocess.run: a string is stderr of a failed
    call, "timeout" a stalled one, a dict is stdout JSON of a good one."""

    def __init__(self, monkeypatch, *outcomes):
        self.outcomes = list(outcomes)
        self.calls = 0
        monkeypatch.setattr(ntn, "BACKOFF", (0.0, 0.0))
        monkeypatch.setattr(ntn.time, "sleep", lambda s: None)
        monkeypatch.setattr(subprocess, "run", self.run)

    def run(self, cmd, **kw):
        out = self.outcomes[min(self.calls, len(self.outcomes) - 1)]
        self.calls += 1
        if out == "timeout":
            raise subprocess.TimeoutExpired(cmd, kw.get("timeout", 0))
        if isinstance(out, str):
            return type("R", (), dict(returncode=1, stdout="", stderr=out))
        return type("R", (), dict(returncode=0, stdout='{"ok": 1}', stderr=""))


GOOD = {"ok": 1}


@pytest.mark.parametrize("args", [QUERY, RESOLVE, SCHEMA, BLOCKS])
@pytest.mark.parametrize("err", [BARE, BAD_GATEWAY, INTERNAL, RATE, "timeout"])
def test_a_read_retries_a_transient_failure(monkeypatch, args, err):
    s = Script(monkeypatch, err, GOOD)
    assert ntn.run_ntn(args) == {"ok": 1}
    assert s.calls == 2


def test_a_read_retries_twice_then_gives_up_with_the_old_message(monkeypatch):
    s = Script(monkeypatch, BARE)
    with pytest.raises(SystemExit) as exc:
        ntn.run_ntn(QUERY, {"a": 1})
    assert s.calls == 3
    assert str(exc.value).startswith("ntn api v1/data_sources/ds1/query -X failed:")
    assert "Failed to execute public API request" in str(exc.value)


@pytest.mark.parametrize("err", [UNAUTH, NOT_FOUND])
@pytest.mark.parametrize("args", [QUERY, RESOLVE, CREATE, PATCH])
def test_an_auth_or_request_error_fails_at_once(monkeypatch, args, err):
    s = Script(monkeypatch, err, GOOD)
    with pytest.raises(SystemExit):
        ntn.run_ntn(args, {"a": 1})
    assert s.calls == 1


@pytest.mark.parametrize("err", [BARE, BAD_GATEWAY, INTERNAL, "timeout"])
@pytest.mark.parametrize("args", [CREATE, PATCH,
                                  ["api", "v1/databases", "-X", "POST"]])
def test_a_write_is_never_retried_on_an_ambiguous_failure(monkeypatch, args, err):
    """The first attempt may have landed: a retried create mints a duplicate."""
    s = Script(monkeypatch, err, GOOD)
    with pytest.raises(SystemExit):
        ntn.run_ntn(args, {"a": 1})
    assert s.calls == 1


@pytest.mark.parametrize("args", [CREATE, PATCH])
def test_a_write_is_retried_on_a_429_only(monkeypatch, args):
    s = Script(monkeypatch, RATE, GOOD)
    assert ntn.run_ntn(args, {"a": 1}) == {"ok": 1}
    assert s.calls == 2


def test_a_timeout_gives_the_runner_message(monkeypatch):
    Script(monkeypatch, "timeout")
    with pytest.raises(SystemExit) as exc:
        ntn.run_ntn(QUERY, {"a": 1})
    assert "timed out after" in str(exc.value)


@pytest.mark.parametrize("args,expected", [
    (SCHEMA, True), (BLOCKS, True), (RESOLVE, True), (QUERY, True),
    (["api", "v1/pages/p1", "-X", "GET"], True),
    (["api", "v1/data_sources/ds1/query?x=1", "-X", "POST"], True),
    (CREATE, False), (PATCH, False),
    (["api", "v1/databases", "-X", "POST"], False),
    (["api", "v1/pages/p1", "-X", "DELETE"], False),
])
def test_is_read_classifies_the_calls_the_sources_make(args, expected):
    assert ntn.is_read(args) is expected


def test_every_notion_source_shares_the_one_runner():
    for mod in (notion, notion_taskboard, notion_taskboard_pull):
        assert mod._run_ntn is ntn.run_ntn
