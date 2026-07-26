"""GitHub adapter tests against a fake gh transport (no network)."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.github import GitHubSource  # noqa: E402
from sync_core import Plan  # noqa: E402


class FakeGh:
    def __init__(self, outputs=None):
        self.calls = []
        self.outputs = list(outputs or [])

    def __call__(self, argv):
        self.calls.append(argv)
        return self.outputs.pop(0) if self.outputs else ""


def test_read_normalizes_states():
    fake = FakeGh([json.dumps([
        {"number": 7, "title": "fix panel", "state": "OPEN", "body": "b"},
        {"number": 8, "title": "old bug", "state": "CLOSED", "body": ""},
    ])])
    items = GitHubSource(runner=fake).read()
    assert items[0] == {"rid": "7", "title": "fix panel", "done": False,
                        "body": "b", "status": None}
    assert items[1]["done"] is True
    # closed carries no shipped-vs-dropped signal; the engine derives the
    # keyword from `done` + its snapshot. Asserting shipped here flipped a
    # dropped row live.
    assert items[1]["status"] is None
    # repo unset: no -R flag leaks into the call
    assert "-R" not in fake.calls[0]


def test_repo_flag_threaded_through():
    fake = FakeGh(["[]"])
    GitHubSource(repo="dwarvesf/whetstone", runner=fake).read()
    i = fake.calls[0].index("-R")
    assert fake.calls[0][i + 1] == "dwarvesf/whetstone"


def test_apply_creates_with_marker_and_returns_rid():
    fake = FakeGh(["https://github.com/o/r/issues/12\n"])
    plan = Plan(src_create=[("WS-4", "decide the thing", "notes", "queued")])
    created = GitHubSource(runner=fake).apply(plan, {}, {})
    assert created == {"WS-4": "12"}
    argv = fake.calls[0]
    body = argv[argv.index("--body") + 1]
    assert "bls: WS-4" in body  # the idempotency marker


def test_apply_close_drop_and_reopen_verbs():
    fake = FakeGh(["", "", ""])
    plan = Plan(src_set_status=[("7", "shipped"), ("8", "dropped"),
                                ("9", "queued")])
    GitHubSource(runner=fake).apply(plan, {}, {})
    verbs = [c[1] for c in fake.calls]
    assert verbs == ["close", "close", "reopen"]
    # dropped keeps its name in the comment; the reopen says git wins
    assert "dropped" in " ".join(fake.calls[1])
    assert "queued" in " ".join(fake.calls[2])


def test_apply_create_without_url_fails_closed():
    fake = FakeGh(["not a url"])
    plan = Plan(src_create=[("WS-9", "t", "b", "queued")])
    try:
        GitHubSource(runner=fake).apply(plan, {}, {})
    except SystemExit as e:
        assert "WS-9" in str(e)
    else:
        raise AssertionError("apply accepted a create with no issue url")
