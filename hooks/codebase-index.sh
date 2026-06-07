#!/bin/bash
# codebase-index.sh , SessionStart hook (OPT-IN), dwarves-kit
#
# Keeps the current repo indexed in codebase-memory-mcp so kit commands can query a
# structural index (search_code / search_graph / get_architecture / trace_path)
# instead of grepping blind. See commands/spec.md and commands/execute.md.
#
# Kit philosophy (docs/PHILOSOPHY.md): integrate external tools, warn when missing,
# never rebuild their functionality. So this hook is opt-in and degrades cleanly:
#   - codebase-memory-mcp not installed  -> no-op (quiet; one-line hint only in debug)
#   - installed                          -> background index of the cwd repo
#
# Indexing runs in the BACKGROUND so session start is never blocked. index_repository
# is incremental on an already-indexed repo (keeps existing nodes, ~sub-second), so a
# re-run is a refresh, not a from-scratch rebuild. The kit stays quiet by default
# (no stdout) to honor the low-noise SessionStart contract; set DWARVES_KIT_DEBUG=1
# for a stderr trace.
set -euo pipefail

# OPT-IN: only act when the tool is on PATH.
if ! command -v codebase-memory-mcp >/dev/null 2>&1; then
  [ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && \
    echo "[dwarves-kit:index] codebase-memory-mcp not installed; commands will grep. Install it for index-aware kit." >&2
  exit 0
fi

# Only index real git repos. `git rev-parse` handles a worktree (where `.git` is a FILE,
# not a dir, so the old `[ -d .git ]` test silently skipped worktrees) and being in a
# subdir; index the repo TOPLEVEL, not the cwd subdir.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# Background, detached so it survives the hook returning. Build if new, incremental
# refresh if already indexed.
nohup codebase-memory-mcp cli index_repository "{\"repo_path\":\"$REPO\"}" \
  >/dev/null 2>&1 &
disown 2>/dev/null || true

[ "${DWARVES_KIT_DEBUG:-0}" = "1" ] && \
  echo "[dwarves-kit:index] refreshing codebase-memory index for $(basename "$REPO") in background" >&2
exit 0
