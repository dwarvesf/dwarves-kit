"""A neutral fixture adapter for the loader and engine tests: it names no real app."""
from __future__ import annotations

from types import SimpleNamespace


def build(app, opts, ctx):
    """One source per fixture app; each reads nothing and writes nothing."""
    if opts.get("fake_name") == "skip":
        print("%s: skipped (fixture)" % app)
        return None
    return SimpleNamespace(
        name=app, sync_fields=True,
        create_only=(app == "fake-create"), pull_only=(app == "fake-pull"),
        read=lambda: [], apply=lambda plan, assigned, rows_after: {})


def guard(names, opts):
    """Refuse a run that names the fixture app and sets fake_name to `refuse`."""
    if opts.get("fake_name") == "refuse":
        raise SystemExit("fake: refused by the fixture guard")


def body_expander(body):
    return body + " [expanded]"
