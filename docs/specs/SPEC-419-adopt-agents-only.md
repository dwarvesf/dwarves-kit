# Spec: adopt.agents_only, AGENTS.md as a repo's one instruction file

Generated: 2026-11-12
Status: VALIDATED
Lane: full (the diff floor: `hooks/context-readiness.sh` and `kit.toml` are enforcement-surface paths)
Depth: standard (every fact was read live in the tree; the Claude Code behavior is from the vendor memory docs)
Type: spec-feature
File: `docs/specs/SPEC-419-adopt-agents-only.md`
References: `lib/adopt.sh` (`--single-source` block routing, `is_adopted`); `lib/wrap/wrap-adopt.sh` (`ADOPT_PATHS`, R3c, R3k, R6); `hooks/context-readiness.sh`; `lib/config/kit-config.sh`; https://code.claude.com/docs/en/memory (section "AGENTS.md")

## Problem

`lib/adopt.sh` writes a `CLAUDE.md` loader (an `@AGENTS.md` import plus a managed block) into every adopted repo, and `--refresh` restores it. A consumer repo (`consolelabs/playdate-agent`) wants ONE instruction file, `AGENTS.md`. Claude Code v2.1.277 and later reads `AGENTS.md` directly when no `CLAUDE.md` exists in the working directory or above it; before v2.1.281 some sessions (Bedrock, telemetry off) read only `CLAUDE.md`. Today the only way out is `--single-source`, which still writes a one-line `CLAUDE.md`. A repo needs a plain opt-out.

## Rules

| # | Rule |
|---|---|
| R1 | New key `[adopt] agents_only` (default `false`), resolved with `kit_config_get`: project `.kit.toml` > operator `kit.toml` > kit-root `kit.toml`. A project file may set it: it only picks which file adopt writes inside the repo being adopted, and an operator runs adopt by hand on that repo. |
| R2 | Key on: `adopt.sh` (fresh and `--refresh`) never creates, restores or edits `CLAUDE.md`. An existing `CLAUDE.md` is left byte-identical, including a legacy kit block inside it. |
| R3 | Key on: the operate-contract block lands in `AGENTS.md` (the managed block `--single-source` writes, with no self-import). `AGENTS.md` is still created as the pointer when absent and still never overwritten when present; the pointer already carries the rules, so no block is added to a kit pointer, nor to an old kit copy (so `--refresh --swap-agents` still recognises it). The append and the refresh keep the file's permission bits. `--refresh` refuses an `AGENTS.md` with more than one block, or an END before the START, rather than drop text outside the block. |
| R4 | Key on: `adopt --check` stops requiring `CLAUDE.md`. |
| R5 | Key on wins over `--single-source` and `adopt.single_source`, which both write a `CLAUDE.md`. |
| R6 | `wrap adopt` follows the key per repo, read as the worktree will see it (committed on `origin/<default>`, kit-root picked as `adopt.sh` picks it): a dirty or ignored `CLAUDE.md` is not a collision (R3c, R3k, R6 ignore check), and a staged `CLAUDE.md` fails the path guard. |
| R7 | `hooks/context-readiness.sh` stays quiet about a missing `CLAUDE.md` only when `AGENTS.md` carries the kit block or the kit pointer. A hook never reads `kit.toml` (the standing lint), so the kit's own marker is the signal. A stray `AGENTS.md` with neither still warns. |
| R8 | Key off or unset: today's behavior in `adopt.sh` and `wrap adopt`, except the new `--refresh` data-loss guard of R3 (more than one block) and the file-mode keep. |
| R9 | The other readers of `CLAUDE.md` fall back to `AGENTS.md` when there is no `CLAUDE.md`: `hooks/post-compact-reinject.sh` (PROJECT line), `lib/board/board-run.sh` (`megagoal_root:` hint). The text in `hooks/pre-compact-backup.sh`, `commands/start.md` and `commands/mega.md` names both files. |

## Solution

### Approaches considered

| Approach | Verdict |
|---|---|
| A. A new `[adopt] agents_only` key that reuses `--single-source`'s block routing and never writes `CLAUDE.md` | chosen |
| B. Extend `adopt.single_source` with a third value | rejected: that knob is root-only and still ends with a `CLAUDE.md` import; two meanings under one name |
| C. A `--no-claude-md` flag only | rejected: `--refresh` from `wrap adopt` and `/kit:onboard` would restore the file unless every caller passes it; a repo needs a committed setting |

### Chosen approach + why

A. One committed key, read at adopt time, covers adopt, refresh and `wrap adopt` with no flag plumbing, and the block routing already exists and is tested.

## Technical Design

- `lib/adopt.sh`: resolve `AGENTS_ONLY` after the single-source resolution; `BLOCK_IN_AGENTS` (single-source or agents-only) drives `block_target`, `block_mode`, `pointer_is_block` and `is_adopted`. The symlink refusal list drops `CLAUDE.md` in this mode. A dry run on a repo with no `AGENTS.md` plans no duplicate block.
- `lib/wrap/wrap-adopt.sh`: `_adopt_agents_only <dir>` reads the same key; `ADOPT_AO` gates R3c, R3k, the in-worktree ignore check, and `_adopt_path_ok`.
- `hooks/context-readiness.sh`: R7. `post-compact-reinject.sh`, `board-run.sh`, text edits: R9.
- Docs: `kit.toml` `[adopt]`, `lib/config/module-registry.md`, `docs/guides/adopt.md`, `commands/adopt.md`, `commands/onboard.md`, `docs/reference/consumer-contract.md`, `lib/adopt/README.md`, `CHANGELOG.md`.

### Out of scope

CRLF marker lines in a consumer file (pre-existing for `CLAUDE.md`). `lib/wrap/wrap-adopt.sh`'s `ADOPT_PATHS` keeps `CLAUDE.md` (an allowlist; the key tightens the guard, never widens it).

## Task Breakdown

1. `adopt.sh` routing, `wrap-adopt.sh` follow, the hook line.
2. Tests: `tests/test-adopt.sh` (AO1 to AO7), `tests/test-wrap-adopt.sh` (41 to 43), `tests/test-hooks.sh` (readiness).
3. Docs above.

## After state

A repo with `[adopt] agents_only = true` adopts, refreshes and lands through `wrap adopt` with no `CLAUDE.md` write. Every other repo is unchanged except the softened readiness hint (R7).

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 fresh adopt with the key writes the pointer, marker and wiring, no `CLAUDE.md`; `--check` exits 0; rerun and `--refresh` are clean no-ops | `tests/test-adopt.sh` AO1 |
| AC2 an existing `CLAUDE.md` is untouched; a repo-authored `AGENTS.md` gets exactly one block through adopt and `--refresh` | AO2, AO3 |
| AC3 `--dry-run` writes nothing and plans no `CLAUDE.md` or duplicate block | AO4 |
| AC4 the key beats `--single-source`; the operator file can set it; `false` keeps today's loader | AO5, AO6, AO7 |
| AC5 `wrap adopt` ignores a dirty `CLAUDE.md` under the key, still refuses it without the key, lands a commit with no `CLAUDE.md`, and fails a driver that writes one | `tests/test-wrap-adopt.sh` 41 to 43 |
| AC6 the readiness hint stays quiet only for `CLAUDE.md` or a kit-marked `AGENTS.md`; a stray `AGENTS.md` warns | `tests/test-hooks.sh` context-readiness |
| AC8 an old kit `AGENTS.md` still swaps; two blocks refuse `--refresh`; the file mode survives | AO8 to AO10 |
| AC9 the key committed locally but not on origin does not decide the preflight | `tests/test-wrap-adopt.sh` 44 |
| AC7 negative control: ignore the key in `adopt.sh` and AO1 to AO6 go red; ignore it in `wrap-adopt.sh` and 41 to 43 go red | `docs/verification/adopt-agents-only.md` |

## Verification

```bash
bash tests/test-adopt.sh
bash tests/test-wrap-adopt.sh
bash tests/test-hooks.sh
bash tests/run-all.sh --changed
```
