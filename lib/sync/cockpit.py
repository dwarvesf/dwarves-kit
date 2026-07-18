"""Cockpit channel: multi-source extract + keyed-diff planner for the sync mesh.

This is the P2 port of the legacy `board mirror` bridge (lib/board/board-mirror.sh,
SPEC-147) into the sync module, implementing kit board row ID-290 and the
SPEC-002 sync-mesh cockpit profile. It ports the two DETERMINISTIC legs of the
bridge:

  EXTRACT   N opted-in repos (a boards.txt registry) -> normalized, ORIGIN-KEYED
            items. A BACKLOG.md row keys as `<repo>:ID-NNN`; an active mega-goal
            (`_meta/megagoals/<slug>/ROADMAP.md`) keys as `megagoals:<repo>/<slug>`.
            Origin identity is what lets many repos pool onto one cockpit board
            without ID collisions (SPEC-002 dim 4 / case 13), the gap bare-ID
            keying leaves open once profiles stop being single-repo.
  TRANSFORM a keyed diff between the current extract and the prior snapshot,
            matched on `origin` + `row_hash`: unseen origin -> CREATE, same hash
            -> UNCHANGED (the idempotence guarantee), changed hash -> CHANGE, a
            prior origin gone from the extract -> COMPLETE. The board always
            wins (row_hash is content from the git-owned board), which IS the
            "row_hash git-wins conflict rule" ID-290 said the port must carry.

Deferred to a later slice (still on the legacy engine, which stays runnable):
  * the LOAD leg (applying a plan to a live Hermes kanban via the CLI): needs a
    real Hermes binary, cannot run in CI, and is left on board-mirror.sh's
    proven `apply-plan`;
  * two-way status writeback (SPEC-149 reverse-status + HELD-PR): left on
    board-writeback.sh;
  * retiring `mirror`/`status`/`writeback` to thin aliases and migrating the
    snapshot into the per-app sync state shape.
See docs/specs/SPEC-002-sync-mesh.md "P2" and the module docstring in
lib/board/board-mirror.sh for the legacy engine this ports.

Pure logic + stdlib only; no network, no Hermes, no I/O beyond the CLI reading
files. The row_hash is byte-identical to the bash `_row_hash` (sha256 over the
0x1f-joined fields) so a future cutover can adopt the legacy NDJSON snapshot
without re-hashing (SPEC-002 case 17: adopt-by-origin).
"""

import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_core import parse_board  # noqa: E402

# State mapping: git board keyword -> the Hermes native state the bridge can
# durably reach. Empty string = "not bridged" (shipped/dropped/unrecognized are
# excluded from the extract entirely). The reachable set is {triage, ready,
# blocked, done}; `todo`/`running` have no CLI-only durable path (see the
# board-mirror.sh header's Hermes-CLI-reality note), so `claimed`/`speccing`/
# `executing` honestly fall back to `ready`. This map is the second asset ID-290
# said the port must carry over.
TARGET_NATIVE = {
    "queued": "triage",
    "claimed": "ready",
    "speccing": "ready",
    "validated": "ready",
    "executing": "ready",
    "parked": "blocked",
}

US = "\x1f"  # unit separator: cannot appear in a markdown cell, so no field's
#              own text can forge a hash collision by concatenation ambiguity.
_ROUTING_RE = re.compile(r"#queue\{[^}]*\}")


def target_native(status_kw: str) -> str:
    """The reachable Hermes native state for a git board keyword, or ""."""
    return TARGET_NATIVE.get(status_kw, "")


def strip_routing_tags(text: str) -> str:
    """Remove the SG-04 `#queue{...}` routing token before content is hashed or
    shown, so the hash keys off human content, not the machine tag (mirrors
    board-mirror.sh's `_strip_routing_tags`; ordinary #tags are kept)."""
    out = _ROUTING_RE.sub("", text)
    return re.sub(r"\s{2,}", " ", out).strip()


def row_hash(repo: str, id_: str, item: str, notes: str, status: str) -> str:
    """sha256 hex over the 0x1f-joined content fields. Byte-identical to the
    bash `_row_hash` (`printf '%s\\x1f...'`, no trailing newline)."""
    joined = US.join((repo, id_, item, notes, status))
    return hashlib.sha256(joined.encode("utf-8")).hexdigest()


# --- extract -----------------------------------------------------------------


@dataclass
class Item:
    """A normalized, origin-keyed extract row (the bridge's TSV, structured)."""
    origin: str      # `<repo>:ID-NNN` or `megagoals:<repo>/<slug>`
    repo: str        # source repo name, or the literal "megagoals"
    id: str          # `ID-NNN`, or `<repo>/<slug>` for a mega
    item: str        # card title (routing-token stripped)
    notes: str       # card body / notes
    status: str      # git board keyword, or "active" for a mega
    target: str      # reachable Hermes native state
    hash: str        # row_hash over the content fields


def extract_rows(backlog_text: str, repo: str) -> list[Item]:
    """One Item per bridgeable BACKLOG.md row. Reuses the sync engine's own
    `parse_board` (the canonical 4-col `| ID | Item | Notes & source | Status |`
    shape); shipped/dropped/unrecognized rows are excluded (empty target)."""
    out: list[Item] = []
    for rid, row in parse_board(backlog_text).items():
        target = target_native(row.status_kw)
        if not target:
            continue  # shipped/dropped/unrecognized: not bridged
        item = strip_routing_tags(row.item)
        notes = strip_routing_tags(row.notes)
        out.append(Item(
            origin=f"{repo}:{rid}", repo=repo, id=rid, item=item, notes=notes,
            status=row.status_kw, target=target,
            hash=row_hash(repo, rid, item, notes, row.status_kw)))
    return out


def _mega_from_roadmap(text: str, slug: str) -> Item | None:
    """One Item for an ACTIVE mega-goal, or None if the roadmap is inactive
    (zero checkboxes = unrecognized shape, or 100% checked = fully shipped;
    a finished mega heals through the COMPLETE path like any vanished row).
    Ports board-mirror.sh's `extract_megas` convention."""
    title = ""
    for line in text.splitlines():
        m = re.match(r"^# Mega-goal:[ \t]*(.*)$", line)
        if m:
            title = m.group(1).strip()
            break
    if not title:
        title = slug.rsplit("/", 1)[-1]  # bare slug, not the qualified <repo>/<slug>
    checked = len(re.findall(r"(?m)^- \[[xX]\]", text))
    unchecked = len(re.findall(r"(?m)^- \[ \]", text))
    total = checked + unchecked
    if total == 0 or unchecked == 0:
        return None
    held = re.search(r"held", text, re.IGNORECASE) is not None
    notes = f"progress {checked}/{total}"
    if held:
        notes += " | held-PR flag set"
    title = strip_routing_tags(title)
    return Item(
        origin=f"megagoals:{slug}", repo="megagoals", id=slug, item=title,
        notes=notes, status="active", target="ready",
        hash=row_hash("megagoals", slug, title, notes, "active"))


def extract_megas(roadmaps: list[tuple[str, str]]) -> list[Item]:
    """Active-mega Items from [(qualified_slug, roadmap_text), ...] where the
    qualified slug is `<repo>/<slug>` (so the origin is `megagoals:<repo>/<slug>`)."""
    out: list[Item] = []
    for slug, text in roadmaps:
        it = _mega_from_roadmap(text, slug)
        if it is not None:
            out.append(it)
    return out


# --- registry ----------------------------------------------------------------


@dataclass
class RegRow:
    name: str
    path: str
    bridge: str


def parse_registry(text: str) -> list[RegRow]:
    """Parse a boards.txt registry (`name  path  bridge`, whitespace-separated,
    `#` comments, `~`-home expansion). Only `bridge == "on"` rows are returned,
    the same opt-in gate board-mirror.sh applies."""
    out: list[RegRow] = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = s.split()
        if len(parts) < 3:
            continue  # rows without the 3rd bridge column are never opted in
        name, path, bridge = parts[0], parts[1], parts[2]
        if bridge != "on":
            continue
        if path.startswith("~/") or path == "~":
            path = str(Path.home()) + path[1:]
        out.append(RegRow(name, path, bridge))
    return out


# --- snapshot ----------------------------------------------------------------


@dataclass
class SnapEntry:
    origin: str
    hermes_id: str
    row_hash: str
    hermes_status: str
    board: str
    seen_at: str


def read_snapshot(ndjson_text: str) -> dict[str, SnapEntry]:
    """Read the bridge NDJSON snapshot (one JSON object per line) into an
    origin-keyed map. Format-compatible with board-mirror.sh's snapshot, so a
    future cutover adopts the legacy file as-is (SPEC-002 case 17). A malformed
    line is skipped, not fatal."""
    out: dict[str, SnapEntry] = {}
    for line in ndjson_text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            o = json.loads(line)
        except json.JSONDecodeError:
            continue
        origin = o.get("origin")
        if not origin:
            continue
        out[origin] = SnapEntry(
            origin=origin, hermes_id=o.get("hermes_id", ""),
            row_hash=o.get("row_hash", ""), hermes_status=o.get("hermes_status", ""),
            board=o.get("board", ""), seen_at=o.get("seen_at", ""))
    return out


# --- plan (the keyed diff) ---------------------------------------------------


@dataclass
class Plan:
    create: list = field(default_factory=list)    # [Item]
    change: list = field(default_factory=list)     # [(Item, SnapEntry)]
    complete: list = field(default_factory=list)   # [SnapEntry]
    unchanged: int = 0

    def total_ops(self) -> int:
        return len(self.create) + len(self.change) + len(self.complete)

    def empty(self) -> bool:
        return self.total_ops() == 0


def plan_cockpit(current: list[Item], snapshot: dict[str, SnapEntry]) -> Plan:
    """Keyed diff between the current extract and the prior snapshot, matched on
    `origin` + `row_hash`. The board always wins (the hash is git-owned content),
    which is the row_hash git-wins conflict rule ID-290 requires. Mirror-out
    only: the snapshot's Hermes-side fields feed CHANGE/COMPLETE targeting; no
    reverse-status path here (that is the deferred writeback leg).

    Ports board-mirror.sh's `cmd_plan` awk diff, including its two edge rules:
    a same-hash origin is UNCHANGED (no-op), and a prior origin absent from the
    current extract is COMPLETE only when its recorded status is not already
    `done` (a done card stays done; it is dropped from the live-state snapshot,
    so a later reappearance is a fresh CREATE, never a resurrection)."""
    p = Plan()
    seen: set[str] = set()
    for it in current:
        seen.add(it.origin)
        prior = snapshot.get(it.origin)
        if prior is None:
            p.create.append(it)
        elif prior.row_hash == it.hash:
            p.unchanged += 1
        else:
            p.change.append((it, prior))
    for origin, prior in snapshot.items():
        if origin not in seen and prior.hermes_status != "done":
            p.complete.append(prior)
    return p


def board_for(it: Item, mega_board: str = "megagoals", board_prefix: str = "") -> str:
    """The cockpit board name a CREATE/CHANGE op targets (COMPLETE ops keep the
    snapshot's own recorded board). Ports the board.sh cmd_plan mapping."""
    if it.repo == "megagoals":
        return mega_board
    return f"{board_prefix}{it.repo}"


# --- driver + CLI ------------------------------------------------------------


def extract_from_registry(registry_text: str,
                          repo_root_for=None) -> list[Item]:
    """Full multi-source extract from a registry: every opted-in repo's
    BACKLOG.md rows plus its active mega-goals. `repo_root_for(path)` maps a
    BACKLOG.md path to the repo root that holds `_meta/megagoals/` (defaults to
    two levels up: `_meta/BACKLOG.md` -> repo root)."""
    def default_root(path: Path) -> Path:
        # <root>/_meta/BACKLOG.md -> <root>
        return path.parent.parent if path.parent.name == "_meta" else path.parent

    root_for = repo_root_for or default_root
    out: list[Item] = []
    for reg in parse_registry(registry_text):
        path = Path(reg.path)
        if not path.is_file():
            print(f"cockpit: skip repo {reg.name!r}: BACKLOG.md missing at "
                  f"{path}", file=sys.stderr)
            continue
        out.extend(extract_rows(path.read_text(), reg.name))
        root = Path(root_for(path))
        mg_root = root / "_meta" / "megagoals"
        if mg_root.is_dir():
            roadmaps: list[tuple[str, str]] = []
            for d in sorted(mg_root.iterdir()):
                rf = d / "ROADMAP.md"
                if rf.is_file():
                    roadmaps.append((f"{reg.name}/{d.name}", rf.read_text()))
            out.extend(extract_megas(roadmaps))
    return out


def describe_plan(plan: Plan, mega_board: str = "megagoals",
                  board_prefix: str = "") -> str:
    lines = []
    for it in plan.create:
        lines.append(f"  + create   {it.origin} -> {board_for(it, mega_board, board_prefix)} ({it.target})")
    for it, prior in plan.change:
        lines.append(f"  ~ change   {it.origin} (was {prior.hermes_id or '?'}) content updated")
    for prior in plan.complete:
        lines.append(f"  x complete {prior.origin} -> {prior.board} (origin removed)")
    head = (f"cockpit: plan {plan.total_ops()} ops "
            f"({len(plan.create)} create, {len(plan.change)} change, "
            f"{len(plan.complete)} complete), {plan.unchanged} unchanged")
    return head + ("\n" + "\n".join(lines) if lines else "")


def plan_to_json(plan: Plan, mega_board: str = "megagoals",
                 board_prefix: str = "") -> str:
    ops = []
    for it in plan.create:
        ops.append({"op": "create", "origin": it.origin, "repo": it.repo,
                    "id": it.id, "item": it.item, "notes": it.notes,
                    "status": it.status, "target_native": it.target,
                    "row_hash": it.hash,
                    "board": board_for(it, mega_board, board_prefix)})
    for it, prior in plan.change:
        ops.append({"op": "change", "origin": it.origin, "repo": it.repo,
                    "id": it.id, "item": it.item, "notes": it.notes,
                    "status": it.status, "target_native": it.target,
                    "row_hash": it.hash, "hermes_id": prior.hermes_id,
                    "prior_hermes_status": prior.hermes_status,
                    "board": board_for(it, mega_board, board_prefix)})
    for prior in plan.complete:
        ops.append({"op": "complete", "origin": prior.origin,
                    "board": prior.board, "hermes_id": prior.hermes_id,
                    "target_native": "done"})
    return "\n".join(json.dumps(o) for o in ops)


def main(argv=None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)

    pe = sub.add_parser("extract", help="print the origin-keyed extract (TSV)")
    pe.add_argument("--registry", type=Path, required=True)

    pp = sub.add_parser("plan", help="keyed diff extract vs snapshot")
    pp.add_argument("--registry", type=Path, required=True)
    pp.add_argument("--snapshot", type=Path)
    pp.add_argument("--mega-board", default="megagoals")
    pp.add_argument("--board-prefix", default="")
    pp.add_argument("--json", action="store_true",
                    help="emit the plan as NDJSON ops instead of a summary")

    args = ap.parse_args(argv)
    if not args.registry.is_file():
        print(f"cockpit: no registry at {args.registry}", file=sys.stderr)
        return 1
    items = extract_from_registry(args.registry.read_text())

    if args.cmd == "extract":
        for it in items:
            print("\t".join((it.origin, it.repo, it.id, it.item, it.notes,
                             it.status, it.target, it.hash)))
        return 0

    snap_text = ""
    if args.snapshot and args.snapshot.is_file():
        snap_text = args.snapshot.read_text()
    plan = plan_cockpit(items, read_snapshot(snap_text))
    if args.json:
        out = plan_to_json(plan, args.mega_board, args.board_prefix)
        if out:
            print(out)
        print(describe_plan(plan, args.mega_board, args.board_prefix).splitlines()[0],
              file=sys.stderr)
    else:
        print(describe_plan(plan, args.mega_board, args.board_prefix))
    return 0


if __name__ == "__main__":
    sys.exit(main())
