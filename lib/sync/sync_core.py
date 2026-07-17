"""Source-agnostic core of backlog-sync: board parsing/writing, the three-way
planner, snapshot state. Pure logic, no I/O. See docs/specs/SPEC-001.

Normalized spoke item: {rid, title, done, body, status} where status is a
board keyword when the adapter can state it definitively, else None (then
done=True reads as a `shipped` proposal). Identity: `ID-NNN` title prefix,
plus the per-spoke rid recorded in the snapshot.
"""

import re
from dataclasses import dataclass, field
from datetime import date

ACTIVE_STATUSES = {"queued", "claimed", "speccing", "validated", "executing"}
BOARD_STATES = ["queued", "claimed", "speccing", "validated", "executing",
                "shipped", "parked", "dropped"]
INBOX_HEADING = "### Reminders inbox"
CLOSED_HEADING = "## Recently closed"
TABLE_HEADER = "| ID | Item | Notes & source | Status |"
TABLE_RULE = "|---|---|---|---|"
TITLE_RE = re.compile(r"^(ID-\d+)\s*(?:[·:, -]\s*)?(.*)$")
CELL_SPLIT = re.compile(r"(?<!\\)\|")

# --- board parsing -----------------------------------------------------------


@dataclass
class Row:
    id: str
    item: str
    status_kw: str
    lineno: int
    notes: str = ""


def split_row(line: str):
    """Split a table row on unescaped pipes; None if not a 4-cell row."""
    parts = CELL_SPLIT.split(line.rstrip("\n"))
    if len(parts) != 6 or parts[0].strip() or parts[5].strip():
        return None
    return [p.strip() for p in parts[1:5]]


def parse_board(text: str) -> dict[str, Row]:
    rows: dict[str, Row] = {}
    for i, line in enumerate(text.splitlines()):
        if not line.startswith("| ID-"):
            continue
        cells = split_row(line)
        if not cells:
            continue
        rid, item, notes, status = cells
        if not re.fullmatch(r"ID-\d+", rid):
            continue
        kw = status.split()[0].lower() if status.split() else ""
        if rid in rows:
            continue  # first occurrence wins (dup rows are a board bug)
        rows[rid] = Row(rid, unescape(item), kw, i, unescape(notes))
    return rows


def next_id(text: str) -> int:
    nums = [int(m) for m in re.findall(r"\bID-(\d+)\b", text)]
    return max(nums, default=0) + 1


def escape(cell: str) -> str:
    return cell.replace("|", "\\|")


def unescape(cell: str) -> str:
    return cell.replace("\\|", "|")


def title_for(row_id: str, item: str) -> str:
    return f"{row_id} · {item}"


def parse_title(title: str):
    m = TITLE_RE.match(title.strip())
    if m and m.group(1):
        return m.group(1), m.group(2).strip()
    return None, title.strip()


def extract_tags(notes: str) -> list[str]:
    return sorted(set(re.findall(r"#([a-z0-9][a-z0-9-]*)", notes)))


def strip_tags(notes: str) -> str:
    """Remove #tag tokens (for spokes that carry tags in a real tag field)."""
    out = re.sub(r"(?:^|(?<=\s))#[a-z0-9][a-z0-9-]*", "", notes)
    return re.sub(r"[ \t]{2,}", " ", out).strip()


# --- plan (pure) -------------------------------------------------------------


@dataclass
class Plan:
    src_create: list = field(default_factory=list)     # [(bid, title, body, kw)]
    src_set_title: list = field(default_factory=list)  # [(rid, new_title)]
    src_set_body: list = field(default_factory=list)   # [(rid, body)]
    src_set_status: list = field(default_factory=list)  # [(rid, board_kw)]
    board_set_status: list = field(default_factory=list)  # [(bid, kw)]
    board_edit_item: list = field(default_factory=list)   # [(bid, item)]
    board_add: list = field(default_factory=list)      # [(rid, title, body, kw)]
    tombstone: list = field(default_factory=list)      # [bid]
    src_scope_exit: list = field(default_factory=list)  # [(bid, rid)] filtered out
    scope_reenter: list = field(default_factory=list)   # [(bid, rid)] back in scope
    conflicts: list = field(default_factory=list)      # [str] report lines
    notes: list = field(default_factory=list)          # [str] report lines

    def empty(self) -> bool:
        return not any((self.src_create, self.src_set_title, self.src_set_body,
                        self.src_set_status, self.board_set_status,
                        self.board_edit_item, self.board_add, self.tombstone,
                        self.src_scope_exit))


def in_scope(row, filt: dict | None) -> bool:
    """Down-filter: may this row appear on this app at all?"""
    if not filt:
        return True
    tags = set(extract_tags(row.notes))
    only = filt.get("only_tags")
    if only and not (tags & only):
        return False
    skip = filt.get("skip_tags")
    if skip and (tags & skip):
        return False
    return True


def intake_ok(body: str, filt: dict | None) -> bool:
    """Up-filter: may this foreign app item become a board row?"""
    mode = (filt or {}).get("intake", "all")
    if mode == "all":
        return True
    if mode == "none":
        return False
    if mode.startswith("tagged:"):
        return mode.split(":", 1)[1] in extract_tags(body)
    return True


def plan_sync(rows: dict, items: list, state: dict,
              sync_fields: bool = True, filt: dict | None = None) -> Plan:
    """Three-way merge between board rows, spoke items, and the snapshot.

    `filt` is this app's audience filter (SPEC-002 P1): {only_tags, skip_tags,
    intake}. Out-of-scope linked pairs are FROZEN (no status/field flow either
    way); the transition out emits a scope-exit (close on the app), the
    transition back re-syncs from the board.
    """
    p = Plan()
    smap = state.get("map", {})
    tombstones = set(state.get("tombstones", []))
    by_rid = {it["rid"]: it for it in items}

    # link spoke items to board ids: snapshot map first, then title prefix
    linked: dict[str, dict] = {}
    for bid, entry in smap.items():
        it = by_rid.get(entry.get("rid", ""))
        if it is not None:
            linked[bid] = it
    claimed_rids = {it["rid"] for it in linked.values()}
    for it in items:
        if it["rid"] in claimed_rids:
            continue
        bid, _ = parse_title(it["title"])
        if bid is None:
            continue
        if bid in linked:
            p.notes.append(f"duplicate item for {bid}: {it['title']!r} ignored")
            continue
        if bid in rows:
            linked[bid] = it
            claimed_rids.add(it["rid"])
        else:
            p.notes.append(f"orphan item (no board row): {it['title']!r}")

    for bid, row in rows.items():
        active = row.status_kw in ACTIVE_STATUSES
        it = linked.get(bid)
        row_in = in_scope(row, filt)
        if it is None:
            if not active:
                continue
            if bid in tombstones:
                continue  # user deleted the spoke item: stop mirroring
            entry = smap.get(bid)
            if entry is not None:
                if entry.get("scoped_out"):
                    continue  # we closed it on this app (filter); item may be gone
                p.tombstone.append(bid)
                p.notes.append(f"{bid}: item deleted on the spoke; stopped "
                               "mirroring (board row untouched)")
                continue
            if not row_in:
                continue  # filtered off this app: never created here
            p.src_create.append((bid, title_for(bid, row.item), row.notes,
                                 row.status_kw))
            continue

        snap = smap.get(bid)
        if snap is not None and snap.get("scoped_out"):
            if not row_in:
                continue  # frozen while out of scope
            # back in scope: re-open on the app and resync from the board
            p.scope_reenter.append((bid, it["rid"]))
            p.src_set_status.append((it["rid"], row.status_kw))
            snap = None  # adoption semantics: board wins on fields below

        src_kw = it.get("status") or ("shipped" if it["done"] else None)
        board_kw = row.status_kw
        eff_kw = board_kw  # board status after this sync round
        if snap is None:
            # fresh adoption (no snapshot): board wins, align the spoke
            done_mismatch = src_kw is None and it["done"] != (not active)
            if (src_kw and src_kw != board_kw) or done_mismatch:
                p.src_set_status.append((it["rid"], board_kw))
        else:
            snap_kw = snap.get("status", board_kw)
            board_changed = board_kw != snap_kw
            src_changed = src_kw is not None and src_kw != snap_kw
            if board_changed and src_changed and board_kw != src_kw:
                p.conflicts.append(f"{bid}: status changed on both sides; "
                                   f"board wins (board={board_kw} "
                                   f"spoke={src_kw})")
                p.src_set_status.append((it["rid"], board_kw))
            elif src_changed and src_kw != board_kw:
                p.board_set_status.append((bid, src_kw))
                eff_kw = src_kw
            elif board_changed:
                p.src_set_status.append((it["rid"], board_kw))

        if not row_in:
            # leaving scope: reverse-status resolved above, now close here
            if eff_kw in ACTIVE_STATUSES and not it["done"]:
                p.src_scope_exit.append((bid, it["rid"]))
            continue  # and no field flow while out of scope
        if not sync_fields:
            continue  # spoke cannot edit fields: freeze after create
        if eff_kw not in ACTIVE_STATUSES or it["done"]:
            continue
        snapd = snap or {}
        snap_item = snapd.get("title", row.item)
        _, it_title = parse_title(it["title"])
        board_t_changed = row.item != snap_item
        src_t_changed = it_title != snap_item
        want_title = title_for(bid, row.item)
        if board_t_changed and src_t_changed and row.item != it_title:
            p.conflicts.append(f"{bid}: both sides retitled; board wins "
                               f"(board={row.item!r} spoke={it_title!r})")
            p.src_set_title.append((it["rid"], want_title))
        elif src_t_changed and not board_t_changed:
            p.board_edit_item.append((bid, it_title))
        elif it["title"] != want_title:
            p.src_set_title.append((it["rid"], want_title))
        if snapd.get("notes") != row.notes:
            p.src_set_body.append((it["rid"], row.notes))

    # brand-new spoke items (no ID prefix, not done) -> new board rows
    existing_items = {r.item for r in rows.values()}
    for it in items:
        if it["rid"] in claimed_rids or it["done"]:
            continue
        bid, _ = parse_title(it["title"])
        if bid is not None or not it["title"].strip():
            continue
        if not intake_ok(it.get("body") or "", filt):
            p.notes.append(f"intake filtered: {it['title']!r} stays on the app")
            continue
        if it["title"].strip() in existing_items:
            # same title already on the board: likely a lost-state re-add
            p.notes.append(f"skipped add (title already on board): "
                           f"{it['title']!r}")
            continue
        kw = it.get("status") if it.get("status") in ACTIVE_STATUSES else "queued"
        p.board_add.append((it["rid"], it["title"].strip(),
                            (it.get("body") or "").strip(), kw))
    return p


# --- board apply -------------------------------------------------------------


def apply_board(text: str, plan: Plan) -> tuple[str, dict[str, str]]:
    """Apply board-side actions. Returns (new_text, {rid: assigned_board_id})."""
    lines = text.splitlines(keepends=True)
    rows = parse_board(text)

    def rewrite(bid: str, item: str | None = None, status_kw: str | None = None):
        row = rows[bid]
        line = lines[row.lineno]
        eol = "\n" if line.endswith("\n") else ""
        cells = split_row(line)
        if item is not None:
            cells[1] = escape(item)
        if status_kw is not None:
            rest = cells[3].split(maxsplit=1)
            trailing = f" {rest[1]}" if len(rest) > 1 else ""
            cells[3] = f"{status_kw}{trailing}"
        lines[row.lineno] = "| " + " | ".join(cells) + " |" + eol

    for bid, kw in plan.board_set_status:
        rewrite(bid, status_kw=kw)
    for bid, item in plan.board_edit_item:
        rewrite(bid, item=item)

    assigned: dict[str, str] = {}
    if plan.board_add:
        nid = next_id(text)
        new_rows = []
        for rid, title, body, kw in plan.board_add:
            bid = f"ID-{nid}"
            nid += 1
            assigned[rid] = bid
            title = " ".join(title.split())  # newlines would break the table row
            # #inbox quarantine (SPEC-002): intake-born rows stay off shared
            # apps (their filters skip #inbox) until first human triage
            provenance = f"added from spoke {date.today().isoformat()} #inbox"
            cell = " ; ".join(l.strip() for l in body.splitlines() if l.strip())
            notes = f"{cell} ; {provenance}" if cell else provenance
            new_rows.append(f"| {bid} | {escape(title)} | {escape(notes)} "
                            f"| {kw} |\n")
        lines = insert_inbox_rows(lines, new_rows)
    return "".join(lines), assigned


def insert_inbox_rows(lines: list[str], new_rows: list[str]) -> list[str]:
    stripped = [l.rstrip("\n") for l in lines]
    if INBOX_HEADING in stripped:
        i = stripped.index(INBOX_HEADING) + 1
        while i < len(lines) and (stripped[i].startswith("|") or not stripped[i].strip()):
            i += 1
        # backtrack over trailing blank lines so rows join the table
        while i > 0 and not stripped[i - 1].strip():
            i -= 1
        return lines[:i] + new_rows + lines[i:]
    section = [f"{INBOX_HEADING}\n", "\n", TABLE_HEADER + "\n", TABLE_RULE + "\n",
               *new_rows, "\n"]
    if CLOSED_HEADING in stripped:
        i = stripped.index(CLOSED_HEADING)
        return lines[:i] + section + lines[i:]
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    return lines + ["\n"] + section


# --- state -------------------------------------------------------------------


def build_state(rows: dict, items: list, plan: Plan, created: dict,
                assigned: dict, old_state: dict) -> dict:
    """Snapshot the post-sync linkage for the next three-way merge.

    `rows` is the POST-apply board. Linked pairs stay in the map even when
    inactive (a spoke item in a terminal column can be reopened later).
    """
    by_rid = {it["rid"]: it for it in items}
    tombstones = sorted(set(old_state.get("tombstones", [])) | set(plan.tombstone))
    m: dict[str, dict] = {}

    def entry_for(bid: str, rid: str) -> dict:
        row = rows[bid]
        return {"rid": rid, "title": row.item, "notes": row.notes,
                "status": row.status_kw}

    for bid, entry in old_state.get("map", {}).items():
        rid = entry.get("rid", "")
        if bid in plan.tombstone:
            continue
        if rid in by_rid and bid in rows:
            m[bid] = entry_for(bid, rid)
    for bid, _t, _b, _kw in plan.src_create:
        if bid in created:
            m[bid] = entry_for(bid, created[bid])
    for rid, _t, _b, _kw in plan.board_add:
        if rid in assigned and assigned[rid] in rows:
            m[assigned[rid]] = entry_for(assigned[rid], rid)
    # adopt prefix-matched items that weren't in the old map
    known_rids = {e["rid"] for e in m.values()}
    for it in items:
        if it["rid"] in known_rids:
            continue
        bid, _ = parse_title(it["title"])
        if bid and bid in rows and bid not in m:
            m[bid] = entry_for(bid, it["rid"])
    # scope flags: set on exit, cleared on re-entry, carried while frozen
    exited = {bid for bid, _ in plan.src_scope_exit}
    reentered = {bid for bid, _ in plan.scope_reenter}
    old_map = old_state.get("map", {})
    for bid, e in m.items():
        was_out = old_map.get(bid, {}).get("scoped_out", False)
        if bid in exited or (was_out and bid not in reentered):
            e["scoped_out"] = True
    out = {"map": m, "tombstones": tombstones}
    if "binding" in old_state:
        out["binding"] = old_state["binding"]
    return out


# --- reporting ---------------------------------------------------------------


def describe(plan: Plan, assigned: dict | None = None) -> str:
    out = []
    for bid, t, _b, _kw in plan.src_create:
        out.append(f"  + spoke     {t}")
    for rid, kw in plan.src_set_status:
        out.append(f"  ~ spoke     {rid} -> {kw}")
    for rid, t in plan.src_set_title:
        out.append(f"  ~ spoke     {rid} title -> {t!r}")
    for rid, _b in plan.src_set_body:
        out.append(f"  ~ spoke     {rid} notes updated from board")
    for bid, kw in plan.board_set_status:
        out.append(f"  ✓ board     {bid} -> {kw}")
    for bid, item in plan.board_edit_item:
        out.append(f"  ~ board     {bid} item -> {item!r}")
    for rid, title, _body, kw in plan.board_add:
        bid = (assigned or {}).get(rid, "ID-?")
        out.append(f"  + board     {bid} ({kw}) <- {title!r}")
    for bid in plan.tombstone:
        out.append(f"  ⏸ tombstone {bid}")
    for bid, _rid in plan.src_scope_exit:
        out.append(f"  ⤫ app       {bid} leaves this app's scope (filtered)")
    for bid, _rid in plan.scope_reenter:
        out.append(f"  ↩ app       {bid} back in scope, re-synced from board")
    for c in plan.conflicts:
        out.append(f"  ! conflict  {c}")
    for n in plan.notes:
        out.append(f"  · note      {n}")
    return "\n".join(out) if out else "  (nothing to do)"
