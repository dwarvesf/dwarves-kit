# adopt-agents-only: implementation notes

Spec: `docs/specs/SPEC-419-adopt-agents-only.md`. Only deltas from the spec.

## Build delta

- R7 is narrower than first written. The readiness hint now stays quiet only when `CLAUDE.md` exists, or `AGENTS.md` carries the kit block or the kit pointer. A stray `AGENTS.md` the kit never wrote still warns, so a repo on an older Claude Code build keeps the warning it needs. A hook never reads `kit.toml` (the standing lint), so the kit's own marker is the signal.
- `wrap adopt` preflight reads the key as committed on `origin/<default>` (the worktree adopt runs in is built from it), not from the main checkout, and picks the kit-root `kit.toml` the way `adopt.sh` does. Review found a main-checkout-on, origin-off split that let a dirty `CLAUDE.md` through the collision check and then failed the post-land pull.
- With the key on, an `AGENTS.md` that is an old kit copy (known hash, or the old contract's first line) gets no block, so `--refresh --swap-agents` can still recognise and swap it.
- `--refresh` now refuses an `AGENTS.md` with more than one `<!-- kit:adopt -->` / `<!-- /kit:adopt -->` line or an END before the START. The strip would otherwise drop consumer text between the blocks. This also applies with the key off (a data-loss guard, not a default behavior change in any file adopt wrote).
- The block append and refresh keep the target file's permission bits (mktemp makes 0600; the target is now a cross-tool file).
- Other readers of `CLAUDE.md` that now fall back to `AGENTS.md` when there is no `CLAUDE.md`: `hooks/post-compact-reinject.sh` (the PROJECT line), `lib/board/board-run.sh` (the `megagoal_root:` hint), plus the text in `hooks/pre-compact-backup.sh` and `commands/start.md`, `commands/mega.md`.
- Left alone on purpose: CRLF marker lines in a consumer file (pre-existing for `CLAUDE.md`), and a project `.kit.toml` key silently beating an explicit `--single-source` (the spec says the key wins; adopt prints one line saying so).
- `docs/reference/FEATURES.md` is regenerated (spec-reference counts). It will conflict with any other branch that also adds a spec; regenerate with `feature-registry.sh check --fix`.
