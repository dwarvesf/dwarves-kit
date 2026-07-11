# Implementation notes: cc-worktree-provision (cc-elevation-r2 sub-goal 04)

Delta from `_meta/megagoals/cc-elevation-r2/goals/04-worktree-autoprovision.md`.

## 2026-06-15 Always exit 0 (best-effort), even on a blockable event
- WorktreeCreate can block creation on a non-zero exit. This hook always exits 0: a failed symlink or install must never abort the worktree. Failures go to stderr only.

## 2026-06-15 Source root via git-common-dir, with --source override
- The main checkout root is derived from the new worktree via `git rev-parse --path-format=absolute --git-common-dir` then dirname. `--source` overrides it so the smoke needs no real git repo (stdlib-only, fast).
- Why: robust for linked worktrees (common-dir points at the main `.git`).

## 2026-06-15 Symlink, not copy; only when missing
- Env files are symlinked (secrets not duplicated; editing the source updates all worktrees) and only when present in source AND absent in the worktree (idempotent; respects a tracked/committed env already in the worktree).

## 2026-06-15 Install is synchronous + opt-out, not opt-in
- Per the spec, install runs by default when a manifest is present. Tradeoff: `uv sync`/`pnpm install` can be slow and runs synchronously in the hook; `CC_WT_PROVISION_NO_INSTALL=1` is the escape hatch for fast worktrees. Chose opt-out over opt-in to match the spec wording; the env hatch covers the "fast and safe" quality-bar tension.
- Alternative considered: backgrounding the install (non-blocking) -> rejected for v1 (a detached process complicates the always-exit-0 contract + error reporting; revisit if the synchronous wait bites).

## 2026-06-28 Go/Rust/Ruby manifests + verbose mode (ID-229 polish)
- Added go.mod -> `go mod download`, Cargo.toml -> `cargo fetch`, Gemfile -> `bundle install`. Refactored the if-ladder in `install_cmd()` into an ordered `MANIFEST_INSTALL` tuple; first present manifest wins, py/node kept first to preserve existing precedence for polyglot worktrees.
- `CC_WT_PROVISION_VERBOSE=1` echoes `running <cmd>` and streams the install's stdout+stderr live; default stays silent.
- Default-silence clarification (a small tightening of the prior code, not a spec deviation): the install now runs with `stdout=DEVNULL, stderr=PIPE` by default and prints a 5-line stderr tail only on non-zero exit, matching the documented "silent except errors" contract. The previous code inherited stdout/stderr unconditionally; under a captured-output hook context that read as silent, so default observable behavior is unchanged for the user while the verbose flag now meaningfully toggles visibility. Always-exit-0 preserved (no raise escapes; non-zero install exit is reported, not propagated).
- Tests: smoke grew from 8 to 14 assertions (3 manifest dry-runs, verbose dry-run label, a stubbed-`go`-on-PATH real run proving verbose streams cmd+output, and its silent-by-default negative control). No real toolchain needed.

## 2026-06-15 Live event-fire is a deploy check
- The unit smoke proves the script logic against the documented `base_path` payload shape. Confirming the real WorktreeCreate event fires + carries `base_path` needs the hook wired live + a real worktree creation, so it is a deploy-time verification (in the proof), not part of the autonomous smoke. Payload key fallbacks (`worktree_path`, `cwd`) are defensive in case the field name differs in this CC version.
