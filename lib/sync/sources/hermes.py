"""Hermes kanban spoke: reach a Hermes instance, drive `hermes kanban` verbs
only (preserves CAS/event/notify integrity; never writes the sqlite directly).

Capability envelope (the CLI has no title/body edit and no reopen verb):
  - create with `--idempotency-key bls-<ID>` (duplicate-seed guard)
  - board shipped/done/resolved -> `complete`; dropped/parked -> `archive`
  - reverse: task `done` -> board shipped; `archived` -> board dropped
  - sync_fields=False: title/body are frozen at create (prevents stale-echo)
  - active-state moves and reopens are reported as skipped, not attempted

Instance selection is three separate axes, because one host runs several
instances and a consumer usually wants a specific board inside one of them:
`target` says which machine and uid, `home` says which instance, `board` says
which board. `assignee` and `workspace` shape what a create looks like, since
an unassigned task on a scratch workspace is inert for a consumer whose
workers pick up by profile and whose deliverables must outlive completion.
"""

import json
import shlex
import subprocess

from cockpit import (mark_untrusted_body, mark_untrusted_title,
                     unmark_untrusted_body, unmark_untrusted_title)

ACTIVE = {"queued", "claimed", "speccing", "validated", "executing"}
COMPLETE_KWS = {"shipped", "done", "resolved"}
STATUS_FROM_HERMES = {"done": "shipped", "archived": "dropped"}


def _target_cmd(target: str) -> list:
    """Argv that runs a bash script fed on stdin, where the instance lives.

    Three forms, because an instance is not always one ssh hop away:

      <host>       ssh to that host, the original and still the default
      local        this host, this uid
      sudo:<user>  this host, another uid

    `sudo:` exists for a job that shares a host with an instance owned by a
    daemon account. That instance's HERMES_HOME is mode 0700, so ssh is not
    the barrier, the uid is, and a job account with a NOPASSWD rule already
    holds the only credential the hop needs. `-H` is load-bearing: the CLI
    reads a per-user dotenv, so the caller's HOME leaking through makes it
    fail on a file it must not read anyway. `-n` keeps an unattended run from
    ever waiting on a password prompt.
    """
    if target == "local":
        return ["bash", "-s"]
    if target.startswith("sudo:"):
        return ["sudo", "-n", "-u", target.split(":", 1)[1], "-H", "bash", "-s"]
    return ["ssh", target, "bash -s"]


def _ssh_runner(target: str, script: str) -> str:
    r = subprocess.run(_target_cmd(target), input=script,
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        raise SystemExit(f"hermes target {target} failed: "
                         f"{r.stderr.strip()[:500]}")
    return r.stdout


class HermesSource:
    name = "hermes"
    sync_fields = False

    # No default target/home: both name ONE operator's machine, so a default here
    # would silently sync the wrong instance on anyone else's box. The caller
    # (backlog_sync.build_source) fails loudly when either is unset.
    def __init__(self, target: str, home: str,
                 runner=None, board: str | None = None,
                 assignee: str | None = None,
                 workspace: str | None = None):
        self.target = target
        self.home = home
        self.board = board
        self.assignee = assignee
        # `{id}` interpolates the board id, so every relayed task gets its own
        # directory. A single fixed path for all creates would have them
        # overwrite each other's files.
        self.workspace = workspace
        self.runner = runner or (lambda s: _ssh_runner(self.target, s))

    def _preamble(self) -> str:
        return f"export HERMES_HOME={shlex.quote(self.home)}\nset -e\n"

    def _kanban(self) -> str:
        """`hermes kanban` with the board selected, when one is configured.
        The flag sits before the subcommand, and it goes on reads as well as
        writes: relaying onto one board while reading another would leave the
        planner unable to see what it just created."""
        if not self.board:
            return "hermes kanban"
        return f"hermes kanban --board {shlex.quote(self.board)}"

    def preview(self, plan) -> list[str]:
        """Dry-run visibility for moves this spoke cannot represent."""
        return [f"hermes: cannot move {rid} to {kw} (no CLI verb); will skip"
                for rid, kw in plan.src_set_status
                if kw in ACTIVE and kw not in COMPLETE_KWS]

    def read(self) -> list[dict]:
        kb = self._kanban()
        out = self.runner(self._preamble() +
                          f"{kb} list --json\n"
                          "echo @@SEP@@\n"
                          f"{kb} list --status archived --json\n")
        live_raw, _, arch_raw = out.partition("@@SEP@@")
        items = []
        seen = set()
        for raw in (live_raw, arch_raw):
            raw = raw.strip()
            for t in (json.loads(raw) if raw else []):
                if t["id"] in seen:
                    continue
                seen.add(t["id"])
                kw = STATUS_FROM_HERMES.get(t.get("status"))
                # Strip the untrusted markers this leg applied at create, so the
                # planner's title-prefix re-link (sync_core.parse_title) still
                # recovers the bare `ID-NNN`. Without this, a state-loss re-sync
                # reads `[untrusted] ID-9 ...`, fails to re-link, and re-mints
                # the card as a junk board row (double-mapped rid).
                title = unmark_untrusted_title(t.get("title") or "")
                body = unmark_untrusted_body(t.get("body") or "")
                items.append({"rid": t["id"], "title": title,
                              "done": t.get("status") in ("done", "archived"),
                              "body": body, "status": kw})
        return items

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        kb = self._kanban()
        lines = [self._preamble()]
        expected = []
        for bid, title, body, _kw in plan.src_create:
            expected.append(bid)
            extra = ""
            if self.assignee:
                extra += f" --assignee {shlex.quote(self.assignee)}"
            if self.workspace:
                extra += " --workspace " + shlex.quote(
                    self.workspace.format(id=bid))
            # A created card's title/body is git-board content = DATA, never
            # instructions to whatever Hermes agent later reads this board. This
            # is a LOAD leg, so it MUST route card text through the untrusted
            # markers (SPEC-147), same as board-mirror.sh and cockpit's leg.
            # sync_fields=False freezes these at create, so marking once here
            # never double-wraps on a re-sync.
            title = mark_untrusted_title(title)
            body = mark_untrusted_body(body)
            lines.append(
                "{kb} create {t} --body {b}{x} --idempotency-key "
                "bls-{bid} --created-by backlog-sync --json | python3 -c "
                "'import json,sys; print(\"@@CREATED {bid}\", "
                "json.load(sys.stdin)[\"id\"])'".format(
                    kb=kb, t=shlex.quote(title), b=shlex.quote(body),
                    x=extra, bid=bid))
        completes, archives, skipped = [], [], []
        archives.extend(rid for _bid, rid in plan.src_scope_exit)
        for rid, kw in plan.src_set_status:
            if kw in COMPLETE_KWS:
                completes.append(rid)
            elif kw in ("dropped", "parked"):
                archives.append(rid)
            else:
                skipped.append((rid, kw))  # no reopen / active-move verb
        if completes:
            lines.append(f"{kb} complete " +
                         " ".join(shlex.quote(r) for r in completes) +
                         " --result 'closed on _meta/BACKLOG.md' || true")
        if archives:
            lines.append(f"{kb} archive " +
                         " ".join(shlex.quote(r) for r in archives) + " || true")
        for rid, kw in skipped:
            print(f"  · note      hermes: cannot move {rid} to {kw} "
                  "(no CLI verb); skipped")
        if len(lines) == 1:
            return {}
        out = self.runner("\n".join(lines) + "\n")
        created = {}
        for line in out.splitlines():
            if line.startswith("@@CREATED "):
                _, bid, rid = line.split()
                created[bid] = rid
        missing = [b for b in expected if b not in created]
        if missing:
            raise SystemExit(f"hermes: creates did not return ids for "
                             f"{missing[:5]}{'...' if len(missing) > 5 else ''}")
        return created
