"""The Notion adapter: builds the three Notion apps, refuses a write aimed at the intake database, and
offers the page-body expander that another adapter's card creation can use."""
from __future__ import annotations

import json
import sys

from notion import NotionSource
from notion_taskboard import NotionTaskBoardSource, parse_map
from notion_taskboard_pull import NotionTaskBoardPullSource, expand_body

body_expander = expand_body


def guard(names, opts):
    """No write-capable app may point at the pull app's own database.

    The pull app cannot write, but `notion` is two-way and hub-wins: aimed at the same board it would
    PATCH the very human-owned pages the intake exists to leave alone, and trash them on a scope exit.
    Ids are compared with dashes stripped, since Notion accepts both forms for the same database.
    """
    target = (opts.get("notion_taskboard_pull_db") or "").replace("-", "")
    if not target:
        return
    clash = [k for k, v in (("notion_db", opts.get("notion_db")),
                            ("notion_taskboard_db", opts.get("notion_taskboard_db")))
             if v and v.replace("-", "") == target]
    if clash:
        sys.exit(f"{', '.join(clash)} points at the same database as "
                 "notion_taskboard_pull_db. That board is read-only by "
                 "contract; never aim a write-capable app at it.")


def build(app, opts, ctx):
    if app == "notion":
        return _two_way(opts, ctx)
    if app == "notion-taskboard":
        return _push(opts)
    return _pull(opts)


def _two_way(opts, ctx):
    state_path = getattr(ctx, "state_path", None)
    has_binding = (state_path is not None and state_path.exists() and
                   json.loads(state_path.read_text()).get("binding"))
    if not (has_binding or opts.get("notion_db") or opts.get("notion_parent")):
        print("notion: skipped (no binding; set notion_db/notion_parent"
              " in [sync] (.kit.toml) or pass --notion-db)")
        return None
    return NotionSource(db=opts.get("notion_db"), parent=opts.get("notion_parent"),
                        title=opts.get("notion_title") or "Backlog")


def _push(opts):
    if not opts.get("notion_taskboard_db"):
        sys.exit("notion-taskboard: set notion_taskboard_db in [sync] "
                 "(.kit.toml) or pass --notion-taskboard-db")
    status_map = parse_map(opts.get("notion_taskboard_status_map"))
    if not status_map and not opts.get("notion_taskboard_status_default"):
        sys.exit("notion-taskboard: set notion_taskboard_status_map "
                 "(and/or notion_taskboard_status_default) in [sync]")
    props = json.loads(opts["notion_taskboard_props"]) \
        if opts.get("notion_taskboard_props") else None
    types = json.loads(opts["notion_taskboard_types"]) \
        if opts.get("notion_taskboard_types") else None
    return NotionTaskBoardSource(
        db=opts["notion_taskboard_db"], status_map=status_map,
        status_default=opts.get("notion_taskboard_status_default"),
        priority_map=parse_map(opts.get("notion_taskboard_priority_map")),
        weight_map=parse_map(opts.get("notion_taskboard_weight_map")),
        owner=opts.get("notion_taskboard_owner"), props=props, types=types)


def _pull(opts):
    if not opts.get("notion_taskboard_pull_db"):
        sys.exit("notion-taskboard-pull: set notion_taskboard_pull_db in "
                 "[sync] (.kit.toml) or pass --notion-taskboard-pull-db")
    props = json.loads(opts["notion_taskboard_pull_props"]) \
        if opts.get("notion_taskboard_pull_props") else None
    return NotionTaskBoardPullSource(
        db=opts["notion_taskboard_pull_db"], props=props,
        done_option=opts.get("notion_taskboard_pull_done_option") or "Done")
