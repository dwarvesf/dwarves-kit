# Implementation notes -- codebase-index-hook

Backfill SDD for the opt-in codebase-memory SessionStart auto-index hook (shipped as
commit a1a6e4b), plus the worktree-guard fix that makes it actually fire.

## 2026-06-08 Why this is a backfill + a fix
- Context: `hooks/codebase-index.sh` shipped on this branch (a1a6e4b) but the branch was never merged. Discovered live: the global `~/.claude/settings.json` SessionStart entry symlinks into the dwarves-kit working tree, but the repo was checked out on a different branch (`feat/verify-by-execution`) that lacks the file, so the symlink dangled and the hook silently no-opped. Auto-index was "installed but not running."
- Decision: (1) backfill a SPEC for the already-shipped hook, (2) fix the worktree guard, (3) merge to master so the file lives on the default branch and the symlink resolves like every other kit hook.

## 2026-06-08 Worktree guard: `[ -d .git ]` -> `git rev-parse`
- Context: the original guard was `[ -d .git ] || exit 0`. In a git WORKTREE `.git` is a FILE, not a directory, so the test was false and the hook skipped every worktree session (e.g. the ops-toolkit benchmark worktree this whole session ran in).
- Decision/Change: `git rev-parse --is-inside-work-tree` as the guard (true in a normal repo, a worktree, and a subdir), and `REPO="$(git rev-parse --show-toplevel)"` so it indexes the repo TOPLEVEL instead of whatever subdir cwd happened to be.
- Why: correctness , worktrees are a first-class workflow here (the global CLAUDE.md mandates worktrees for parallel work), so a hook that skips them is broken for the common case.
- Alternatives considered: `[ -e .git ]` (covers dir+file but not subdirs, and keeps the cwd-subdir bug); `git rev-parse` is one cheap call and the hook already shells out to a heavier tool.
- Impact: worktree + subdir sessions now index; the indexed path is normalized to the toplevel.

## 2026-06-08 SPEC number 043 (skip 042 to avoid a cross-branch collision)
- Context: this branch's highest SPEC is 041; the parallel `feat/verify-by-execution` branch already used SPEC-042 (proof of done).
- Decision: number this SPEC-043 so the two branches do not both claim 042 and conflict when both reach master.

## 2026-06-08 Root-cause lesson (not just this hook)
- A kit hook is only live if its file is on the checked-out branch's working tree (the install symlinks the working tree). New hooks therefore MUST land on master to fire for normal checkouts. This one sat unmerged, so it was inert. Recorded so the next new-hook PR merges promptly instead of lingering.
