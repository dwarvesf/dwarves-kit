"""Notion spoke: drives the `ntn` CLI (keychain auth, Han's Notion rule).

Bootstrap covers both cases:
  - no board: create a database under --notion-parent with Name / Status
    (select, all board states) / Tags (multi_select) / Notes (rich_text);
  - has board: bind to --notion-db, discover the title prop + a Status
    select/status prop, add missing Notes/Tags/Status props to the schema.

Select-type Status is lossless (page writes auto-create unseen options).
Status-type Status cannot gain options via the API, so it maps by group:
Complete-group reads as `shipped`; writes pick the exact option when it
exists, else the group default. The binding persists in the snapshot file.
"""

import json
import subprocess

from sync_core import (ACTIVE_STATUSES, BOARD_STATES, extract_tags,
                       strip_tags, title_for)

STATE_COLORS = {"queued": "gray", "claimed": "yellow", "speccing": "orange",
                "validated": "purple", "executing": "blue", "shipped": "green",
                "parked": "brown", "dropped": "red"}
RICH_LIMIT = 2000  # Notion rich_text element content cap, in UTF-16 code units


def _run_ntn(args: list, data: dict | None = None):
    cmd = ["ntn", *args]
    stdin = None
    if data is not None:
        cmd += ["-d", "@-"]
        stdin = json.dumps(data)
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0:
        raise SystemExit(f"ntn {' '.join(args[:3])} failed: {r.stderr.strip()[:500]}")
    return json.loads(r.stdout) if r.stdout.strip() else {}


def _rich(text: str) -> list:
    # Notion measures the cap in UTF-16 code units, not codepoints: an astral
    # char (emoji) counts as 2, so len()-based 2000-char slices can weigh 2001
    # and 400 the whole request (validation_error, board-sync rc=1 every run).
    chunks, buf, units = [], [], 0
    for ch in text:
        u = 2 if ord(ch) > 0xFFFF else 1
        if units + u > RICH_LIMIT:
            chunks.append("".join(buf))
            buf, units = [], 0
        buf.append(ch)
        units += u
    if buf:
        chunks.append("".join(buf))
    return [{"type": "text", "text": {"content": c}} for c in chunks[:100]] \
        or [{"type": "text", "text": {"content": ""}}]


def _plain(rich: list) -> str:
    return "".join(t.get("plain_text", t.get("text", {}).get("content", ""))
                   for t in rich or [])


class NotionSource:
    name = "notion"
    sync_fields = True

    def __init__(self, binding: dict | None = None, db: str | None = None,
                 parent: str | None = None, title: str = "ops-toolkit Backlog",
                 runner=_run_ntn):
        self.runner = runner
        self.db = db
        self.parent = parent
        self.board_title = title
        self.binding = binding or {}

    # --- bootstrap / binding -------------------------------------------------

    def ensure_binding(self) -> dict:
        if self.binding.get("ds_id"):
            return self.binding
        if self.db:
            self.binding = self._bind_existing(self.db)
        elif self.parent:
            self.binding = self._create_board(self.parent)
        else:
            raise SystemExit(
                "notion: no binding yet. Pass --notion-db <database_id> to "
                "bind an existing board, or --notion-parent <page_id> to "
                "create one.")
        return self.binding

    def _create_board(self, parent_page: str) -> dict:
        resp = self.runner(["api", "v1/databases", "-X", "POST"], {
            "parent": {"type": "page_id", "page_id": parent_page},
            "title": [{"type": "text", "text": {"content": self.board_title}}],
            # 2025-09+ API: schema lives on the data source, not the database
            "initial_data_source": {"properties": {
                "Name": {"title": {}},
                "Status": {"select": {"options": [
                    {"name": s, "color": STATE_COLORS[s]} for s in BOARD_STATES]}},
                "Tags": {"multi_select": {}},
                "Notes": {"rich_text": {}},
            }},
        })
        db_id = resp["id"]
        ds = resp.get("data_sources") or []
        ds_id = ds[0]["id"] if ds else self._resolve_ds(db_id)
        return {"db_id": db_id, "ds_id": ds_id, "created": True,
                "props": {"title": "Name", "status": "Status",
                          "status_type": "select", "notes": "Notes",
                          "tags": "Tags"}}

    def _resolve_ds(self, db_id: str) -> str:
        resp = self.runner(["datasources", "resolve", db_id, "--json"])
        if isinstance(resp, list):
            return resp[0]["id"] if isinstance(resp[0], dict) else resp[0]
        for key in ("data_sources", "results"):
            if resp.get(key):
                first = resp[key][0]
                return first["id"] if isinstance(first, dict) else first
        return resp["id"]

    def _bind_existing(self, db_id: str) -> dict:
        ds_id = self._resolve_ds(db_id)
        schema = self.runner(["api", f"v1/data_sources/{ds_id}"])
        props = schema.get("properties", {})
        title_prop = next((n for n, p in props.items() if p.get("type") == "title"),
                          "Name")
        status_prop, status_type = None, None
        for n, p in props.items():
            if p.get("type") in ("select", "status") and n.lower() == "status":
                status_prop, status_type = n, p["type"]
                break
        if status_prop is None:  # any select/status prop using board keywords
            for n, p in props.items():
                if p.get("type") in ("select", "status"):
                    names = {o["name"] for o in p[p["type"]].get("options", [])}
                    if names & set(BOARD_STATES):
                        status_prop, status_type = n, p["type"]
                        break
        notes_prop = next((n for n, p in props.items()
                           if p.get("type") == "rich_text"
                           and n.lower() == "notes"), None)
        tags_prop = next((n for n, p in props.items()
                          if p.get("type") == "multi_select"
                          and n.lower() == "tags"), None)

        additions = {}
        if status_prop is None:
            status_prop, status_type = "Status", "select"
            additions["Status"] = {"select": {"options": [
                {"name": s, "color": STATE_COLORS[s]} for s in BOARD_STATES]}}
        if notes_prop is None:
            notes_prop = "Notes"
            additions["Notes"] = {"rich_text": {}}
        if tags_prop is None:
            tags_prop = "Tags"
            additions["Tags"] = {"multi_select": {}}
        if additions:
            self.runner(["api", f"v1/data_sources/{ds_id}", "-X", "PATCH"],
                        {"properties": additions})

        binding = {"db_id": db_id, "ds_id": ds_id, "created": False,
                   "props": {"title": title_prop, "status": status_prop,
                             "status_type": status_type, "notes": notes_prop,
                             "tags": tags_prop}}
        if status_type == "status":
            binding["status_map"] = self._status_group_map(props[status_prop])
        return binding

    @staticmethod
    def _status_group_map(prop: dict) -> dict:
        """For status-type props: option name -> group name, + group defaults."""
        options = {o["id"]: o["name"] for o in prop["status"].get("options", [])}
        by_option, defaults = {}, {}
        for g in prop["status"].get("groups", []):
            for oid in g.get("option_ids", []):
                if oid in options:
                    by_option[options[oid]] = g["name"]
                    defaults.setdefault(g["name"], options[oid])
        return {"groups": by_option, "defaults": defaults,
                "options": sorted(options.values())}

    # --- read -----------------------------------------------------------------

    def read(self) -> list[dict]:
        b = self.ensure_binding()
        items, cursor = [], None
        while True:
            body = {"page_size": 100}
            if cursor:
                body["start_cursor"] = cursor
            resp = self.runner(
                ["api", f"v1/data_sources/{b['ds_id']}/query", "-X", "POST"],
                body)
            for page in resp.get("results", []):
                if page.get("archived") or page.get("in_trash"):
                    continue
                items.append(self._item(page, b))
            if not resp.get("has_more"):
                return items
            cursor = resp.get("next_cursor")

    def _item(self, page: dict, b: dict) -> dict:
        props = page.get("properties", {})
        p = b["props"]
        title = _plain(props.get(p["title"], {}).get("title", []))
        raw = (props.get(p["status"], {}) or {}).get(b["props"]["status_type"])
        opt = (raw or {}).get("name")
        kw, done = None, False
        if opt in BOARD_STATES:
            kw = opt
            done = kw not in ACTIVE_STATUSES
        elif opt and p["status_type"] == "status":
            group = b.get("status_map", {}).get("groups", {}).get(opt)
            if group == "Complete":
                kw, done = "shipped", True
        body = _plain((props.get(p["notes"], {}) or {}).get("rich_text", [])) \
            if p.get("notes") else ""
        if p.get("tags"):
            # fold field tags back as #tags so an inbox capture keeps them
            tags = [t["name"] for t in
                    (props.get(p["tags"], {}) or {}).get("multi_select", [])]
            missing = [t for t in tags if f"#{t}" not in body]
            if missing:
                body = (body + " " + " ".join(f"#{t}" for t in missing)).strip()
        return {"rid": page["id"], "title": title, "done": done,
                "body": body, "status": kw}

    # --- write ----------------------------------------------------------------

    def _status_value(self, kw: str, b: dict) -> dict:
        p = b["props"]
        if p["status_type"] == "select":
            return {"select": {"name": kw}}  # unseen options auto-create
        sm = b.get("status_map", {})
        if kw in sm.get("options", []):
            return {"status": {"name": kw}}
        group = "Complete" if kw not in ACTIVE_STATUSES else "To-do"
        name = sm.get("defaults", {}).get(group)
        if name is None:
            raise SystemExit(f"notion: status prop has no {group} group option")
        return {"status": {"name": name}}

    def _field_props(self, b: dict, title=None, body=None, kw=None) -> dict:
        p = b["props"]
        out = {}
        if title is not None:
            out[p["title"]] = {"title": _rich(title)}
        if body is not None:
            # tags belong in the Tags field, not the notes text
            if p.get("tags"):
                out[p["tags"]] = {"multi_select":
                                  [{"name": t} for t in extract_tags(body)[:20]]}
                out[p["notes"]] = {"rich_text": _rich(strip_tags(body))}
            else:
                out[p["notes"]] = {"rich_text": _rich(body)}
        if kw is not None:
            out[p["status"]] = self._status_value(kw, b)
        return out

    def apply(self, plan, assigned: dict, rows_after: dict) -> dict:
        b = self.ensure_binding()
        created = {}
        for bid, title, body, kw in plan.src_create:
            resp = self.runner(["api", "v1/pages", "-X", "POST"], {
                "parent": {"type": "data_source_id",
                           "data_source_id": b["ds_id"]},
                "properties": self._field_props(b, title=title, body=body,
                                                kw=kw)})
            created[bid] = resp["id"]
        for rid, title in plan.src_set_title:
            self.runner(["api", f"v1/pages/{rid}", "-X", "PATCH"],
                        {"properties": self._field_props(b, title=title)})
        for rid, body in plan.src_set_body:
            self.runner(["api", f"v1/pages/{rid}", "-X", "PATCH"],
                        {"properties": self._field_props(b, body=body)})
        for rid, kw in plan.src_set_status:
            self.runner(["api", f"v1/pages/{rid}", "-X", "PATCH"],
                        {"properties": self._field_props(b, kw=kw)})
        for _bid, rid in plan.src_scope_exit:
            # filtered off this app: trash the page (recreated fresh if the
            # row ever re-enters scope)
            self.runner(["api", f"v1/pages/{rid}", "-X", "PATCH"],
                        {"in_trash": True})
        for rid, _t, _b2, _kw in plan.board_add:
            bid = assigned.get(rid)
            if bid and bid in rows_after:
                row = rows_after[bid]
                self.runner(["api", f"v1/pages/{rid}", "-X", "PATCH"],
                            {"properties": self._field_props(
                                b, title=title_for(bid, row.item),
                                body=row.notes, kw=row.status_kw)})
        return created
