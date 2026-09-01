# SPEC: cc-worktree-provision

## Problem
A new git worktree (via EnterWorktree) lacks the gitignored env (`.envrc`/`.env`) and installed deps, so it is not immediately workable. Hand-wiring each worktree is friction, and the always-worktree policy means worktrees are created often.

## Solution
A MANUAL provisioner (`cc-worktree-provision --base <worktree>`) that symlinks the env from the main checkout into a worktree and runs the project install when a manifest is present. Best-effort, always exit 0.

It is deliberately NOT a `WorktreeCreate` hook: that event is a creation-delegate (the hook must create the worktree and echo its path), so a post-hoc provisioner there makes `EnterWorktree` fail. Run it after creating a worktree, or from your own wrapper. The deploy overlay carries a `del(.hooks.WorktreeCreate)` guard.

## Contract
- Input: `--base` = the worktree path (or `base_path` from a stdin JSON payload, for wrapper use). `--source` overrides the git-derived root.
- Source root: `git rev-parse --path-format=absolute --git-common-dir` then dirname.
- Symlink: each of `CC_WT_PROVISION_ENV` (default `.envrc,.env`) if present in source and absent in worktree.
- Install: `uv sync` if `pyproject.toml`, else `pnpm install` if `package.json`, unless `CC_WT_PROVISION_NO_INSTALL=1`.
- Exit: always 0.

## Non-goals
- Worktree creation itself (native EnterWorktree).
- Cleanup on WorktreeRemove (possible follow-on).
- Copying secrets (symlink only).
- Non-git directories.

## Verification
`tests/smoke.sh` (8 assertions): plan, no-op, real symlink, idempotency, manifest detection (uv/pnpm), junk-safe, missing-base_path-safe, stdin-payload-driven. (Run manually; there is no live hook to verify.)
