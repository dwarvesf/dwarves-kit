"""Hermes adapter tests against a fake ssh transport (no network)."""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from sources.hermes import HermesSource, _target_cmd  # noqa: E402
from sync_core import Plan  # noqa: E402


class FakeSsh:
    def __init__(self, output=""):
        self.scripts = []
        self.output = output

    def __call__(self, script):
        self.scripts.append(script)
        return self.output


def make_src(output=""):
    fake = FakeSsh(output)
    src = HermesSource(runner=fake)
    return src, fake


def test_read_merges_live_and_archived_and_normalizes():
    live = json.dumps([
        {"id": "t1", "title": "ID-10 · Fix it", "body": "b", "status": "todo"},
        {"id": "t2", "title": "ID-12 · Old", "body": "", "status": "done"},
        {"id": "t3", "title": "foreign task", "body": "d", "status": "ready"},
    ])
    archived = json.dumps([
        {"id": "t4", "title": "ID-13 · Dropped", "body": "", "status": "archived"},
        {"id": "t2", "title": "dup", "body": "", "status": "done"},  # dedup
    ])
    src, fake = make_src(f"{live}\n@@SEP@@\n{archived}\n")
    items = src.read()
    assert [(i["rid"], i["status"], i["done"]) for i in items] == [
        ("t1", None, False), ("t2", "shipped", True),
        ("t3", None, False), ("t4", "dropped", True)]
    assert "HERMES_HOME=/Users/tieubao/hermes-personal/home" in fake.scripts[0]
    assert "--status archived" in fake.scripts[0]


def test_apply_creates_with_idempotency_key_and_quoting():
    src, fake = make_src("@@CREATED ID-10 t_aa\n@@CREATED ID-11 t_bb\n")
    plan = Plan(src_create=[
        ("ID-10", "ID-10 · Fix 'quoted' thing", "body with $var", "queued"),
        ("ID-11", "ID-11 · Ship it", "", "executing")])
    created = src.apply(plan, {}, {})
    assert created == {"ID-10": "t_aa", "ID-11": "t_bb"}
    script = fake.scripts[0]
    assert "--idempotency-key bls-ID-10" in script
    assert "--created-by backlog-sync" in script
    assert "'body with $var'" in script  # shell-quoted, not interpolated


def test_apply_routes_statuses_and_skips_unrepresentable(capsys):
    src, fake = make_src("")
    plan = Plan(src_set_status=[("t1", "shipped"), ("t2", "resolved"),
                                ("t3", "dropped"), ("t4", "parked"),
                                ("t5", "queued")])
    src.apply(plan, {}, {})
    script = fake.scripts[0]
    assert "hermes kanban complete t1 t2" in script
    assert "hermes kanban archive t3 t4" in script
    assert "t5" not in script
    assert "cannot move t5 to queued" in capsys.readouterr().out


def test_apply_missing_created_id_fails_loud():
    src, _ = make_src("")  # runner returns no @@CREATED lines
    plan = Plan(src_create=[("ID-10", "t", "b", "queued")])
    with pytest.raises(SystemExit, match="ID-10"):
        src.apply(plan, {}, {})


def test_preview_reports_unrepresentable_moves():
    src, _ = make_src()
    plan = Plan(src_set_status=[("t1", "queued"), ("t2", "shipped")])
    notes = src.preview(plan)
    assert notes == ["hermes: cannot move t1 to queued (no CLI verb); "
                     "will skip"]


def test_sync_fields_is_false():
    assert HermesSource(runner=FakeSsh()).sync_fields is False


def test_apply_noop_makes_no_ssh_call():
    src, fake = make_src("")
    assert src.apply(Plan(), {}, {}) == {}
    assert fake.scripts == []


# --- instance reach: target, board, assignee, workspace ---------------------

def test_target_forms_pick_ssh_local_or_sudo():
    assert _target_cmd("mini-tieubao") == ["ssh", "mini-tieubao", "bash -s"]
    assert _target_cmd("local") == ["bash", "-s"]
    assert _target_cmd("sudo:server") == [
        "sudo", "-n", "-u", "server", "-H", "bash", "-s"]


def test_board_flag_rides_reads_and_writes():
    """Reading one board while writing another would hide a just-created task
    from the planner, so the flag has to be on both."""
    reader = FakeSsh("[]\n@@SEP@@\n[]\n")
    HermesSource(runner=reader, board="dw-ops").read()
    assert reader.scripts[0].count("hermes kanban --board dw-ops list") == 2
    fake = FakeSsh("@@CREATED ID-10 t_aa\n")
    HermesSource(runner=fake, board="dw-ops").apply(
        Plan(src_create=[("ID-10", "ID-10 · x", "b", "queued")],
             src_set_status=[("t1", "shipped"), ("t2", "dropped")]), {}, {})
    write = fake.scripts[0]
    assert "hermes kanban --board dw-ops create" in write
    assert "hermes kanban --board dw-ops complete t1" in write
    assert "hermes kanban --board dw-ops archive t2" in write


def test_no_board_configured_leaves_the_command_bare():
    fake = FakeSsh("[]\n@@SEP@@\n[]\n")
    HermesSource(runner=fake).read()
    assert "--board" not in fake.scripts[0]


def test_create_carries_assignee_and_per_id_workspace():
    fake = FakeSsh("@@CREATED ID-10 t_aa\n@@CREATED ID-11 t_bb\n")
    src = HermesSource(runner=fake, assignee="chief-of-staff",
                       workspace="dir:/srv/outbox/{id}")
    src.apply(Plan(src_create=[("ID-10", "ID-10 · a", "", "queued"),
                               ("ID-11", "ID-11 · b", "", "queued")]), {}, {})
    script = fake.scripts[0]
    assert "--assignee chief-of-staff" in script
    # one directory per task: a shared path would have them overwrite each other
    assert "--workspace dir:/srv/outbox/ID-10" in script
    assert "--workspace dir:/srv/outbox/ID-11" in script


def test_assignee_and_workspace_are_shell_quoted():
    fake = FakeSsh("@@CREATED ID-10 t_aa\n")
    src = HermesSource(runner=fake, assignee="a b;rm -rf /",
                       workspace="dir:/srv/o u t/{id}")
    src.apply(Plan(src_create=[("ID-10", "ID-10 · a", "", "queued")]), {}, {})
    script = fake.scripts[0]
    assert "'a b;rm -rf /'" in script
    assert "rm -rf /'" in script and ";rm -rf / " not in script


def test_unconfigured_create_is_unchanged():
    """Default construction must emit exactly what it emitted before."""
    fake = FakeSsh("@@CREATED ID-10 t_aa\n")
    HermesSource(runner=fake).apply(
        Plan(src_create=[("ID-10", "ID-10 · a", "", "queued")]), {}, {})
    script = fake.scripts[0]
    assert "--assignee" not in script and "--workspace" not in script
