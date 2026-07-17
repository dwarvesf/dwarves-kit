"""Hermes kanban spoke: ssh to the Mini, drive `hermes kanban` verbs only
(preserves CAS/event/notify integrity; never writes the sqlite directly).

Capability envelope (the CLI has no title/body edit and no reopen verb):
  - create with `--idempotency-key bls-<ID>` (duplicate-seed guard)
  - board shipped/done/resolved -> `complete`; dropped/parked -> `archive`
  - reverse: task `done` -> board shipped; `archived` -> board dropped
  - sync_fields=False: title/body are frozen at create (prevents stale-echo)
  - active-state moves and reopens are reported as skipped, not attempted
"""

import json
import shlex
import subprocess

ACTIVE = {"queued", "claimed", "speccing", "validated", "executing"}
COMPLETE_KWS = {"shipped", "done", "resolved"}
STATUS_FROM_HERMES = {"done": "shipped", "archived": "dropped"}


def _ssh_runner(target: str, script: str) -> str:
    r = subprocess.run(["ssh", target, "bash -s"], input=script,
                       capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        raise SystemExit(f"ssh {target} failed: {r.stderr.strip()[:500]}")
    return r.stdout


class HermesSource:
    name = "hermes"
    sync_fields = False

    def __init__(self, target: str = "mini-tieubao",
                 home: str = "/Users/tieubao/hermes-personal/home",
                 runner=None):
        self.target = target
        self.home = home
        self.runner = runner or (lambda s: _ssh_runner(self.target, s))

    def _preamble(self) -> str:
        return f"export HERMES_HOME={shlex.quote(self.home)}\nset -e\n"

    def preview(self, plan) -> list[str]:
        """Dry-run visibility for moves this spoke cannot represent."""
        return [f"hermes: cannot move {rid} to {kw} (no CLI verb); will skip"
                for rid, kw in plan.src_set_status
                if kw in ACTIVE and kw not in COMPLETE_KWS]

    def read(self) -> list[dict]:
        out = self.runner(self._preamble() +
                          "hermes kanban list --json\n"
                          "echo @@SEP@@\n"
                          "hermes kanban list --status archived --json\n")
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
                items.append({"rid": t["id"], "title": t.get("title") or "",
                              "done": t.get("status") in ("done", "archived"),
                              "body": t.get("body") or "", "status": kw})
        return items

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        lines = [self._preamble()]
        expected = []
        for bid, title, body, _kw in plan.src_create:
            expected.append(bid)
            lines.append(
                "hermes kanban create {t} --body {b} --idempotency-key "
                "bls-{bid} --created-by backlog-sync --json | python3 -c "
                "'import json,sys; print(\"@@CREATED {bid}\", "
                "json.load(sys.stdin)[\"id\"])'".format(
                    t=shlex.quote(title), b=shlex.quote(body), bid=bid))
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
            lines.append("hermes kanban complete " +
                         " ".join(shlex.quote(r) for r in completes) +
                         " --result 'closed on _meta/BACKLOG.md' || true")
        if archives:
            lines.append("hermes kanban archive " +
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
