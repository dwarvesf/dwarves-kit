"""The Apple Reminders adapter: builds the Reminders spoke and carries the one-time state copy."""
from __future__ import annotations

import shutil
from pathlib import Path

from reminders import RemindersSource


def legacy_state_path() -> Path:
    """Where the pre-kit single-source tool kept its state (read at call time, so HOME decides)."""
    return Path.home() / ".cache" / "backlog-reminders-sync" / "state.json"


def _migrate_legacy_state(target: Path) -> None:
    legacy = legacy_state_path()
    if not target.exists() and legacy.exists():
        shutil.copy(legacy, target)
        print(f"migrated legacy reminders state -> {target}")


def build(app, opts, ctx):
    if ctx.state_path is not None:
        _migrate_legacy_state(Path(ctx.state_path))
    return RemindersSource(opts.get("reminders_list") or "Backlog")
