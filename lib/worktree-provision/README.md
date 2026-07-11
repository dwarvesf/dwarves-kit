# worktree-provision

A **manual** provisioner that makes a freshly created git worktree usable: it symlinks
the gitignored env (`.envrc`/`.env`) from the main checkout into the worktree and runs
the project install when a manifest is present (a new worktree carries neither).

Folded in from ops-toolkit `tools/cc-worktree-provision` (cc-elevation-r2 sub-goal 04;
deferred by the 2026-07-05 kit-foldin disposition, unparked 2026-07-11). Orphan module
at `lib/` root, like `skill-curator` and `plugin-check`: a single cohesive tool with no
sibling subsystem. Named by FUNCTION on entry per the kit naming invariant: the callable
is `worktree-provision` and the env knobs are `WORKTREE_PROVISION_*` (the `cc-` /
`CC_` host-agent prefixes were dropped at the door).

> **Not a `WorktreeCreate` hook.** That event is a creation-delegate: the hook is
> expected to *create* the worktree and echo its path, so wiring a post-hoc provisioner
> there makes `EnterWorktree` fail. Run this manually (or from your own wrapper) after
> creating a worktree.

## Install + use

Exposed on PATH by `install.sh` when the `worktree` module is enabled
(`bash install.sh --with worktree`); stable entrypoint `bin/worktree-provision`.

```bash
worktree-provision --base <new-worktree-path> [--source <main-checkout>]   # provision it
worktree-provision --base <path> --dry-run                                 # show the plan only
```

## What it does

Given a worktree path (`--base`, or `base_path` from a stdin payload):

1. Symlinks `.envrc` / `.env` from the main checkout into the worktree, only if present
   in the source and missing in the worktree (secrets are linked, never copied).
2. Runs the install when a manifest is present (first match wins):
   `pyproject.toml` -> `uv sync` · `package.json` -> `pnpm install` · `go.mod` ->
   `go mod download` · `Cargo.toml` -> `cargo fetch` · `Gemfile` -> `bundle install`.

Always exits 0: provisioning is best-effort and must never block worktree creation.

Env knobs: `WORKTREE_PROVISION_NO_INSTALL=1` (skip the install), `WORKTREE_PROVISION_ENV="a,b"`
(env filenames, default `.envrc,.env`), `WORKTREE_PROVISION_VERBOSE=1` (stream the install).

## Test

```bash
bash lib/worktree-provision/tests/smoke.sh   # "smoke: all 14 passed"
```
