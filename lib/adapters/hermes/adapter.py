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
