# SPEC-043: codebase-memory SessionStart auto-index hook

Status: SHIPPED
Lane: tiny
Backlog: (none; discovered live 2026-06-08, the auto-index was installed but inert)
Branch: feat/codebase-memory-index (hook shipped as a1a6e4b; this SPEC backfills it + adds the worktree-guard fix)

## Problem

The kit's commands (`/kit:spec`, `/kit:execute`) can query a structural index from
codebase-memory-mcp instead of grepping, but only if the repo is indexed. Indexing by
hand every session is friction. Worse, the hook that was meant to automate it shipped on
an unmerged branch, so in practice it never fired: the global `~/.claude/settings.json`
SessionStart entry symlinks into the dwarves-kit working tree, the repo was checked out on
a branch without the file, the symlink dangled, and the hook silently no-opped. And even
when present, its `[ -d .git ]` guard is false in a git worktree (`.git` is a file there),
so it skipped every worktree session.

## Solution

An opt-in SessionStart hook, `hooks/codebase-index.sh`, that background-indexes the cwd
repo in codebase-memory-mcp so the index stays fresh with zero manual step:

- **Opt-in by tool presence**: no-ops (quiet; one-line hint only under `DWARVES_KIT_DEBUG=1`)
  when codebase-memory-mcp is not on PATH, so the kit is unchanged for everyone else.
- **Backgrounded**: `nohup ... &` + `disown` so session start is never blocked.
- **Build-then-refresh**: `index_repository` builds the first time and is incremental
  (sub-second) afterward, so a re-run is a refresh, not a rebuild.
- **Worktree + subdir correct**: guards on `git rev-parse --is-inside-work-tree` (true in a
  normal repo, a worktree, and a subdir) and indexes `git rev-parse --show-toplevel` (the
  repo root), not the cwd subdir.

Wired into `settings.json` + `hooks/hooks.json` as a SessionStart hook. To be live it must
be on master (the install symlinks the working tree), so this SPEC ships with the merge.

## Scope

In:
- `hooks/codebase-index.sh` (the hook; backfilled + the worktree-guard fix).
- The SessionStart registration in `settings.json` + `hooks/hooks.json`.
- The `commands/spec.md` + `commands/execute.md` tool-name references to the real
  codebase-memory API (`get_architecture` / `search_code` / `trace_path`).
- A pinning meta-test in `tests/test-meta.sh`.

Out:
- Forcing codebase-memory on all kit users (opt-in only).
- A new indexer (uses codebase-memory's own `index_repository`).
- The navigation skill that steers the model to query the index (separate follow-up).

## Task Breakdown

### Phase 1: hook + guard

- [x] TASK-001: Opt-in SessionStart auto-index hook with a worktree-correct guard.
  Acceptance criteria:
  - `hooks/codebase-index.sh` exists, is executable, and guards on
    `git rev-parse --is-inside-work-tree` (NOT `[ -d .git ]`), so worktrees are indexed.
  - It is registered as a SessionStart hook in both `settings.json` and `hooks/hooks.json`.
  - It no-ops cleanly when codebase-memory-mcp is absent (opt-in).
  - The full meta-test suite passes: `bash tests/test-meta.sh` exits 0.

## Verification

Run: `bash tests/test-meta.sh` (expect exit 0). Behavioral: run the hook from a normal
repo dir and from a git worktree; both trigger an `index_repository` (verify via
`codebase-memory-mcp cli index_status`). With codebase-memory-mcp absent, the hook exits 0
without indexing.
