# Spec: install.sh deploys AGENTS.md + WORKFLOW.md into the install

Status: DRAFT
Lane: normal

## Problem

`install.sh` symlinks `hooks/` and `lib/` into `~/.claude/dwarves-kit/` but never deploys the root
`AGENTS.md` or `WORKFLOW.md`. So when run from the install (the normal case, not the repo):
- `lib/adopt.sh` can't find a source `AGENTS.md` (it looks in `$KIT_ROOT` = the install) -> adopt
  fails with "no source AGENTS.md".
- `lib/gate/gate-ledger.sh` reads `$KIT_ROOT/WORKFLOW.md` for the lane x phase matrix -> "awk: can't
  open WORKFLOW.md", so the lane-completeness check silently passes (empty required set).

Surfaced dogfooding sub-goal 03 (adopting ops-toolkit): adopt + the lane gate only worked by
resolving from the kit repo. This is the gap between the shipped sub-goals and the destination
"self-install" actually holding.

## Design

In `install.sh`'s out-of-place branch (the one that symlinks hooks + lib), symlink `AGENTS.md` and
`WORKFLOW.md` into `$CLAUDE_DIR/dwarves-kit/` too (same pattern: a symlink keeps repo edits live).
The in-place install needs nothing (the files are already there). Add their removal to the
uninstall block (only a symlink is removed).

## Scope

**In:** the contract-deploy block in `install.sh` (install + uninstall), a test.
**Out:** changing adopt.sh / gate-ledger resolution logic (the symlink fixes them as-is); the
lane/proof taxonomy.
**Not:** copying lib (stays a symlink); a packaging format change; shipping more than these two
files.

## Acceptance criteria

- [ ] After the install block runs (out-of-place), `$CLAUDE_DIR/dwarves-kit/AGENTS.md` and
  `WORKFLOW.md` exist (symlinks to the repo).
- [ ] From a simulated install dir (lib + AGENTS.md + WORKFLOW.md symlinked), `bash
  $INSTALL/lib/adopt.sh <tmprepo>` creates the contract (finds the source AGENTS.md), and
  `gate-ledger required full` (KIT_ROOT=$INSTALL) prints the 11-gate matrix (reads WORKFLOW.md).
- [ ] Uninstall removes the two symlinks.
- [ ] `bash tests/test-install-contract.sh` passes; `bash tests/test-meta.sh` stays green.

## Test plan

| Scenario | assert |
|---|---|
| simulated install: adopt from install | AGENTS.md found, 4 artifacts land in the tmp repo |
| simulated install: gate-ledger reads matrix | `required full` lists 11 gates (non-empty) |
| (control) install WITHOUT the contract symlinks | adopt fails "no source AGENTS.md" |

## Resolved decisions

- Symlink (not copy) to mirror hooks/lib and keep repo edits live.
