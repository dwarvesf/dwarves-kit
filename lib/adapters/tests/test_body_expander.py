"""The page-body relay: a card the Hermes adapter creates carries the body that the Notion adapter's
`body_expander` hook fetches, and the hook comes from the registry, never from a core import.

Nothing here reaches Notion or a Hermes host: the block transport and the ssh runner are fakes, and the
broken-provider cases run in a child interpreter whose process-wide transports refuse every call.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

import adapters
import backlog_sync
from notion_taskboard_pull import PAGE_BODY_UNAVAILABLE, expand_body
from sync_core import Plan
from test_notion_taskboard_pull import HEX_A, FakeBlocks, blk, intake_notes

ADAPTERS = Path(__file__).resolve().parents[1]
CORE_DIRS = [str(ADAPTERS.parent / "sync"), str(ADAPTERS.parent / "sync" / "sweep"),
             str(ADAPTERS.parent / "config")]
HERMES_OPTS = {"hermes_home": "/srv/h", "hermes_target": "box"}


@pytest.fixture
def adapter_dir(tmp_path, monkeypatch):
    """Point the loader at a temp directory and undo what the loader leaves in the process."""
    before_path, before_mods = list(sys.path), set(sys.modules)
    ext = tmp_path / "ext"
    ext.mkdir()
    monkeypatch.setenv("KIT_ADAPTERS_DIR", str(ext))
    yield ext
    sys.path[:] = before_path
    for name in set(sys.modules) - before_mods:
        if name.startswith("kit_adapter_"):
            del sys.modules[name]


def build_hermes(reg):
    return reg.build("hermes", dict(HERMES_OPTS), SimpleNamespace(state_path=None, project_root=None))


def relay(src, notes, blocks):
    """Create one card through `src` with the registry's hook reading blocks from `blocks`."""
    ssh = []
    hook = src.body_expander
    src.runner = lambda s: ssh.append(s) or "@@CREATED DF-1 t1\n"
    src.body_expander = lambda body: hook(body, blocks)
    created = src.apply(Plan(src_create=[("DF-1", "DF-1 · t", notes, "queued")]), {}, {})
    return created, ssh


def test_hermes_create_carries_the_page_body_and_the_row_does_not(tmp_path, adapter_dir):
    for name in ("hermes", "notion"):
        (adapter_dir / name).symlink_to(ADAPTERS / name)
    notes = intake_notes(tmp_path)
    blocks = FakeBlocks({HEX_A: [[blk("paragraph", "Steps: open the vault.")]]})
    created, ssh = relay(build_hermes(adapters.load()), notes, blocks)
    assert created == {"DF-1": "t1"}
    assert "Page body:\nSteps: open the vault." in ssh[0]
    assert "Steps: open the vault." not in notes


def test_hermes_create_survives_a_failed_page_fetch(tmp_path, adapter_dir):
    for name in ("hermes", "notion"):
        (adapter_dir / name).symlink_to(ADAPTERS / name)
    notes = intake_notes(tmp_path)
    created, ssh = relay(build_hermes(adapters.load()), notes,
                         FakeBlocks(fail=SystemExit("ntn: 500")))
    assert created == {"DF-1": "t1"}
    assert PAGE_BODY_UNAVAILABLE in ssh[0]


def test_build_source_wires_the_expander_into_hermes():
    args = type("A", (), dict(
        hermes_home="/srv/h", hermes_target="box", hermes_board=None,
        hermes_assignee=None, hermes_workspace=None))
    assert backlog_sync.build_source("hermes", args).body_expander is expand_body


def test_the_hook_comes_from_whichever_adapter_declares_it(adapter_dir):
    (adapter_dir / "hermes").symlink_to(ADAPTERS / "hermes")
    reg = adapters.load()
    assert reg.hook("body_expander") is None
    (adapter_dir / "notion").symlink_to(ADAPTERS / "notion")
    reg = adapters.load()
    assert reg.hook("body_expander") is expand_body


def test_with_no_provider_the_card_is_created_with_the_body_as_it_is(tmp_path, adapter_dir):
    (adapter_dir / "hermes").symlink_to(ADAPTERS / "hermes")
    src = build_hermes(adapters.load())
    assert src.body_expander is None
    notes = intake_notes(tmp_path)
    ssh = []
    src.runner = lambda s: ssh.append(s) or "@@CREATED DF-1 t1\n"
    created = src.apply(Plan(src_create=[("DF-1", "DF-1 · t", notes, "queued")]), {}, {})
    assert created == {"DF-1": "t1"}
    assert "Page body:" not in ssh[0]


_CHILD = """
import json, subprocess, sys
sys.path[:0] = json.loads(sys.argv[1])
reached = []

def refuse(*a, **k):
    reached.append(1)
    raise AssertionError("real transport")

subprocess.run = refuse
subprocess.Popen = refuse
import backlog_sync
args = type("A", (), dict(hermes_home="/srv/h", hermes_target="box", hermes_board=None,
                          hermes_assignee=None, hermes_workspace=None))
try:
    backlog_sync.build_source("hermes", args)
except SystemExit as exc:
    print("exit:", exc)
    sys.exit(3 if not reached else 4)
print("built")
"""


def _broken_provider_run(tmp_path, adapter_py):
    ext = tmp_path / "ext"
    ext.mkdir()
    (ext / "hermes").symlink_to(ADAPTERS / "hermes")
    bad = ext / "notion"
    bad.mkdir()
    (bad / "adapter.tsv").write_text("app\tnotion\ttwo-way\nhook\tbody_expander\n")
    (bad / "adapter.py").write_text(adapter_py)
    env = {"PATH": os.environ.get("PATH", ""), "HOME": str(tmp_path / "home"),
           "KIT_ADAPTERS_DIR": str(ext)}
    return subprocess.run([sys.executable, "-I", "-c", _CHILD, json.dumps(CORE_DIRS)],
                          capture_output=True, text=True, timeout=60, env=env)


@pytest.mark.parametrize("adapter_py,why", [
    ("def build(app, opts, ctx:\n    return None\n", "a syntax error"),
    ("from __future__ import annotations\n\n\ndef build(app, opts, ctx):\n    return None\n",
     "a missing function")])
def test_a_provider_that_declares_the_hook_and_fails_stops_the_run(tmp_path, adapter_py, why):
    r = _broken_provider_run(tmp_path, adapter_py)
    assert r.returncode == 3, (why, r.stdout, r.stderr)
    assert "hook body_expander from notion failed" in r.stdout
    assert "built" not in r.stdout


def test_a_healthy_provider_builds_in_the_same_child(tmp_path):
    ok = ("from __future__ import annotations\n\n\ndef build(app, opts, ctx):\n    return None\n\n\n"
          "def body_expander(body):\n    return body\n")
    r = _broken_provider_run(tmp_path, ok)
    assert r.returncode == 0 and "built" in r.stdout, (r.stdout, r.stderr)
