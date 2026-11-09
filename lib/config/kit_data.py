"""kit_data: the Python door to the kit's data-path resolver (lib/config/data-path.sh).

The shell file is the only place the precedence lives. This module asks it, so a Python tool never
keeps a second copy of the rules. One call costs one bash start; a caller that asks often keeps the
answer for its own process.

    import kit_data
    kit_data.path("state", "harvest")   # -> "/home/me/.local/state/dwarves-kit/harvest"

A caller that needs its own env override (HARVEST_STATE_DIR and the like) reads it first; the
resolver also honors it. Raises KitDataError when bash or the resolver is unusable, or the entry is
unknown: a broken install is loud, never a silent wrong path.
"""
import os
import subprocess

_RESOLVER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data-path.sh")


class KitDataError(RuntimeError):
    pass


def path(kind, name):
    try:
        out = subprocess.run(["bash", _RESOLVER, "path", kind, name],
                             capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as exc:
        raise KitDataError("kit_data: cannot run %s: %s" % (_RESOLVER, exc))
    if out.returncode != 0 or not out.stdout:
        raise KitDataError("kit_data: %s %s: %s" % (kind, name, out.stderr.strip() or "no path"))
    return out.stdout
