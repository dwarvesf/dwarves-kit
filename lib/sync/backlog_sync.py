#!/usr/bin/env python3
"""Two-way sync between a kit kanban BACKLOG.md (hub) and its spokes. Each spoke
is an adapter under lib/adapters/<name>/, picked by name in `[sync] apps`.

Front door: `board sync` (bin/board), which any adopted repo's `_meta/board`
shim already forwards to with the right --backlog-file. Spokes plug in per
repo via the `[sync]` section of `.kit.toml` (config layer); the
`cmd_sync` shim in lib/board/board.sh resolves those keys through
lib/config/kit-config.sh (the ONE TOML reader) and hands this engine plain
flags. This file reads no config file, by design.

Each configured spoke syncs independently via a three-way merge with a
per-board snapshot in <config data path state backlog-sync>/<board-slug>/<source>.state.json.
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
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "config"))
import adapters  # noqa: E402
import kit_data  # noqa: E402

from sync_core import (ID_TOKEN, INBOX_HEADING, apply_board,  # noqa: E402
                       board_lock, build_state, describe, detect_prefix,
                       parse_board,
                       plan_create_only, plan_pull_only, plan_sync)


def atomic_write(path: Path, text: str, new_mode: int = 0o644) -> None:
    """Replace `path` atomically, keeping its mode. mkstemp opens 0600, and a
    bare os.replace would hand that to the board, locking out every other
    account that reads it (a cron running as another user). A new file gets
    `new_mode`; the state files pass 0600."""
    try:
        mode = os.stat(path).st_mode & 0o7777
    except FileNotFoundError:
        mode = new_mode
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def warn_duplicate_ids(text: str, strict_id: bool = True) -> bool:
    """Print row-hygiene warnings; return False when the board must be
    refused outright (duplicate ids), True when it is safe to sync.

    A duplicate id means two rows are fighting over the same identity: which
    one is "first" depends on line order, not intent, so silently picking one
    (the old "first occurrence wins" behavior) can flip or create the wrong
    row underneath the operator. Refuse the whole board instead."""
    token = (re.escape(detect_prefix(text)) + r"-\d+") if strict_id \
        else ID_TOKEN
    ids = re.findall(r"^\| (" + token + r") \|", text, flags=re.M)
    dups = sorted({i for i in ids if ids.count(i) > 1})
    ok = True
    if dups:
        print(f"ERROR: duplicate board rows for {', '.join(dups)}; "
              "refusing to sync, run: board dedupe <ID> for each")
        ok = False
    parsed = set(parse_board(text, strict_id=strict_id,
                             prefix=detect_prefix(text)))
    broken = sorted(set(ids) - parsed - set(dups))
    if broken:
        print(f"WARNING: malformed board rows (not 4 cells, invisible to "
              f"sync) for {', '.join(broken)}; fix the board")
    return ok


def sync_create_only(src, backlog: Path, state_path: Path, dry_run: bool,
                     filt: dict | None = None) -> None:
    """One-way, insert-only push to a write-only sink. The board
    file is never written; the local state map is the identity index. State is
    checkpointed after EACH create, so a mid-batch failure never re-pushes an
    already-created page (no duplicate cards on a team-owned board)."""
    text = backlog.read_text()
    rows = parse_board(text, strict_id=False)
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if hasattr(src, "binding") and state.get("binding"):
        src.binding = state["binding"]
    plan = plan_create_only(rows, state, skip_kw=getattr(src, "skip_kw", None),
                            filt=filt,
                            bound_re=getattr(src, "bound_marker_re", None))
    # Validate the whole batch (maps resolve, options exist) BEFORE any write,
    # so `--dry-run` surfaces config errors and a live run never dies part-way.
    if hasattr(src, "preflight"):
        src.preflight(plan)
    header = (f"{src.name}: {len(rows)} board rows, "
              f"{len(plan.src_create)} to create")
    if dry_run:
        print(f"dry-run {header}")
        print(describe(plan))
        return

    new_map = dict(state.get("map", {}))
    state_path.parent.mkdir(parents=True, exist_ok=True)

    def write_state() -> None:
        new_state = {"map": new_map}
        if getattr(src, "binding", None):
            new_state["binding"] = src.binding
        atomic_write(state_path, json.dumps(new_state, indent=1), new_mode=0o600)

    def checkpoint(bid: str, rid: str) -> None:
        new_map[bid] = {"rid": rid}
        write_state()

    # Adoptions bind an existing page with no network call, so they are
    # persisted up front rather than through the create-only checkpoint,
    # which fires per POST.
    if plan.src_adopt:
        for bid, pid in plan.src_adopt:
            new_map[bid] = {"rid": pid, "via": "pull-marker"}
        write_state()

    created = src.apply(plan, {}, rows, on_created=checkpoint)
    print(f"synced {header}")
    print(describe(plan, created))


def sync_pull_only(src, backlog: Path, dry_run: bool,
                   heading: str = INBOX_HEADING) -> None:
    """One-way, insert-only INTAKE from a read-only source. Writes
    only the board file: no spoke write (the source has no write method), and
    no state file at all. Identity lives in the board row's own notes cell, so
    there is nothing to lose and a re-run recomputes exactly the missing rows.
    """
    items = src.read()
    # board read -> plan -> apply -> write runs under the shared per-board
    # lock (intake mints board ids); the spoke read above stays outside, so a
    # slow source never stalls an interactive `board capture`.
    with board_lock(backlog):
        text = backlog.read_text()
        prefix = detect_prefix(text)
        plan = plan_pull_only(text, items)
        header = f"{src.name}: {len(plan.board_add)} to intake"
        if dry_run:
            print(f"dry-run {header}")
            print(describe(plan))
            return
        new_text, assigned = apply_board(text, plan, prefix=prefix, path=backlog,
                                         heading=heading)
        if new_text != text:
            atomic_write(backlog, new_text)
        print(f"synced {header}")
        print(describe(plan, assigned))


def check_pull_isolation(names: list, args,
                         filters: dict | None = None, reg=None) -> None:
    """Two refusals that keep a read-only intake read-only (an adapter's `guard` hook adds its own).

    FILTER: this app takes none. The source board's own `Agent Queue` checkbox
    is the gate, and the pull path never consults `filt`, so accepting
    `--filter <pull app>:intake=none` would hand an operator a guard that
    silently does nothing.

    ISOLATION: a pull app runs alone. Intake mints a board id, and a downstream
    spoke keys its own idempotency on that id, so an intake row must be
    published to git BEFORE anything relays it. Sharing one invocation would
    let a relay key on an id the publish step may still discard, which
    duplicates the relayed task on the next run. The runner sequences
    intake, publish, relay as separate invocations instead.
    """
    reg = reg if reg is not None else adapters.load()
    pull_apps = reg.pull_only_apps()
    filtered = sorted(set(filters or {}) & pull_apps)
    if filtered:
        sys.exit(f"{filtered[0]}: this app takes no --filter; the source "
                 "board's own Agent Queue checkbox is the gate.")
    pull = [n for n in names if n in pull_apps]
    others = [n for n in names if n not in pull_apps]
    if pull and others:
        sys.exit(f"{pull[0]}: a pull app runs alone, but this invocation also "
                 f"lists {', '.join(others)}. Run intake first, publish the "
                 "board, then run the other apps (design question 1).")


def resolve_archive(backlog: Path, configured: Path | None) -> Path:
    """Where this board's archive lives.

    A relative configured path resolves against the BOARD's directory, never
    the process cwd. `board sync` runs from launchd and from any cwd, so a
    cwd-relative path reads an empty archive (closing nothing) or, worse,
    another repo's archive that shares the `ID-` prefix.
    """
    if configured is None:
        return backlog.parent / "BACKLOG-archive.md"
    return configured if configured.is_absolute() else backlog.parent / configured


def read_archive(path: Path | None, prefix: str) -> dict:
    """Rows an archive pass moved out of the board, keyed by board id.

    No readable archive means no evidence, which reads as an empty archive:
    the planner then closes nothing, exactly as it behaved before archives
    were consulted at all. A directory, a binary file, or an unreadable one
    must degrade the same way rather than kill a whole sync run.
    """
    if path is None or not path.exists():
        return {}
    try:
        return parse_board(path.read_text(), prefix=prefix)
    except (OSError, ValueError) as exc:
        print(f"archive: cannot read {path} ({exc}); no card closes on "
              "archive evidence this run")
        return {}


def sync_source(src, backlog: Path, state_path: Path, dry_run: bool,
                filt: dict | None = None, cap: int = 20,
                allow: int = 0, allow_flips: int = 0,
                archive: Path | None = None, allow_closes: int = 0,
                heading: str = INBOX_HEADING) -> bool:
    """Returns True when the run is clean, False when it hit a refusal the
    caller should reflect in the process exit code (the bulk-flip breaker)."""
    if getattr(src, "pull_only", False):
        sync_pull_only(src, backlog, dry_run, heading)
        return True
    if getattr(src, "create_only", False):
        sync_create_only(src, backlog, state_path, dry_run, filt)
        return True
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    if hasattr(src, "binding") and state.get("binding"):
        src.binding = state["binding"]
    items = src.read()
    # board read -> plan -> apply -> write runs under the shared per-board
    # lock: apply_board mints row ids, and a `board capture`/`board promote`
    # racing this window would otherwise mint the same id or watch its new row
    # get clobbered by this stale-text rewrite. The spoke read above stays
    # outside, so a slow source never stalls an interactive mint.
    with board_lock(backlog):
        text = backlog.read_text()
        prefix = detect_prefix(text)
        rows = parse_board(text, prefix=prefix)
        plan = plan_sync(rows, items, state, sync_fields=src.sync_fields,
                         filt=filt, app_name=src.name, allow_flips=allow_flips,
                         archived=read_archive(archive, prefix),
                         allow_closes=allow_closes)
        header = (f"{src.name}: {len(items)} spoke items, {len(rows)} board rows")
        preview = getattr(src, "preview", None)
        if preview:
            plan.notes.extend(preview(plan))
        if dry_run:
            print(f"dry-run {header}")
            print(describe(plan))
            return not plan.flips_refused
        exits = len(plan.src_scope_exit)
        if exits > max(cap, allow):
            print(f"{src.name}: ABORTED, {exits} items would leave this app's "
                  f"scope (cap {max(cap, allow)}). Review with --dry-run, then "
                  f"re-run with --allow-scope-exit {exits}.")
            # A tick can trip both guards at once: the scope-exit abort must
            # still surface a flip refusal, or the alarm is lost silently (this
            # path used to always return True regardless of plan.flips_refused).
            return not plan.flips_refused
        new_text, assigned = apply_board(text, plan, prefix=prefix, path=backlog,
                                         heading=heading)
        if new_text != text:
            atomic_write(backlog, new_text)
        rows_after = parse_board(new_text, prefix=prefix)
    created = src.apply(plan, assigned, rows_after)
    new_state = build_state(rows_after, items, plan, created, assigned, state)
    if getattr(src, "binding", None):
        new_state["binding"] = src.binding
    state_path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(state_path, json.dumps(new_state, indent=1), new_mode=0o600)
    print(f"synced {header}")
    print(describe(plan, assigned))
    return not plan.flips_refused


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


def _check_mode(name: str, src, mode: str) -> None:
    """The manifest mode is the contract: the source object must agree with it."""
    got = ("pull-only" if getattr(src, "pull_only", False)
           else "create-only" if getattr(src, "create_only", False) else "two-way")
    if got != mode:
        sys.exit(f"adapters: {name}: the manifest says {mode} but the source "
                 f"object is {got}")


def build_source(name: str, args, reg=None, state_path=None):
    """The one seam that turns an app name into a source object: the registry
    answers; a name no adapter provides ends the run."""
    reg = reg if reg is not None else adapters.load()
    if name in reg.apps:
        opts = {o.key: getattr(args, o.key, None) for o in reg.opts}
        ctx = SimpleNamespace(state_path=state_path,
                              project_root=os.environ.get("KIT_PROJECT_ROOT"))
        src = reg.build(name, opts, ctx)
        if src is not None:
            _check_mode(name, src, reg.mode(name))
        return src
    sys.exit(f"no adapter provides {name} (searched: {reg.dir})")


def main(argv=None):
    reg = adapters.load()
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apps", "--surfaces", "--sources", dest="apps",
                    default="",
                    help="comma list of apps (cmd_sync fills this from "
                         ".kit.toml [sync] apps; --surfaces/--sources are "
                         "legacy aliases)")
    ap.add_argument("--backlog", type=Path,
                    default=Path.cwd() / "_meta" / "BACKLOG.md")
    ap.add_argument("--archive-file", type=Path,
                    help="board archive closed rows move to (default: "
                         "BACKLOG-archive.md beside the board). A linked "
                         "spoke card closes only when its id sits here with "
                         "a closed status.")
    ap.add_argument("--state-root", type=Path,
                    default=Path(kit_data.path("state", "backlog-sync")))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--filter", action="append", default=[],
                    help="app:key=value (key: only_tags|skip_tags|intake|"
                         "intake_skip_re); "
                         "repeatable; cmd_sync fills these from .kit.toml")
    ap.add_argument("--scope-exit-cap", type=int, default=20)
    ap.add_argument("--allow-scope-exit", type=int, default=0,
                    help="one-run override when a legitimate bulk exit "
                         "exceeds the cap")
    ap.add_argument("--allow-flips", type=int, default=0,
                    help="one-run override when a legitimate bulk status "
                         "flip exceeds the cap")
    ap.add_argument("--allow-archived-closes", type=int, default=0,
                    help="one-run override when a legitimate bulk archive "
                         "pass closes more cards than the cap")
    for o in reg.opts:
        ap.add_argument(f"--{o.flag}", dest=o.key, help=o.help)
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
        elif key == "intake_skip_re":
            try:
                re.compile(val)
            except re.error as exc:
                sys.exit(f"bad --filter intake_skip_re {val!r}: {exc}")
            filters.setdefault(app, {})[key] = val
        else:
            sys.exit(f"bad --filter key {key!r} "
                     "(only_tags|skip_tags|intake|intake_skip_re)")

    names = [s.strip() for s in args.apps.split(",") if s.strip()]
    if not names:
        print("backlog_sync: no apps (--apps)", file=sys.stderr)
        sys.exit(2)
    # before any source is built, so a refused combination never touches a
    # transport or the board file: the guards of the adapters that provide a
    # named app, then the generic isolation rules, then the unknown-app exit
    opts = {o.key: getattr(args, o.key, None) for o in reg.opts}
    for guard in reg.hooks("guard", only=names):
        guard(names, opts)
    check_pull_isolation(names, args, filters, reg)
    unknown = [n for n in names if n not in reg.apps]
    if unknown:
        sys.exit(f"no adapter provides {unknown[0]} (searched: {reg.dir})")

    if not args.backlog.exists():
        sys.exit(f"no backlog at {args.backlog}; pass --backlog or run via "
                 "`board sync` from an adopted repo")

    # worktree fence: spokes (a remote list, a remote database) are shared per
    # BOARD, not per checkout. A sync run from a git worktree pairs the
    # spoke's items against that branch's divergent row set and poisons the
    # shared state for every other checkout (a 180-row cross-board fossil
    # map from exactly this, 2026-08-16, fed the 2026-09-01 dfoundation
    # title scramble). Only the canonical checkout may sync.
    if "/.claude/worktrees/" in str(args.backlog.resolve()) \
            and not os.environ.get("KIT_SYNC_ALLOW_WORKTREE"):
        sys.exit("board sync: refusing to sync a worktree checkout "
                 f"({args.backlog}); spokes are shared per board, and a "
                 "worktree's divergent rows poison them for every checkout. "
                 "Run from the canonical checkout, or set "
                 "KIT_SYNC_ALLOW_WORKTREE=1 if you truly know better.")

    archive = resolve_archive(args.backlog, args.archive_file)
    if args.archive_file and not archive.exists():
        print(f"archive: no file at {archive}; no card closes on archive "
              "evidence. Check sync.archive_file.")

    state_dir = board_state_dir(args.state_root, args.backlog)
    # single-writer lock: overlapping runs would hand out colliding IDs and
    # clobber each other's board writes. This serializes sync-vs-sync only; the
    # board file itself is additionally covered by sync_core.board_lock inside
    # sync_source/sync_pull_only, the lock `board capture`/`board promote` share.
    lock = open(state_dir / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit("another backlog-sync run holds the lock; try again")
    strict_id = not (set(names) & reg.create_only_apps())
    if not warn_duplicate_ids(args.backlog.read_text(), strict_id=strict_id):
        sys.exit(1)

    heading = reg.const("inbox-heading", INBOX_HEADING)
    ok = True
    for name in names:
        state_path = state_dir / f"{name}.state.json"
        src = build_source(name, args, reg, state_path)
        if src is None:
            continue
        if not sync_source(src, args.backlog, state_path, args.dry_run,
                           filt=filters.get(name), cap=args.scope_exit_cap,
                           allow=args.allow_scope_exit,
                           allow_flips=args.allow_flips,
                           archive=archive,
                           allow_closes=args.allow_archived_closes,
                           heading=heading):
            ok = False
    if not ok:
        sys.exit(1)


if __name__ == "__main__":
    main()
