"""Notion Task Board sink: ONE-WAY, insert-only push of board rows to a
foreign, team-OWNED Notion board. Drives the `ntn` CLI (keychain auth, Han's
Notion rule). See docs/specs/SPEC-003-oneway-create-push.md (ID-138).

Insert-only by contract: the team owns each card after it lands, so the sink
sets fields on page-create and never touches them again (the local sync-state
map is the identity index; a bid already in the map is never re-pushed). Status
/ Priority / Weight are mapped to the team board's OWN option names via config.

Never mutates the team schema: `ensure_binding` resolves the data source
(a benign read), `preflight` reads the schema once to (a) learn each prop's
type and (b) validate that every configured option name already exists on the
board, so a typo'd map value is a hard error instead of a silently
auto-created select option. `read()` returns [] (the sink is write-only).
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
# Fallback types used only when the schema has not been read (e.g. unit tests
# that inject a binding directly); a real run derives types from the schema.
DEFAULT_TYPES = {"status": "status", "priority": "select", "weight": "number",
                 "owner": "people"}
OPTION_TYPES = ("select", "status")


class NotionTaskBoardSource:
    name = "notion-taskboard"
    create_only = True   # engine runs plan_create_only + the write-only path
    sync_fields = False

    def __init__(self, db=None, status_map=None, *, status_default=None,
                 priority_map=None, weight_map=None, owner=None,
                 props=None, types=None, binding=None, runner=_run_ntn):
        self.db = db
        self.status_map = status_map or {}
        self.status_default = status_default
        self.priority_map = priority_map or {}
        self.weight_map = weight_map or {}
        self.owner = owner
        self.props = {**DEFAULT_PROPS, **(props or {})}
        self.types = {**(types or {})}          # explicit overrides only
        self.skip_kw = {"dropped"}
        self.binding = binding or {}
        self.runner = runner
        self._schema_types: dict = {}
        self._prop_opts: dict = {}
        self._schema_loaded = False

    # --- binding + schema (reads only; never a schema PATCH) ----------------

    def ensure_binding(self) -> dict:
        if self.binding.get("ds_id") and self.binding.get("db_id") == self.db:
            return self.binding   # cached (possibly restored from state)
        if not self.db:
            raise SystemExit(
                "notion-taskboard: no target. Set notion_taskboard_db in "
                "[sync] (.kit.toml) or pass --notion-taskboard-db.")
        # a stale cached binding for a different db is discarded
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

    def _load_schema(self) -> None:
        if self._schema_loaded:
            return
        b = self.ensure_binding()
        schema = self.runner(["api", f"v1/data_sources/{b['ds_id']}"])
        props = schema.get("properties", {})
        for kind, pname in self.props.items():
            p = props.get(pname)
            if p is None:
                continue   # optional props (owner/priority/weight) may be absent
            ptype = p.get("type")
            self._schema_types[kind] = ptype
            if ptype in OPTION_TYPES:
                self._prop_opts[pname] = {
                    o["name"] for o in p.get(ptype, {}).get("options", [])}
        self._schema_loaded = True

    def _eff_type(self, kind: str) -> str:
        return (self.types.get(kind) or self._schema_types.get(kind)
                or DEFAULT_TYPES.get(kind))

    # --- read (write-only sink: nothing to read) ---------------------------

    def read(self) -> list:
        return []

    # --- validation (preflight, before any write) --------------------------

    def preflight(self, plan) -> None:
        self._load_schema()
        for bid, _title, body, kw in plan.src_create:
            self._validate_row(bid, body, kw)

    def _validate_row(self, bid: str, body: str, kw: str) -> None:
        self._check_option(bid, "status", self._status_option(kw))
        tags = extract_tags(body)
        prio = self._tag_value(tags, self.priority_map)
        if prio is not None:
            self._check_option(bid, "priority", prio)
        weight = self._tag_value(tags, self.weight_map)
        if weight is not None:
            if self._eff_type("weight") == "number":
                self._number(weight, "weight")
            else:
                self._check_option(bid, "weight", weight)

    def _check_option(self, bid: str, kind: str, name: str) -> None:
        opts = self._prop_opts.get(self.props[kind])
        if opts is not None and name not in opts:
            raise SystemExit(
                f"notion-taskboard: {bid}: {kind} value {name!r} is not an "
                f"option of the {self.props[kind]!r} prop {sorted(opts)}; fix "
                "the map or add the option on the board (a create must never "
                "auto-create an option on a team board).")

    # --- property mapping --------------------------------------------------

    def _status_option(self, kw: str) -> str:
        name = self.status_map.get(kw, self.status_default)
        if name is None:
            raise SystemExit(
                f"notion-taskboard: no Status mapping for board state {kw!r}; "
                "add it to notion_taskboard_status_map or set "
                "notion_taskboard_status_default.")
        return name

    @staticmethod
    def _number(value: str, kind: str):
        try:
            num = float(value)
        except ValueError:
            raise SystemExit(f"notion-taskboard: {kind} value {value!r} is not "
                             "a number (types set number).")
        return int(num) if num.is_integer() else num

    def _typed_value(self, kind: str, name: str) -> dict:
        t = self._eff_type(kind)
        if t == "status":
            return {"status": {"name": name}}
        if t == "select":
            return {"select": {"name": name}}
        if t == "number":
            return {"number": self._number(name, kind)}
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

    # --- apply (insert-only; checkpoints each create via on_created) --------

    def apply(self, plan, assigned: dict, rows_after: dict,
              on_created=None) -> dict:
        b = self.ensure_binding()
        created = {}
        for bid, title, body, kw in plan.src_create:
            resp = self.runner(["api", "v1/pages", "-X", "POST"], {
                "parent": {"type": "data_source_id",
                           "data_source_id": b["ds_id"]},
                "properties": self._page_props(title, body, kw)})
            rid = resp["id"]
            created[bid] = rid
            if on_created is not None:
                on_created(bid, rid)   # persist state before the next POST
        return created
