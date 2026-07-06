# Sub-goal 04: Auto-provision a new worktree

**Time budget:** ~2-3h
**Depends on:** none
**Branch:** feat/cc-elev-r2-04-worktree
**PR base:** main

## Outcome

A `WorktreeCreate` hook that makes a freshly created worktree immediately workable: symlink the gitignored env (`.envrc`, `.env` if present in the parent checkout) into the new worktree, and run the project's install (`uv sync` / `pnpm install`) when a manifest is present. So I stop hand-wiring every new worktree.

## Quality bar

Fast and safe. Symlinks (not copies) of env so secrets are not duplicated into the worktree. Install runs only when a manifest exists. No-ops cleanly for a repo with nothing to provision. Honors the always-worktree workflow.

## How to close the loop

- Implement the WorktreeCreate hook (reads `base_path` from the payload); symlink env + conditional install.
- Given a fixture repo with `.envrc` + a `pyproject.toml`: creating a worktree symlinks the env and runs `uv sync`; given a fixture repo with neither, the hook no-ops (negative control). Verify the WorktreeCreate event actually fires + its payload shape.
- Lane via lane-classify; new tool owes `tools/<name>/docs/proof-of-done.md`.

**Done =** creating a worktree triggers the hook, which symlinks gitignored env + runs install when a manifest is present, and no-ops cleanly otherwise (negative control), with the WorktreeCreate payload verified; proof-of-done; on PR #NN.

## Scope edges

**In:** the WorktreeCreate hook + tool dir + tests + proof + dotfiles one-line wire.
**Out:** worktree creation itself (native EnterWorktree); cleanup on WorktreeRemove (follow-on, note in Proposed additions).
**Not:** copying secrets (symlink only); auto-provisioning non-git dirs.

## Open knobs (do NOT flip without Han)

- Which files to symlink (default `.envrc`, `.env`); which install commands (default uv/pnpm by manifest).

## Where to look

The `WorktreeCreate` event payload (`base_path`, `isolation_reason`) + whether it fires for EnterWorktree, the always-worktree policy, direnv `.envrc`, `tools/tide/` for shape.

## PR body

Outcome: a WorktreeCreate hook that auto-provisions new worktrees (symlink env + conditional install).
Verify: fixture with env+manifest provisions; fixture with neither no-ops; payload verified.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 04).

## Notes
