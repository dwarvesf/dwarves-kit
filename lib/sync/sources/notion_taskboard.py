"""Notion Task Board sink: ONE-WAY, insert-only push of board rows to a
foreign, team-OWNED Notion board. Drives the `ntn` CLI (keychain auth, Han's
Notion rule). See docs/specs/SPEC-003-oneway-create-push.md (ID-138).

Insert-only by contract: the team owns each card after it lands, so the sink
sets fields on page-create and never touches them again (the local sync-state
map is the identity index; a bid already in the map is never re-pushed). Status
/ Priority / Weight are mapped to the team board's OWN option names via config,
so the sink never mutates the team schema.

Unlike the two-way NotionSource, this adapter never reads the board for merge
(`read()` returns []) and never PATCHes the target schema. `ensure_binding`
does ONE benign read to resolve the data_source_id (the page-create parent).
"""

import json
import subprocess

from sync_core import extract_tags, strip_tags

RICH_LIMIT = 2000  # Notion rich_text element content cap


def _run_ntn(args: list, data: dict | None = None):
    cmd = ["ntn", *args]
    stdin = None
    if data is not None:
        cmd += ["-d", "@-"]
        stdin = json.dumps(data)
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0:
        raise SystemExit(
            f"ntn {' '.join(args[:3])} failed: {r.stderr.strip()[:500]}")
    return json.loads(r.stdout) if r.stdout.strip() else {}


def _rich(text: str) -> list:
    chunks = [text[i:i + RICH_LIMIT] for i in range(0, len(text), RICH_LIMIT)]
    return [{"type": "text", "text": {"content": c}} for c in chunks[:100]] \
        or [{"type": "text", "text": {"content": ""}}]


def parse_map(spec: str | None) -> dict:
    """Parse a `k=v,k=v` config string into a dict (empty on blank)."""
    out = {}
    for pair in (spec or "").split(","):
        pair = pair.strip()
        if not pair:
            continue
        k, _, v = pair.partition("=")
        if not v:
            raise SystemExit(f"notion-taskboard: bad map entry {pair!r} "
                             "(want key=value)")
        out[k.strip()] = v.strip()
    return out


DEFAULT_PROPS = {"title": "Task", "status": "Status", "priority": "Priority",
                 "weight": "Weight", "owner": "Owner", "notes": "Notes"}
DEFAULT_TYPES = {"status": "status", "priority": "select", "weight": "number",
                 "owner": "people"}


class NotionTaskBoardSource:
    name = "notion-taskboard"
    create_only = True   # engine runs plan_create_only + the write-only path
    sync_fields = False

    def __init__(self, db=None, status_map=None, *, status_default=None,
                 priority_map=None, weight_map=None, owner=None,
                 props=None, types=None, skip_statuses=None,
                 binding=None, runner=_run_ntn):
        self.db = db
        self.status_map = status_map or {}
        self.status_default = status_default
        self.priority_map = priority_map or {}
        self.weight_map = weight_map or {}
        self.owner = owner
        self.props = {**DEFAULT_PROPS, **(props or {})}
        self.types = {**DEFAULT_TYPES, **(types or {})}
        self.skip_kw = set(skip_statuses) if skip_statuses else {"dropped"}
        self.binding = binding or {}
        self.runner = runner

    # --- binding (resolve the data source; no schema mutation) --------------

    def ensure_binding(self) -> dict:
        if self.binding.get("ds_id"):
            return self.binding
        if not self.db:
            raise SystemExit(
                "notion-taskboard: no target. Set notion_taskboard_db in "
                "[sync] (.kit.toml) or pass --notion-taskboard-db.")
        self.binding = {"db_id": self.db, "ds_id": self._resolve_ds(self.db)}
        return self.binding

    def _resolve_ds(self, db_id: str) -> str:
        resp = self.runner(["datasources", "resolve", db_id, "--json"])
        if isinstance(resp, list):
            return resp[0]["id"] if isinstance(resp[0], dict) else resp[0]
        for key in ("data_sources", "results"):
            if resp.get(key):
                first = resp[key][0]
                return first["id"] if isinstance(first, dict) else first
        return resp["id"]

    # --- read (write-only sink: nothing to read) ---------------------------

    def read(self) -> list:
        return []

    # --- property mapping --------------------------------------------------

    def _status_option(self, kw: str) -> str:
        name = self.status_map.get(kw, self.status_default)
        if name is None:
            raise SystemExit(
                f"notion-taskboard: no Status mapping for board state {kw!r}; "
                "add it to notion_taskboard_status_map or set "
                "notion_taskboard_status_default.")
        return name

    def _typed_value(self, kind: str, name: str) -> dict:
        t = self.types.get(kind)
        if t == "status":
            return {"status": {"name": name}}
        if t == "select":
            return {"select": {"name": name}}
        if t == "number":
            try:
                num = float(name)
            except ValueError:
                raise SystemExit(f"notion-taskboard: {kind} value {name!r} is "
                                 "not a number (types set number).")
            return {"number": int(num) if num.is_integer() else num}
        if t == "people":
            return {"people": [{"id": name}]}
        if t == "rich_text":
            return {"rich_text": _rich(name)}
        raise SystemExit(f"notion-taskboard: unknown prop type {t!r} for {kind}")

    def _tag_value(self, tags: list, mapping: dict) -> str | None:
        for tag in tags:
            if tag in mapping:
                return mapping[tag]
        return None

    def _page_props(self, title: str, body: str, kw: str) -> dict:
        out = {self.props["title"]: {"title": _rich(title)},
               self.props["status"]: self._typed_value(
                   "status", self._status_option(kw)),
               self.props["notes"]: {"rich_text": _rich(strip_tags(body))}}
        tags = extract_tags(body)
        prio = self._tag_value(tags, self.priority_map)
        if prio is not None:
            out[self.props["priority"]] = self._typed_value("priority", prio)
        weight = self._tag_value(tags, self.weight_map)
        if weight is not None:
            out[self.props["weight"]] = self._typed_value("weight", weight)
        if self.owner:
            out[self.props["owner"]] = self._typed_value("owner", self.owner)
        return out

    # --- apply (insert-only) -----------------------------------------------

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        b = self.ensure_binding()
        created = {}
        for bid, title, body, kw in plan.src_create:
            resp = self.runner(["api", "v1/pages", "-X", "POST"], {
                "parent": {"type": "data_source_id",
                           "data_source_id": b["ds_id"]},
                "properties": self._page_props(title, body, kw)})
            created[bid] = resp["id"]
        return created
