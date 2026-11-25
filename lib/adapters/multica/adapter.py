"""The Multica adapter: builds the Multica REST spoke."""
from __future__ import annotations

import sys

from multica import MulticaSource


def build(app, opts, ctx):
    keys = ("multica_url", "multica_workspace", "multica_project")
    missing = [k for k in keys if not opts.get(k)]
    if missing:
        sys.exit(f"multica: set {', '.join(missing)} in [sync] "
                 "(.kit.toml) or pass the matching --flags")
    return MulticaSource(opts["multica_url"], opts["multica_workspace"],
                         opts["multica_project"])
