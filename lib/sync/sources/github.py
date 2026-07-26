"""GitHub Issues spoke: drive the `gh` CLI only (auth, remotes, and retries
stay gh's problem; no token ever passes through this process).

The team-collab proposal (2026-07-04 §7) names GitHub Issues as the board
surface for code repos; this is that adapter, same hub-and-spoke rules as the
others: board wins on conflict, spoke deletions never touch the board.

Capability envelope (GitHub has open/closed and nothing finer):
  - create with a `bls: <ID>` body marker as the idempotency guard (GitHub has
    no idempotency key; read() surfaces the marker so a re-run adopts instead
    of duplicating)
  - board shipped/done/resolved -> close; dropped/parked -> close with a
    comment saying which, so the distinction survives in the thread
  - reverse: a closed issue reads back as shipped (finer states cannot be
    inferred from closed alone)
  - unlike Hermes this spoke CAN reopen: a board row moving back to an active
    state reopens its closed issue (git wins, visibly)
  - sync_fields=False: title/body freeze at create. Teammates retitling an
    issue must not stale-echo the board; the row is the record.
"""

import json
import subprocess

ACTIVE = {"queued", "claimed", "speccing", "validated", "executing"}
COMPLETE_KWS = {"shipped", "done", "resolved"}
MARKER = "bls: "


def _gh_runner(argv: list, cwd: str | None = None) -> str:
    r = subprocess.run(["gh"] + argv, capture_output=True, text=True,
                       timeout=120, cwd=cwd or None)
    if r.returncode != 0:
        raise SystemExit(f"gh {' '.join(argv[:3])}... failed: "
                         f"{r.stderr.strip()[:500]}")
    return r.stdout


class GitHubSource:
    name = "github"
    sync_fields = False

    def __init__(self, repo: str = "", runner=None, cwd: str | None = None):
        # repo empty = whatever `gh` resolves from the origin remote of `cwd`
        # (the repo that owns the backlog, threaded in as KIT_PROJECT_ROOT by
        # cmd_sync). Relying on the PROCESS cwd broke the first launchd run:
        # the cron launcher starts nowhere near the checkout, gh saw "not a
        # git repository", and every scheduled sync exited 1. Interactive runs
        # never caught it because a shell is always inside the repo.
        self.repo = repo
        self.cwd = cwd
        self.runner = runner or (lambda argv: _gh_runner(argv, self.cwd))

    def _flags(self) -> list:
        return ["-R", self.repo] if self.repo else []

    def read(self) -> list[dict]:
        raw = self.runner(["issue", "list", *self._flags(), "--state", "all",
                           "--limit", "500",
                           "--json", "number,title,state,body"])
        items = []
        for t in json.loads(raw or "[]"):
            closed = t.get("state") == "CLOSED"
            # status stays None: closed carries no shipped-vs-dropped signal,
            # and asserting "shipped" here overrides the engine's three-way
            # merge (measured live: a re-sync flipped a dropped row to shipped
            # because this claimed to know more than GitHub does). The `done`
            # flag is the whole truth a binary spoke has; the engine derives
            # the keyword against its snapshot, same as the Reminders spoke.
            items.append({"rid": str(t["number"]),
                          "title": t.get("title") or "",
                          "done": closed,
                          "body": t.get("body") or "",
                          "status": None})
        return items

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        created = {}
        for bid, title, body, _kw in plan.src_create:
            # The marker is the idempotency guard: read() returns bodies, so
            # the planner has already matched rows to marked issues; anything
            # still in src_create is genuinely new.
            url = self.runner(["issue", "create", *self._flags(),
                               "--title", title,
                               "--body", f"{body}\n\n{MARKER}{bid}"]).strip()
            rid = url.rstrip("/").rsplit("/", 1)[-1]
            if not rid.isdigit():
                raise SystemExit(f"github: create for {bid} returned no "
                                 f"issue url: {url[:200]}")
            created[bid] = rid
        for _bid, rid in plan.src_scope_exit:
            self.runner(["issue", "close", *self._flags(), rid,
                         "-c", "left the sync scope on _meta/BACKLOG.md"])
        for rid, kw in plan.src_set_status:
            if kw in COMPLETE_KWS:
                self.runner(["issue", "close", *self._flags(), rid,
                             "-c", "closed on _meta/BACKLOG.md"])
            elif kw in ("dropped", "parked"):
                self.runner(["issue", "close", *self._flags(), rid,
                             "-c", f"{kw} on _meta/BACKLOG.md"])
            elif kw in ACTIVE:
                # Board says live, issue is closed: reopen, git wins.
                self.runner(["issue", "reopen", *self._flags(), rid,
                             "-c", f"board row is {kw}; reopened from "
                                   "_meta/BACKLOG.md"])
        return created
