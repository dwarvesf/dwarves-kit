"""Multica spoke: REST against a self-hosted Multica board (the team pilot at
multica.d.foundation; see ops-toolkit tools/multica-deploy). Board rows mirror
into one Multica project as issues.

Auth: personal access token in the MULTICA_TOKEN env var (board.sh resolves it
from 1Password at invocation; never an argv flag, argv leaks in ps). Workspace
is selected per-request via ?workspace_id= (CLI/daemon compat path in the
server's workspace middleware).

Status mapping: Multica has a fixed status enum, one coarser than the board's
state machine (speccing/claimed both land on `todo`). A naive reverse map
would misread an untouched issue as a status *change* (speccing -> todo ->
reverse claimed), so each issue carries its exact board state in an HTML
comment marker at the end of its description: `<!-- board:speccing -->`.
read() trusts the marker while the Multica status still equals the marker's
forward image; the moment someone moves the issue on the Multica board, the
marker is stale and the reverse map speaks. Sync rewrites the marker on every
status/body write.

Issues are created UNASSIGNED and in `backlog`/`todo`-family states only;
assigning an agent is what dispatches execution in Multica, and that stays a
human act on the Multica UI (the multica-eval cost lesson).
"""

import json
import os
import urllib.error
import urllib.parse
import urllib.request

MARKER_PREFIX = "<!-- board:"
MARKER_SUFFIX = " -->"
TO_MULTICA = {"queued": "backlog", "claimed": "todo", "speccing": "todo",
              "validated": "in_review", "executing": "in_progress",
              "shipped": "done", "parked": "blocked", "dropped": "cancelled"}
FROM_MULTICA = {"backlog": "queued", "todo": "claimed",
                "in_progress": "executing", "in_review": "validated",
                "done": "shipped", "blocked": "parked", "cancelled": "dropped"}
PAGE = 100


def _http_runner(url: str, token: str):
    def run(method: str, path: str, body: dict | None = None) -> dict:
        req = urllib.request.Request(
            url.rstrip("/") + path, method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {token}",
                     "Content-Type": "application/json",
                     # Cloudflare's Browser Integrity Check 403s the default
                     # Python-urllib UA (error 1010); name ourselves honestly
                     "User-Agent": "backlog-sync-multica/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:300]
            raise SystemExit(f"multica: {method} {path} -> {e.code} {detail}")
        except urllib.error.URLError as e:
            raise SystemExit(f"multica: {method} {path} unreachable: {e.reason}")
        return json.loads(raw) if raw.strip() else {}
    return run


def split_marker(description: str) -> tuple[str, str | None]:
    """(body-without-marker, board kw from the marker or None)."""
    text = (description or "").rstrip()
    i = text.rfind(MARKER_PREFIX)
    if i < 0 or not text.endswith(MARKER_SUFFIX):
        return text, None
    kw = text[i + len(MARKER_PREFIX):-len(MARKER_SUFFIX)].strip()
    if kw not in TO_MULTICA:
        return text, None
    return text[:i].rstrip(), kw


def with_marker(body: str, kw: str) -> str:
    body = (body or "").rstrip()
    marker = f"{MARKER_PREFIX}{kw}{MARKER_SUFFIX}"
    return f"{body}\n\n{marker}" if body else marker


class MulticaSource:
    name = "multica"
    sync_fields = True

    def __init__(self, url: str, workspace: str, project: str,
                 token: str | None = None, runner=None):
        self.workspace = workspace
        self.project = project
        if runner is None:
            token = token or os.environ.get("MULTICA_TOKEN")
            if not token:
                raise SystemExit(
                    "multica: no token. Set multica_token_ref in [sync] "
                    "(.kit.toml) or export MULTICA_TOKEN.")
            runner = _http_runner(url, token)
        self.runner = runner
        # read()-time caches; apply() needs them to rewrite the description
        # marker without clobbering the body (and vice versa).
        self._body: dict[str, str] = {}
        self._kw: dict[str, str | None] = {}

    def _qs(self, **extra) -> str:
        q = {"workspace_id": self.workspace, "project_id": self.project}
        q.update(extra)
        return "?" + urllib.parse.urlencode(q)

    def read(self) -> list[dict]:
        items, offset = [], 0
        while True:
            resp = self.runner("GET", "/api/issues" +
                               self._qs(limit=PAGE, offset=offset))
            page = resp.get("issues") or []
            for it in page:
                rid = it["id"]
                m_status = it.get("status") or ""
                body, marker_kw = split_marker(it.get("description") or "")
                if marker_kw and TO_MULTICA[marker_kw] == m_status:
                    kw = marker_kw  # untouched on the Multica side
                else:
                    kw = FROM_MULTICA.get(m_status)
                self._body[rid] = body
                self._kw[rid] = kw
                items.append({"rid": rid, "title": it.get("title") or "",
                              "done": m_status in ("done", "cancelled"),
                              "body": body, "status": kw})
            offset += len(page)
            if len(page) < PAGE:
                return items

    def _put(self, rid: str, body: dict) -> None:
        self.runner("PUT", f"/api/issues/{rid}" + self._qs(), body)

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        created = {}
        for bid, title, body, kw in plan.src_create:
            resp = self.runner("POST", "/api/issues" + self._qs(), {
                "title": title, "description": with_marker(body, kw),
                "status": TO_MULTICA[kw], "project_id": self.project})
            rid = resp.get("id") or (resp.get("issue") or {}).get("id")
            if not rid:
                raise SystemExit(f"multica: create for {bid} returned no id")
            created[bid] = rid
            self._body[rid], self._kw[rid] = body, kw
        for rid, kw in plan.src_set_status:
            self._kw[rid] = kw
            self._put(rid, {"status": TO_MULTICA[kw],
                            "description": with_marker(self._body.get(rid, ""),
                                                       kw)})
        for _bid, rid in plan.src_scope_exit:
            # filtered off this app: park the issue in the dropped column
            self._put(rid, {"status": TO_MULTICA["dropped"]})
        for rid, body in plan.src_set_body:
            self._body[rid] = body
            kw = self._kw.get(rid) or "queued"
            self._put(rid, {"description": with_marker(body, kw)})
        for rid, title in plan.src_set_title:
            self._put(rid, {"title": title})
        for rid, _t, _b, _kw in plan.board_add:
            bid = assigned.get(rid)
            if bid and bid in rows_after:
                row = rows_after[bid]
                self._body[rid], self._kw[rid] = row.notes, row.status_kw
                self._put(rid, {"title": f"{bid} · {row.item}",
                                "description": with_marker(row.notes,
                                                           row.status_kw),
                                "status": TO_MULTICA[row.status_kw]})
        return created
