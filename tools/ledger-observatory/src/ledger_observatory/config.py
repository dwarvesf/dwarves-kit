"""Env-driven source roots + the derivable db path.

Every source is overridable so tests point at fixtures and the tool stays
portable across hosts. A missing source is skipped (empty table), never fatal.
"""

from __future__ import annotations

import os
from pathlib import Path


def _env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


def db_path() -> Path:
    """The materialized DuckDB lens. Derivable + disposable; never in the repo."""
    return _env_path(
        "LEDGER_OBSERVATORY_DB", "~/.cache/ledger-observatory/ledger.duckdb"
    )


def kit_lib_dir() -> Path:
    """dwarves-kit lib dir (holds lane-telemetry.sh, the mandated kit reader)."""
    return _env_path("DWARVES_KIT_LIB", "~/.claude/dwarves-kit/lib")


def kit_log_dir() -> Path:
    """The kit log root. lane-telemetry.sh reads $DWARVES_KIT_LOG_DIR/runs/*.log."""
    return _env_path("DWARVES_KIT_LOG_DIR", "~/.local/state/dwarves-kit/logs")


def tide_db_path() -> Path:
    return _env_path("LEDGER_OBS_TIDE_DB", "~/.local/state/tide/state.sqlite")


def tgcleanup_dir() -> Path:
    return _env_path("LEDGER_OBS_TGCLEANUP_DIR", "~/workspace/tieubao/ops-toolkit/tools/tg-cleanup")


def learned_md_path() -> Path:
    return _env_path(
        "LEDGER_OBS_LEARNED_MD", "~/workspace/tieubao/ops-toolkit/_meta/learned-ledger.md"
    )


def sessions_dir() -> Path:
    """Root of Claude Code session transcripts (SPEC-135): one subdir per project-cwd slug,
    one *.jsonl file per session. `adapters.read_sessions` reads a fixed field WHITELIST only
    (numbers/timestamps/short slugs); this knob never widens what gets read, only where from."""
    return _env_path("LEDGER_OBS_SESSIONS_DIR", "~/.claude/projects")


def secret_guard_log_path() -> Path:
    """The secret-guard audit log (SPEC-135): bracket-prefixed lines, COUNTS ONLY (see
    `adapters.read_safety`, which never captures the log's free-text remainder)."""
    return _env_path("LEDGER_OBS_SECRET_GUARD_LOG", "~/.cache/claude-secret-guard.log")


def git_repo_dir() -> Path:
    """The repo whose commit history `git_fixes` reads (SPEC-132). Defaults to this tool's
    own repo (ops-toolkit); override per-invocation to run `defect-correlation` against a
    different repo's history (e.g. `LEDGER_OBS_GIT_REPO_DIR=~/workspace/tieubao/dwarves-kit`).
    v1 is single-repo-per-materialization, a documented tradeoff (see README)."""
    return _env_path(
        "LEDGER_OBS_GIT_REPO_DIR", "~/workspace/tieubao/ops-toolkit"
    )


def memory_repo_dir() -> Path:
    """The repo whose `.claude/memory/` the memory-verify sweep walks as the 'repo' store
    (SPEC-136). Defaults to this tool's own repo, same convention as `git_repo_dir()` -- but a
    SEPARATE env knob, so isolating one source in a test never silently isolates the other (the
    HANDOFF cross-suite-pollution lesson)."""
    return _env_path("LEDGER_OBS_MEMORY_REPO_DIR", "~/workspace/tieubao/ops-toolkit")


def rejected_findings_repos() -> list[Path]:
    """Repos `read_rejected_findings` (SPEC-137) walks for a `docs/verification/
    rejected-findings.md` file. `LEDGER_OBS_REPOS` is a comma-separated list of repo ROOT
    paths -- the tool's FIRST genuinely multi-repo-in-one-materialization knob, unlike every
    other repo-scoped adapter here (`git_repo_dir`/`memory_repo_dir`), which is single-repo-
    per-invocation by convention. Chosen over reusing `_meta/boards.txt` (SPEC-137 DEC-001):
    that registry names paths to each repo's `BACKLOG.md` at an inconsistent nesting depth
    across its own rows (some `_meta/BACKLOG.md`, some bare `BACKLOG.md`), so deriving a repo
    root from it generically is unreliable; a dedicated env var matches this file's own
    one-knob-per-adapter convention instead. Default: the two repos gate-review-absorptions
    actually produced ledger files in as of this writing."""
    raw = os.environ.get(
        "LEDGER_OBS_REPOS",
        "~/workspace/tieubao/ops-toolkit,~/workspace/tieubao/dwarves-kit",
    )
    return [Path(p.strip()).expanduser() for p in raw.split(",") if p.strip()]


def memory_projects_root() -> Path:
    """Root of the built-in Claude Code auto-memory project dirs (SPEC-136): one
    `<project-slug>/memory/` subdirectory per project the harness has ever auto-memoried. Same
    real root as `sessions_dir()` (`~/.claude/projects`), but a DEDICATED env knob -- a test
    isolating one source must never silently isolate the other."""
    return _env_path("LEDGER_OBS_MEMORY_PROJECTS_ROOT", "~/.claude/projects")
