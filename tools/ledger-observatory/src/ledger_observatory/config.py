"""Env-driven source roots + the derivable db path.

Every source is overridable so tests point at fixtures and the tool stays
portable across hosts. A missing source is skipped (empty table), never fatal.

**Adapter-default split (SPEC/goal 05K, the ops-toolkit -> dwarves-kit move).** Two
different flavors of default live in this file, and they now behave differently:

- **Kit-internal sources** (`DWARVES_KIT_LIB`, `LEDGER_OBS_GIT_REPO_DIR`,
  `LEDGER_OBS_MEMORY_REPO_DIR`): these describe "wherever this tool's own repo is".
  Before the move that repo was ops-toolkit (hardcoded); now that the tool lives
  INSIDE dwarves-kit, the default is computed at runtime via `_kit_repo_root()`
  instead of a hardcoded personal path -- a simplification (same-repo-relative), not
  new machinery, and it never goes stale again on a future move.
- **ops-toolkit-specific sources** (`LEDGER_OBS_TIDE_DB`, `LEDGER_OBS_TGCLEANUP_DIR`,
  `LEDGER_OBS_LEARNED_MD`, `LEDGER_OBS_REPOS`): tide/tg-cleanup/learned-ledger are
  ops-toolkit tools, not kit-generic ones. These now have NO hardcoded fallback --
  an unset env var means "not configured", handled by the existing skip-safe
  contract (an absent/None source returns an empty table, never an exception).
  `DWARVES_KIT_LOG_DIR` stays unchanged: it was already host-generic (XDG state,
  see `lib/kit-log-dir.sh`), never ops-toolkit- or repo-specific, so the move does
  not affect it. `LEDGER_OBSERVATORY_DB`/`LEDGER_OBS_SESSIONS_DIR`/
  `LEDGER_OBS_SECRET_GUARD_LOG`/`LEDGER_OBS_MEMORY_PROJECTS_ROOT` are likewise
  host-generic (a derivable cache dir; Claude Code's own `~/.claude/projects` and
  `~/.cache/claude-secret-guard.log`), unrelated to which repo hosts this tool.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


def _env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


def _env_path_optional(name: str) -> Path | None:
    """Like `_env_path`, but for a source with NO default (ops-toolkit-specific): an
    unset env var returns None, which every caller treats the same way it already
    treats a missing path -- skip-safe, never fatal."""
    v = os.environ.get(name)
    return Path(v).expanduser() if v else None


def _kit_repo_root() -> Path:
    """This tool's own repo root, now that it lives inside dwarves-kit (05K move).
    Mirrors `lib/weekend-batch.sh`'s `_repo_root()` shell convention: `git rev-parse
    --show-toplevel` first (correct under a worktree checkout too), falling back to a
    fixed parent-count walk from this file's own location if git is unavailable (e.g.
    a non-git install). This file lives at
    `tools/ledger-observatory/src/ledger_observatory/config.py`, four directories
    below the repo root.
    """
    try:
        out = subprocess.run(
            ["git", "-C", str(Path(__file__).resolve().parent), "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=5,
        )
        if out.returncode == 0:
            top = out.stdout.strip()
            if top:
                return Path(top)
    except (OSError, subprocess.SubprocessError):
        pass
    return Path(__file__).resolve().parents[4]


def db_path() -> Path:
    """The materialized DuckDB lens. Derivable + disposable; never in the repo.
    Host-generic cache dir, unrelated to which repo hosts this tool -- unchanged by
    the 05K move."""
    return _env_path(
        "LEDGER_OBSERVATORY_DB", "~/.cache/ledger-observatory/ledger.duckdb"
    )


def kit_lib_dir() -> Path:
    """dwarves-kit lib dir (holds lane-telemetry.sh, the mandated kit reader).
    Kit-internal (05K): now that this tool lives INSIDE the kit, the default is this
    repo's OWN `lib/` (via `_kit_repo_root()`), not a separately-installed
    `~/.claude/dwarves-kit/lib` copy that could drift from the code actually running
    this CLI."""
    return _env_path("DWARVES_KIT_LIB", str(_kit_repo_root() / "lib"))


def kit_log_dir() -> Path:
    """The kit log root. lane-telemetry.sh reads $DWARVES_KIT_LOG_DIR/runs/*.log.
    UNCHANGED by the 05K move: this was already host-generic XDG state (see
    `lib/kit-log-dir.sh`'s own resolver), never tied to ops-toolkit or to which repo
    hosts this tool, so there is nothing to make repo-relative here."""
    return _env_path("DWARVES_KIT_LOG_DIR", "~/.local/state/dwarves-kit/logs")


def tide_db_path() -> Path | None:
    """ops-toolkit-specific (05K): tide is an ops-toolkit tool. No default post-move;
    an unset env var means "not configured" (skip-safe, same as a path that does not
    exist)."""
    return _env_path_optional("LEDGER_OBS_TIDE_DB")


def tgcleanup_dir() -> Path | None:
    """ops-toolkit-specific (05K): tg-cleanup is an ops-toolkit tool. No default
    post-move; see `tide_db_path()`."""
    return _env_path_optional("LEDGER_OBS_TGCLEANUP_DIR")


def learned_md_path() -> Path | None:
    """ops-toolkit-specific (05K): the learning ledger lives in ops-toolkit's
    `_meta/`. No default post-move; see `tide_db_path()`."""
    return _env_path_optional("LEDGER_OBS_LEARNED_MD")


def sessions_dir() -> Path:
    """Root of Claude Code session transcripts (SPEC-135): one subdir per project-cwd slug,
    one *.jsonl file per session. `adapters.read_sessions` reads a fixed field WHITELIST only
    (numbers/timestamps/short slugs); this knob never widens what gets read, only where from.
    Host-generic (Claude Code's own dir), unaffected by the 05K move."""
    return _env_path("LEDGER_OBS_SESSIONS_DIR", "~/.claude/projects")


def secret_guard_log_path() -> Path:
    """The secret-guard audit log (SPEC-135): bracket-prefixed lines, COUNTS ONLY (see
    `adapters.read_safety`, which never captures the log's free-text remainder).
    Host-generic, unaffected by the 05K move."""
    return _env_path("LEDGER_OBS_SECRET_GUARD_LOG", "~/.cache/claude-secret-guard.log")


def git_repo_dir() -> Path:
    """The repo whose commit history `git_fixes` reads (SPEC-132). Kit-internal (05K):
    defaults to this tool's OWN repo root (`_kit_repo_root()`, now dwarves-kit) rather
    than a hardcoded ops-toolkit path; override per-invocation to run
    `defect-correlation` against a different repo's history (e.g.
    `LEDGER_OBS_GIT_REPO_DIR=~/workspace/tieubao/ops-toolkit`). v1 is
    single-repo-per-materialization, a documented tradeoff (see README)."""
    return _env_path("LEDGER_OBS_GIT_REPO_DIR", str(_kit_repo_root()))


def memory_repo_dir() -> Path:
    """The repo whose `.claude/memory/` the memory-verify sweep walks as the 'repo'
    store (SPEC-136). Kit-internal (05K), same convention as `git_repo_dir()` -- but a
    SEPARATE env knob, so isolating one source in a test never silently isolates the
    other (the HANDOFF cross-suite-pollution lesson)."""
    return _env_path("LEDGER_OBS_MEMORY_REPO_DIR", str(_kit_repo_root()))


def rejected_findings_repos() -> list[Path]:
    """Repos `read_rejected_findings` (SPEC-137) walks for a `docs/verification/
    rejected-findings.md` file. `LEDGER_OBS_REPOS` is a comma-separated list of repo ROOT
    paths -- the tool's FIRST genuinely multi-repo-in-one-materialization knob, unlike every
    other repo-scoped adapter here (`git_repo_dir`/`memory_repo_dir`), which is single-repo-
    per-invocation by convention. Chosen over reusing `_meta/boards.txt` (SPEC-137 DEC-001):
    that registry names paths to each repo's `BACKLOG.md` at an inconsistent nesting depth
    across its own rows (some `_meta/BACKLOG.md`, some bare `BACKLOG.md`), so deriving a repo
    root from it generically is unreliable; a dedicated env var matches this file's own
    one-knob-per-adapter convention instead.

    ops-toolkit-specific (05K): the pre-move default named two specific repos
    (ops-toolkit + dwarves-kit) by hardcoded personal path. No default post-move --
    an unset env var yields an empty list (zero repos scanned, the same honest-empty
    contract `read_rejected_findings` already applies to any repo with no ledger
    file); pass an explicit comma-separated list to opt in."""
    raw = os.environ.get("LEDGER_OBS_REPOS", "")
    return [Path(p.strip()).expanduser() for p in raw.split(",") if p.strip()]


def memory_projects_root() -> Path:
    """Root of the built-in Claude Code auto-memory project dirs (SPEC-136): one
    `<project-slug>/memory/` subdirectory per project the harness has ever auto-memoried. Same
    real root as `sessions_dir()` (`~/.claude/projects`), but a DEDICATED env knob -- a test
    isolating one source must never silently isolate the other. Host-generic, unaffected by
    the 05K move."""
    return _env_path("LEDGER_OBS_MEMORY_PROJECTS_ROOT", "~/.claude/projects")
