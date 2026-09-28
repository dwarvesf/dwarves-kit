#!/bin/bash
# anchor-root.sh -- cd to the repo (or worktree) root, then run the given hook command.
# Every hooks.json / settings.json entry routes through this (secrets-guard.sh is the one
# named exclusion: it canonicalizes relative path operands against the real cwd), so no hook
# reads or writes relative to the wrong directory because a session's cwd was a subdirectory.
#
# Usage: anchor-root.sh <hook-path> [args...]
# The true invocation cwd survives as DWARVES_KIT_INVOCATION_CWD for any hook that needs it
# (ship-gate.sh resolves a relative embedded `cd` against it when the payload has no .cwd).
# Outside a git work tree ROOT falls back to $PWD, so the cd is a no-op. exec keeps stdin,
# stdout, stderr, and the exit code untouched.
export DWARVES_KIT_INVOCATION_CWD="$PWD"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
cd "$ROOT" 2>/dev/null || true
exec "$@"
