"""Env-driven source roots.

Every source is overridable so tests point at fixtures and the tool stays
portable across hosts. A missing source is skipped (empty table), never fatal.
There is no derivable db path: `stats` (SPEC-182) materializes in-memory per invocation
and persists nothing, so no `*_DB` cache knob exists.

**Adapter-default split (SPEC/goal 05K, the ops-toolkit -> dwarves-kit move).** Two
different flavors of default live in this file, and they now behave differently:

- **Kit-internal sources** (`DWARVES_KIT_LIB`, `STATS_GIT_REPO_DIR`,
  `STATS_MEMORY_REPO_DIR`): these describe "wherever this tool's own repo is".
  Before the move that repo was ops-toolkit (hardcoded); now that the tool lives
  INSIDE dwarves-kit, the default is computed at runtime via `_kit_repo_root()`
  instead of a hardcoded personal path -- a simplification (same-repo-relative), not
  new machinery, and it never goes stale again on a future move.
- **ops-toolkit-specific sources** (`STATS_TIDE_DB`, `STATS_TGCLEANUP_DIR`,
  `STATS_LEARNED_MD`, `STATS_REPOS`): tide/tg-cleanup/learned-ledger are
  ops-toolkit tools, not kit-generic ones. These now have NO hardcoded fallback --
  an unset env var means "not configured", handled by the existing skip-safe
  contract (an absent/None source returns an empty table, never an exception).
  `DWARVES_KIT_LOG_DIR` stays unchanged: it was already host-generic (XDG state,
  see `lib/kit-log-dir.sh`), never ops-toolkit- or repo-specific, so the move does
  not affect it. `STATS_SESSIONS_DIR`/`STATS_SECRET_GUARD_LOG`/
  `STATS_MEMORY_PROJECTS_ROOT` are likewise host-generic (Claude Code's own
  `~/.claude/projects` and `~/.cache/claude-secret-guard.log`), unrelated to which
  repo hosts this tool.
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
    """This tool's own repo root, now that it lives inside dwarves-kit (05K move). The
    primary lookup mirrors `lib/weekend-batch.sh`'s `_repo_root()` shell convention:
    `git rev-parse --show-toplevel` (correct under a worktree checkout too). The
    fallback deliberately does NOT mirror the shell version (which falls back to
    `pwd`, the caller's cwd): a Python CLI can be invoked from any cwd, so falling
    back to cwd here would be fragile. Instead this walks a fixed parent count from
    this file's OWN location if git is unavailable (e.g. a non-git install) -- this
    file lives at `lib/stats/src/stats/config.py`, four directories below the repo
    root, so the fallback (`parents[4]`) is cwd-independent by construction.
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


def kit_lib_dir() -> Path:
    """dwarves-kit lib dir (holds lane-telemetry.sh, the mandated kit reader).
    Kit-internal (05K): now that this tool lives INSIDE the kit, the default is this
    repo's OWN `lib/` (via `_kit_repo_root()`), not a separately-installed
    `~/.claude/dwarves-kit/lib` copy that could drift from the code actually running
    this CLI."""
    return _env_path("DWARVES_KIT_LIB", str(_kit_repo_root() / "lib"))


def kit_log_dir() -> Path:
    """The kit LEDGER root: the SAME single root the write side writes to.

    ASKS THE ONE RESOLVER (lib/telemetry/kit-log-dir.sh), it does not reimplement it.
    The previous version was a second Python copy of the precedence chain whose docstring
    claimed it "mirrors the shell resolver exactly" while skipping level 3, the
    `kit.toml [ledger].location` key. Under `location = "isolated"` the write plane wrote
    to the toml location and this read plane read the XDG default, and it failed SILENTLY:
    `stats` simply reported no runs. Latent only because the shipped default (`shared`)
    makes both agree by accident (found 2026-07-15 while writing ADR-0035).

    Two implementations of one resolver is the same bug class as a hand-list beside a
    deriving resolver: the copy drifts, and the drift is invisible until it costs you.
    """
    resolver = _kit_repo_root() / "lib" / "telemetry" / "kit-log-dir.sh"
    if resolver.is_file():
        r = subprocess.run(
            ["bash", "-c", f'. "{resolver}" && kit_resolve_log_dir'],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            # The resolver's own fatal (e.g. KIT_LEDGER_DIR set but empty). Do not paper
            # over it with a guess: a wrong ledger root reads someone else's history.
            raise SystemExit((r.stderr or "stats: kit-log-dir.sh refused to resolve a ledger root").strip())
        root = r.stdout.strip()
        if root:
            return Path(root).expanduser()
    # Resolver absent (a partial checkout): fall back to the env chain WITHOUT the toml
    # level, and say so, rather than silently reading a plausible-but-wrong root.
    ledger_dir = os.environ.get("KIT_LEDGER_DIR")
    if ledger_dir is not None:
        if ledger_dir == "":
            raise SystemExit(
                "stats: KIT_LEDGER_DIR is set but empty; refusing a ledger root "
                "(would read from a relative path)"
            )
        return Path(ledger_dir).expanduser()
    xdg = os.environ.get("XDG_STATE_HOME", "~/.local/state")
    return _env_path("DWARVES_KIT_LOG_DIR", f"{xdg}/dwarves-kit/logs")


def tide_db_path() -> Path | None:
    """ops-toolkit-specific (05K): tide is an ops-toolkit tool. No default post-move;
    an unset env var means "not configured" (skip-safe, same as a path that does not
    exist)."""
    return _env_path_optional("STATS_TIDE_DB")


def tgcleanup_dir() -> Path | None:
    """ops-toolkit-specific (05K): tg-cleanup is an ops-toolkit tool. No default
    post-move; see `tide_db_path()`."""
    return _env_path_optional("STATS_TGCLEANUP_DIR")


def learned_md_path() -> Path | None:
    """ops-toolkit-specific (05K): the learning ledger lives in ops-toolkit's
    `_meta/`. No default post-move; see `tide_db_path()`."""
    return _env_path_optional("STATS_LEARNED_MD")


def sessions_dir() -> Path:
    """Root of Claude Code session transcripts (SPEC-135): one subdir per project-cwd slug,
    one *.jsonl file per session. `adapters.read_sessions` reads a fixed field WHITELIST only
    (numbers/timestamps/short slugs); this knob never widens what gets read, only where from.
    Host-generic (Claude Code's own dir), unaffected by the 05K move."""
    return _env_path("STATS_SESSIONS_DIR", "~/.claude/projects")


def secret_guard_log_path() -> Path:
    """The secret-guard audit log (SPEC-135): bracket-prefixed lines, COUNTS ONLY (see
    `adapters.read_safety`, which never captures the log's free-text remainder).
    Host-generic, unaffected by the 05K move."""
    return _env_path("STATS_SECRET_GUARD_LOG", "~/.cache/claude-secret-guard.log")


def git_repo_dir() -> Path:
    """The repo whose commit history `git_fixes` reads (SPEC-132). Kit-internal (05K):
    defaults to this tool's OWN repo root (`_kit_repo_root()`, now dwarves-kit) rather
    than a hardcoded ops-toolkit path; override per-invocation to run
    `defect-correlation` against a different repo's history (e.g.
    `STATS_GIT_REPO_DIR=~/workspace/<owner>/ops-toolkit`). v1 is
    single-repo-per-materialization, a documented tradeoff (see README)."""
    return _env_path("STATS_GIT_REPO_DIR", str(_kit_repo_root()))


def memory_repo_dir() -> Path:
    """The repo whose `.claude/memory/` the memory-verify sweep walks as the 'repo'
    store (SPEC-136). Kit-internal (05K), same convention as `git_repo_dir()` -- but a
    SEPARATE env knob, so isolating one source in a test never silently isolates the
    other (the HANDOFF cross-suite-pollution lesson)."""
    return _env_path("STATS_MEMORY_REPO_DIR", str(_kit_repo_root()))


def rejected_findings_repos() -> list[Path]:
    """Repos `read_rejected_findings` (SPEC-137) walks for a `docs/verification/
    rejected-findings.md` file. `STATS_REPOS` is a comma-separated list of repo ROOT
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
    raw = os.environ.get("STATS_REPOS", "")
    return [Path(p.strip()).expanduser() for p in raw.split(",") if p.strip()]


def memory_projects_root() -> Path:
    """Root of the built-in Claude Code auto-memory project dirs (SPEC-136): one
    `<project-slug>/memory/` subdirectory per project the harness has ever auto-memoried. Same
    real root as `sessions_dir()` (`~/.claude/projects`), but a DEDICATED env knob -- a test
    isolating one source must never silently isolate the other. Host-generic, unaffected by
    the 05K move."""
    return _env_path("STATS_MEMORY_PROJECTS_ROOT", "~/.claude/projects")
