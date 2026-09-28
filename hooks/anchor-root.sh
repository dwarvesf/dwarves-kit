#!/bin/bash
# anchor-root.sh -- cd to the repo (or worktree) root, then run the given hook command.
# Every hooks.json / settings.json entry routes through this (secrets-guard.sh is the one
# named exclusion: it canonicalizes relative path operands against the real cwd), so no hook
# reads or writes relative to the wrong directory because a session's cwd was a subdirectory.
#
# Usage: anchor-root.sh <hook-path> [args...]
# The true invocation cwd survives as DWARVES_KIT_INVOCATION_CWD for any hook that needs it
# (ship-gate.sh resolves a relative embedded `cd` against it when the payload has no .cwd).
# Outside a git work tree ROOT falls back to $PWD, so the cd is a no-op. The cd also runs only
# when the physical cwd sits under ROOT: with core.worktree or GIT_WORK_TREE pointing the work
# tree elsewhere, a cd there would leave git discovery (and the hook) with no repo at all.
export DWARVES_KIT_INVOCATION_CWD="$PWD"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
case "$(pwd -P)/" in "$ROOT"/*) cd "$ROOT" 2>/dev/null || true ;; esac
# A .sh hook runs under an explicit `bash`, never by its exec bit: a hook that lost the bit
# must still block (exit 2), not exit 126, which Claude Code treats as non-blocking. Every
# wired target is a .sh file (the .py hooks sit behind .sh shims that call python3). exec
# keeps stdin, stdout, stderr, and the exit code untouched.
case "$1" in
  *.sh) exec bash "$@" ;;
  *) exec "$@" ;;
esac
