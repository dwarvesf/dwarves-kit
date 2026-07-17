#!/usr/bin/env python3
"""Two-way sync between a kit kanban BACKLOG.md (hub) and its spokes: Apple
Reminders, a Notion board, the Hermes kanban. See docs/specs/SPEC-001.

Front door: `board sync` (bin/board), which any adopted repo's `_meta/board`
shim already forwards to with the right --backlog-file. Spokes plug in per
repo via the `[sync]` section of `.kit.toml` (ADR-0034 config layer); the
`cmd_sync` shim in lib/board/board.sh resolves those keys through
lib/config/kit-config.sh (the ONE TOML reader) and hands this engine plain
flags. This file reads no config file, by design.

Each configured spoke syncs independently via a three-way merge with a
per-board snapshot in ~/.cache/backlog-sync/<board-slug>/<source>.state.json.
Board wins on conflict; spoke deletions never touch the board.
"""

import argparse
import fcntl
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_core import apply_board, build_state, describe, parse_board, plan_sync  # noqa: E402
from sources.hermes import HermesSource  # noqa: E402
from sources.multica import MulticaSource  # noqa: E402
from sources.notion import NotionSource  # noqa: E402
from sources.reminders import RemindersSource  # noqa: E402

LEGACY_REMINDERS_STATE = (Path.home() / ".cache" / "backlog-reminders-sync"
                          / "state.json")


def atomic_write(path: Path, text: str) -> None:
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def warn_duplicate_ids(text: str) -> None:
    ids = re.findall(r"^\| (ID-\d+) \|", text, flags=re.M)
    dups = sorted({i for i in ids if ids.count(i) > 1})
    if dups:
        print(f"WARNING: duplicate board rows for {', '.join(dups)}; "
              "first occurrence wins, fix the board")
    parsed = set(parse_board(text))
    broken = sorted(set(ids) - parsed - set(dups))
    if broken:
        print(f"WARNING: malformed board rows (not 4 cells, invisible to "
              f"sync) for {', '.join(broken)}; fix the board")


def sync_source(src, backlog: Path, state_path: Path, dry_run: bool,
                filt: dict | None = None, cap: int = 20,
                allow: int = 0) -> None:
    text = backlog.read_text()
    rows = parse_board(text)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if hasattr(src, "binding") and state.get("binding"):
        src.binding = state["binding"]
    items = src.read()
    plan = plan_sync(rows, items, state, sync_fields=src.sync_fields,
                     filt=filt)
    header = (f"{src.name}: {len(items)} spoke items, {len(rows)} board rows")
    preview = getattr(src, "preview", None)
    if preview:
        plan.notes.extend(preview(plan))
    if dry_run:
        print(f"dry-run {header}")
        print(describe(plan))
        return
    exits = len(plan.src_scope_exit)
    if exits > max(cap, allow):
        print(f"{src.name}: ABORTED, {exits} items would leave this app's "
              f"scope (cap {max(cap, allow)}). Review with --dry-run, then "
              f"re-run with --allow-scope-exit {exits}.")
        return
    new_text, assigned = apply_board(text, plan)
    if new_text != text:
        atomic_write(backlog, new_text)
    rows_after = parse_board(new_text)
    created = src.apply(plan, assigned, rows_after)
    new_state = build_state(rows_after, items, plan, created, assigned, state)
    if getattr(src, "binding", None):
        new_state["binding"] = src.binding
    state_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(state_path, json.dumps(new_state, indent=1))
    print(f"synced {header}")
    print(describe(plan, assigned))


def board_state_dir(root: Path, backlog: Path) -> Path:
    slug = re.sub(r"[^a-zA-Z0-9]+", "-", str(backlog.resolve())).strip("-")
    d = root / slug
    if not d.exists():
        d.mkdir(parents=True, exist_ok=True)
        # adopt pre-slug flat state files (single-board era) once
        for f in root.glob("*.state.json"):
            shutil.move(str(f), d / f.name)
            print(f"migrated state {f.name} -> {d}")
    return d


def build_source(name: str, args):
    if name == "reminders":
        return RemindersSource(args.list_name or "Backlog")
    if name == "notion":
        return NotionSource(db=args.notion_db, parent=args.notion_parent)
    if name == "hermes":
        if not args.hermes_home:
            sys.exit("hermes: set hermes_home in [sync] (.kit.toml) or pass "
                     "--hermes-home (the HERMES_HOME to sync against)")
        return HermesSource(args.hermes_target or "mini-tieubao",
                            args.hermes_home)
    if name == "multica":
        missing = [f for f, v in (("multica_url", args.multica_url),
                                  ("multica_workspace", args.multica_workspace),
                                  ("multica_project", args.multica_project))
                   if not v]
        if missing:
            sys.exit(f"multica: set {', '.join(missing)} in [sync] "
                     "(.kit.toml) or pass the matching --flags")
        return MulticaSource(args.multica_url, args.multica_workspace,
                             args.multica_project)
    sys.exit(f"unknown source {name!r}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apps", "--surfaces", "--sources", dest="apps",
                    default="reminders",
                    help="comma list of apps (cmd_sync fills this from "
                         ".kit.toml [sync] apps; --surfaces/--sources are "
                         "legacy aliases)")
    ap.add_argument("--backlog", type=Path,
                    default=Path.cwd() / "_meta" / "BACKLOG.md")
    ap.add_argument("--state-root", type=Path,
                    default=Path.home() / ".cache" / "backlog-sync")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list", dest="list_name", help="Reminders list name")
    ap.add_argument("--notion-db", help="bind an existing Notion database id")
    ap.add_argument("--notion-parent",
                    help="Notion page id to create the board under (bootstrap)")
    ap.add_argument("--hermes-target")
    ap.add_argument("--hermes-home")
    ap.add_argument("--multica-url", help="Multica server base URL")
    ap.add_argument("--multica-workspace", help="Multica workspace UUID")
    ap.add_argument("--multica-project", help="Multica project UUID")
    ap.add_argument("--filter", action="append", default=[],
                    help="app:key=value (key: only_tags|skip_tags|intake); "
                         "repeatable; cmd_sync fills these from .kit.toml")
    ap.add_argument("--scope-exit-cap", type=int, default=20)
    ap.add_argument("--allow-scope-exit", type=int, default=0,
                    help="one-run override when a legitimate bulk exit "
                         "exceeds the cap")
    args = ap.parse_args(argv)

    filters: dict[str, dict] = {}
    for spec in args.filter:
        app, _, kv = spec.partition(":")
        key, _, val = kv.partition("=")
        if key in ("only_tags", "skip_tags"):
            filters.setdefault(app, {})[key] = {
                t.strip() for t in val.split(",") if t.strip()}
        elif key == "intake":
            filters.setdefault(app, {})[key] = val.strip()
        else:
            sys.exit(f"bad --filter key {key!r} (only_tags|skip_tags|intake)")

    if not args.backlog.exists():
        sys.exit(f"no backlog at {args.backlog}; pass --backlog or run via "
                 "`board sync` from an adopted repo")
    names = [s.strip() for s in args.apps.split(",") if s.strip()]

    state_dir = board_state_dir(args.state_root, args.backlog)
    # single-writer lock: overlapping runs would hand out colliding IDs and
    # clobber each other's board writes
    lock = open(state_dir / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit("another backlog-sync run holds the lock; try again")
    warn_duplicate_ids(args.backlog.read_text())

    # one-time migration from the pre-kit single-source tool's state path
    rem_state = state_dir / "reminders.state.json"
    if not rem_state.exists() and LEGACY_REMINDERS_STATE.exists():
        shutil.copy(LEGACY_REMINDERS_STATE, rem_state)
        print(f"migrated legacy reminders state -> {rem_state}")

    for name in names:
        state_path = state_dir / f"{name}.state.json"
        if name == "notion":
            has_binding = (state_path.exists() and
                           json.loads(state_path.read_text()).get("binding"))
            if not (has_binding or args.notion_db or args.notion_parent):
                print("notion: skipped (no binding; set notion_db/notion_parent"
                      " in [sync] (.kit.toml) or pass --notion-db)")
                continue
        src = build_source(name, args)
        sync_source(src, args.backlog, state_path, args.dry_run,
                    filt=filters.get(name), cap=args.scope_exit_cap,
                    allow=args.allow_scope_exit)


if __name__ == "__main__":
    main()
