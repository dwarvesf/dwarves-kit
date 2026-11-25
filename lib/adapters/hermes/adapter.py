"""The Hermes adapter: builds the Hermes kanban spoke, with the page-body expander another adapter may provide."""
from __future__ import annotations

import sys

from hermes import HermesSource


def build(app, opts, ctx):
    if not opts.get("hermes_home"):
        sys.exit("hermes: set hermes_home in [sync] (.kit.toml) or pass "
                 "--hermes-home (the HERMES_HOME to sync against)")
    # Both keys name one operator's own instance, so neither carries a default:
    # guessing a target would point the sync at someone else's machine.
    if not opts.get("hermes_target"):
        sys.exit("hermes: set hermes_target in [sync] (.kit.toml) or pass "
                 "--hermes-target (an ssh host, 'local', or 'sudo:<user>')")
    return HermesSource(opts["hermes_target"], opts["hermes_home"],
                        board=opts.get("hermes_board"),
                        assignee=opts.get("hermes_assignee"),
                        workspace=opts.get("hermes_workspace"),
                        body_expander=ctx.hooks.get("body_expander"))


def brief_decisions(health, cluster, first_cluster):
    """What this adapter adds to the daily brief: one decision per linked profile whose kit skills are out of
    date. The sweep records the comparison each tick (`hermes_links`); a health state with no record compares
    now. Returns [(sort key, text)]; the brief wraps each text in its own item."""
    links = health.get("hermes_links")
    if links is None:
        import sweep_modules
        links = sweep_modules.load("board-hermes").check_links()
    return [((6, 0), f"kit skills on `{lk.get('label') or lk.get('profile')}` are stale: re-run `board hermes link`")
            for lk in links
            if lk.get("stale") and (lk.get("cluster") or first_cluster) == cluster]
