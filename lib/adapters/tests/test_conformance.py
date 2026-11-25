"""Conformance: every app the registry lists builds a source object that follows the contract.

Nothing here reaches a store: an autouse guard makes the real transports raise, and every source
gets a recording fake in place of its `runner` before `read()` is called.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path
from types import SimpleNamespace

import pytest

import adapters

LIB = Path(__file__).resolve().parents[2]
CORE_DIRS = [str(LIB / "sync"), str(LIB / "sync" / "sweep"), str(LIB / "config")]
_REAL_RUN = subprocess.run
_REAL_POPEN = subprocess.Popen


def fresh_interpreter(argv, **kw):
    """Run a child Python for the isolation checks: the one transport this test file allows."""
    guarded = subprocess.Popen
    subprocess.Popen = _REAL_POPEN
    try:
        return _REAL_RUN(argv, capture_output=True, text=True, timeout=60, **kw)
    finally:
        subprocess.Popen = guarded


def _real_registry():
    """The registry of the running kit, whatever the environment says about the directory."""
    held = os.environ.pop("KIT_ADAPTERS_DIR", None)
    try:
        return adapters.load()
    finally:
        if held is not None:
            os.environ["KIT_ADAPTERS_DIR"] = held


APPS = sorted(_real_registry().apps)


@pytest.fixture(autouse=True)
def no_real_transport(monkeypatch, tmp_path):
    def refuse(*_a, **_k):
        raise AssertionError("real transport")

    monkeypatch.setattr(subprocess, "run", refuse)
    monkeypatch.setattr(subprocess, "Popen", refuse)
    monkeypatch.setattr(urllib.request, "urlopen", refuse)
    import socket
    monkeypatch.setattr(socket.socket, "connect", refuse)
    monkeypatch.delenv("KIT_ADAPTERS_DIR", raising=False)
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    (tmp_path / "home").mkdir()


class Recorder:
    def __init__(self):
        self.calls = []

    def __call__(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return "[]"


def default_opts(reg, app, tmp_path):
    """fixture-<key> strings for every opt row, over the adapter's own fixture-opts.json when it has one."""
    opts = {o.key: "fixture-" + o.key for o in reg.opts}
    adapter_dir = reg.dir / reg.apps[app][0]
    extra = adapter_dir / "fixture-opts.json"
    if extra.is_file():
        opts.update(json.loads(extra.read_text()))
    return opts


def build(reg, app, tmp_path):
    ctx = SimpleNamespace(state_path=tmp_path / f"{app}.state.json",
                          project_root=None)
    return reg.build(app, default_opts(reg, app, tmp_path), ctx)


@pytest.mark.parametrize("app", APPS)
def test_the_source_object_follows_the_contract(app, tmp_path, monkeypatch):
    monkeypatch.setenv("MULTICA_TOKEN", "fixture")
    reg = adapters.load()
    src = build(reg, app, tmp_path)
    assert src is not None
    assert src.name == app
    mode = reg.mode(app)
    assert bool(getattr(src, "create_only", False)) == (mode == "create-only")
    assert bool(getattr(src, "pull_only", False)) == (mode == "pull-only")
    assert callable(src.read)
    if mode == "pull-only":
        assert not hasattr(src, "apply")
    else:
        assert callable(src.apply)
    assert isinstance(getattr(src, "sync_fields", False), bool)


@pytest.mark.parametrize("app", APPS)
def test_read_reaches_the_runner_and_nothing_else(app, tmp_path, monkeypatch):
    monkeypatch.setenv("MULTICA_TOKEN", "fixture")
    reg = adapters.load()
    src = build(reg, app, tmp_path)
    fake = Recorder()
    src.runner = fake
    try:
        src.read()
    except (Exception, SystemExit):
        pass  # the fake's reply is not a real payload; reaching it is the point
    assert fake.calls, f"{app}: read() never called the runner"


def _stems(adapter_dir: Path) -> list:
    return sorted(f.stem for f in adapter_dir.glob("*.py") if f.stem != "adapter")


def test_sibling_module_stems_are_unique_across_adapters():
    reg = adapters.load()
    seen = {}
    for adapter in reg.adapters:
        for stem in _stems(adapter.path):
            assert stem not in seen, f"{stem} is in both {seen[stem]} and {adapter.name}"
            seen[stem] = adapter.name


def test_no_sibling_stem_shadows_the_standard_library_or_core():
    reg = adapters.load()
    stems = sorted({s for a in reg.adapters for s in _stems(a.path)})
    code = ("import importlib.util, json, sys\n"
            "sys.path[:0] = json.loads(sys.argv[1])\n"
            "print(json.dumps([s for s in json.loads(sys.argv[2]) "
            "if importlib.util.find_spec(s) is not None]))\n")
    r = fresh_interpreter([sys.executable, "-I", "-c", code, json.dumps(CORE_DIRS),
                           json.dumps(stems)])
    assert r.returncode == 0, r.stderr
    assert json.loads(r.stdout) == []


def test_each_adapter_module_sits_in_its_own_directory(tmp_path, monkeypatch):
    monkeypatch.setenv("MULTICA_TOKEN", "fixture")
    reg = adapters.load()
    done = set()
    for app in APPS:
        adapter = reg.apps[app][0]
        if adapter in done:
            continue
        done.add(adapter)
        build(reg, app, tmp_path)
        here = (reg.dir / adapter).resolve()
        mod = sys.modules["kit_adapter_" + adapter]
        assert Path(mod.__file__).resolve().parent == here
        for stem in _stems(here):
            held = sys.modules.get(stem)
            if held is not None:
                assert Path(held.__file__).resolve().parent == here


_ALONE = """
import json, sys
from pathlib import Path
from types import SimpleNamespace
sys.path[:0] = json.loads(sys.argv[1])
import adapters
reg = adapters.load()
app, opts, state = sys.argv[2], json.loads(sys.argv[3]), sys.argv[4]
src = reg.build(app, opts, SimpleNamespace(state_path=Path(state), project_root=None))
print("ok" if src is not None and src.name == app else "bad")
"""


@pytest.mark.parametrize("app", APPS)
def test_the_adapter_imports_alone_in_a_fresh_interpreter(app, tmp_path):
    reg = adapters.load()
    env = {"HOME": str(tmp_path / "home"), "PATH": os.environ.get("PATH", ""),
           "MULTICA_TOKEN": "fixture"}
    r = fresh_interpreter([sys.executable, "-I", "-c", _ALONE, json.dumps(CORE_DIRS), app,
                           json.dumps(default_opts(reg, app, tmp_path)),
                           str(tmp_path / f"{app}.state.json")], env=env)
    assert r.stdout.strip() == "ok", r.stderr


def test_legacy_reminders_state_is_copied_once_and_only_when_named(tmp_path, monkeypatch, capsys):
    legacy = tmp_path / "home" / ".cache" / "backlog-reminders-sync" / "state.json"
    legacy.parent.mkdir(parents=True)
    legacy.write_text('{"map": {"ID-1": {"rid": "legacy"}}}')
    reg = adapters.load()
    state = tmp_path / "state" / "reminders.state.json"
    state.parent.mkdir()
    opts = {"reminders_list": "ListA"}

    reg.build("reminders", opts, SimpleNamespace(state_path=state, project_root=None))
    assert state.read_text() == legacy.read_text()
    assert f"migrated legacy reminders state -> {state}" in capsys.readouterr().out

    state.write_text('{"map": {"ID-9": {"rid": "changed"}}}')
    before = state.read_bytes()
    reg.build("reminders", opts, SimpleNamespace(state_path=state, project_root=None))
    assert state.read_bytes() == before
    assert "migrated" not in capsys.readouterr().out


def test_a_run_naming_another_app_copies_no_legacy_state(tmp_path, monkeypatch, capsys):
    import backlog_sync
    monkeypatch.setattr(backlog_sync.kit_data, "path", lambda *a: str(tmp_path / "default-state"))
    legacy = tmp_path / "home" / ".cache" / "backlog-reminders-sync" / "state.json"
    legacy.parent.mkdir(parents=True)
    legacy.write_text('{"map": {}}')
    ext = tmp_path / "ext"
    ext.mkdir()
    (ext / "reminders").symlink_to(LIB / "adapters" / "reminders")
    fake = LIB / "sync" / "tests" / "fixtures" / "adapters" / "fake"
    (ext / "fake").mkdir()
    for name in ("adapter.tsv", "adapter.py"):
        (ext / "fake" / name).write_bytes((fake / name).read_bytes())
    monkeypatch.setenv("KIT_ADAPTERS_DIR", str(ext))
    board = tmp_path / "BACKLOG.md"
    board.write_text("## Active\n\n| ID | Item | Status | Notes |\n|---|---|---|---|\n"
                     "| ID-1 | x | queued | n |\n\n## Recently closed\n")
    root = tmp_path / "state-root"
    backlog_sync.main(["--backlog", str(board), "--state-root", str(root),
                       "--apps", "fake-two", "--dry-run"])
    assert "migrated" not in capsys.readouterr().out
    assert not list(root.glob("*/reminders.state.json"))


def test_github_takes_its_repo_from_the_flag_and_its_cwd_from_the_project_root(monkeypatch, tmp_path):
    import backlog_sync
    monkeypatch.setenv("KIT_PROJECT_ROOT", "/some/repo")
    args = SimpleNamespace(github_repo="owner/name")
    src = backlog_sync.build_source("github", args)
    assert (src.repo, src.cwd) == ("owner/name", "/some/repo")
    src = backlog_sync.build_source("github", SimpleNamespace(github_repo=None))
    assert (src.repo, src.cwd) == ("", "/some/repo")
    monkeypatch.delenv("KIT_PROJECT_ROOT")
    assert backlog_sync.build_source("github", args).cwd is None
