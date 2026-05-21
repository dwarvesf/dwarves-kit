# Spec: Installer materializes hooks at the path settings.json references

Generated: 2026-05-21
Status: SHIPPED
Shipped: 2026-05-21 (PR #5, squash-merged to master)
Source: live defect, 2026-05-21. A fresh session on a dev checkout (`~/workspace/tieubao/dwarves-kit`) opened with `SessionStart:startup hook error ... bash: /Users/<user>/.claude/dwarves-kit/hooks/context-readiness.sh: No such file or directory`. Retroactive spec: the fix shipped first (PR #5) under the bug lane; this records the contract and the in-place regression the SDD pass then caught.
Depends on: `install.sh` (the bash install path), `settings.json` (hook command paths), `tests/test-meta.sh` (the structural guard). No new ADR: the chosen mechanism (per-file symlink from `KIT_DIR` into `~/.claude/...`) is the same pattern `install.sh` already uses for `commands/`, not a new architectural axis.
Lane: bug (a defect: the installer never placed the scripts the settings reference). Root cause recorded before the fix, per the bug lane's iron law.

## Problem

`settings.json` hard-codes every hook (and the statusline) at
`$HOME/.claude/dwarves-kit/hooks/<script>.sh`. The bash installer is documented
(README Option 2) to clone the repo **to** `~/.claude/dwarves-kit`, so in that
canonical layout the scripts already sit at the referenced path and everything
resolves with no copy step.

`install.sh` quietly depended on that coincidence. It:

- `chmod +x`'d the hooks at `$KIT_DIR/hooks/` (the installer's own location),
- merged `settings.json` (whose commands point at `$HOME/.claude/dwarves-kit/hooks/`),
- created only `~/.claude/dwarves-kit/logs/`.

It never materialized the scripts at the referenced path. When `KIT_DIR` is NOT
`~/.claude/dwarves-kit` (a dev checkout elsewhere, a CI clone, a template dir),
`~/.claude/dwarves-kit/` ends up holding only `logs/`, and all 14 hooks plus the
statusline point at missing files. Every hook then fails with
"No such file or directory"; `SessionStart`'s `context-readiness.sh` is just the
first to fire. A plain re-run of `install.sh` re-created the broken state instead
of fixing it.

## Root cause

`install.sh` conflated two paths that only coincide in the documented in-place
layout: the installer's source location (`$KIT_DIR`, used for `chmod`) and the
fixed path the settings reference (`$HOME/.claude/dwarves-kit/hooks/`). There was
no step that bridged them when they differ. The hooks were "installed" only in
the sense that the repo happened to be at the right path.

## Solution

### Approaches considered
1. **Per-file symlink each `hooks/*.sh` into `~/.claude/dwarves-kit/hooks/` when the kit lives elsewhere (CHOSEN).** Mirrors exactly how `install.sh` already links `commands/` into `~/.claude/commands/`, so repo edits stay live without a reinstall. Idempotent.
2. **Copy the scripts into `~/.claude/dwarves-kit/hooks/`.** Tradeoff: a dev checkout's edits would not take effect until reinstall; diverges from the command-link precedent. Rejected for the maintainer's dogfooding loop.
3. **Symlink the whole `hooks/` directory** (`~/.claude/dwarves-kit/hooks -> $KIT_DIR/hooks`). Tradeoff: simpler, but a stale real directory at the destination needs an `rm -rf` to replace, and `logs/` is a real sibling that a dir-symlink must not swallow. Per-file is non-destructive and matches the command pattern. Rejected.
4. **Document "clone only to `~/.claude/dwarves-kit`" and do nothing in code.** Tradeoff: leaves the installer silently broken for every non-canonical layout and gives no error pointing at the cause. Rejected: the installer should be location-independent.

### Chosen approach + why
Approach 1. It makes `install.sh` location-independent and consistent with the
existing `commands/` link step, and keeps `logs/` as a real sibling untouched.

### The in-place hazard (caught by this SDD pass, not at ship)
The naive per-file loop is **destructive in the canonical layout**: when
`KIT_DIR == ~/.claude/dwarves-kit`, the destination link path equals the source
script path, so `rm "$LINK"` deletes the real script and `ln -s` then points it
at itself, leaving a broken self-referential symlink. The first cut of the fix
(PR #5) had this bug; the regression test only exercised the out-of-place layout,
so it passed. Reproduced, then fixed by detecting the in-place layout
(`realpath(KIT_DIR) == realpath(~/.claude/dwarves-kit)`) and skipping the link
step (the scripts are already where they belong). A third meta-test now exercises
the in-place layout so this cannot regress.

### Architecture
```
install.sh, step 1b
  KIT_REAL  = realpath(KIT_DIR)
  DEST_REAL = realpath(~/.claude/dwarves-kit)   (empty if it doesn't exist yet)
  if KIT_REAL == DEST_REAL:   # in-place clone (README Option 2)
      skip; scripts already at the referenced path
  else:                       # dev checkout / CI / template
      drop a stale dir-symlink, mkdir the real dir,
      per-file symlink each hooks/*.sh into ~/.claude/dwarves-kit/hooks/
uninstall
  remove ONLY symlinks (in-place real files survive; the clone is deleted by hand)
```

## Technical Design

### Interfaces (I/O contract)
- **Inputs / consumes:** `$KIT_DIR/hooks/*.sh` (the source scripts), `$HOME` (the install root).
- **Outputs / produces:** every path referenced under `$HOME/.claude/dwarves-kit/hooks/` in `settings.json` resolves to a runnable script. Either symlinks (out-of-place) or the in-place real files.
- **Invariants:** idempotent (safe to re-run); never destroys a real hook script (in-place layout is detected and skipped); `logs/` is untouched; uninstall removes only the symlinks it created.

### Data model changes
None.

### Infrastructure changes
- Edit `install.sh`: add step 1b (in-place detection + per-file link) and symmetric uninstall cleanup.
- Edit `tests/test-meta.sh`: a new "Installer materializes the hooks settings.json references" section (3 assertions).

## Task Breakdown
- [x] **TASK-1: `install.sh` step 1b.** In-place detection via resolved-path compare; per-file symlink for the out-of-place layout; symmetric uninstall that removes only symlinks.
  - Acceptance: out-of-place install leaves every referenced hook path resolvable; in-place install leaves the real scripts intact (no broken self-symlink); `bash -n install.sh` clean.
- [x] **TASK-2: regression tests in `tests/test-meta.sh`.** (1) every referenced hook script exists in the repo `hooks/`; (2) a real install into a throwaway HOME resolves every referenced path; (3) an in-place install keeps the hook scripts resolvable.
  - Acceptance: all three assertions present and green; assertion (2) fails on the pre-fix installer; assertion (3) fails on the in-place-destructive first cut.
- [x] **TASK-3: docs.** SPEC-025 (this file), CHANGELOG `### Fixed`, RUNBOOK troubleshooting entry.
  - Acceptance: CHANGELOG entry under `[Unreleased]`; RUNBOOK lists the symptom -> cause -> fix; this spec exists with Status set.

## Acceptance Criteria (global)
- [x] A fresh bash install from a dev checkout (KIT_DIR != ~/.claude/dwarves-kit) leaves every hook + the statusline resolvable; no SessionStart hook error
- [x] An in-place install (KIT_DIR == ~/.claude/dwarves-kit, README Option 2) leaves the real hook scripts intact (no broken self-referential symlink)
- [x] `install.sh` is idempotent and the uninstall is symmetric (removes only the symlinks it created)
- [x] `tests/test-meta.sh` guards all three properties; the guards fail on the respective buggy installers and pass on the fixed one
- [x] `bash tests/test-meta.sh` and `bash tests/test-hooks.sh` both green; no em-dash introduced

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh`. Spot-checks (both proven this session):
- out-of-place: run the old `install.sh` from the repo into a temp HOME -> all 14 hooks + statusline unresolved (guard fails); fixed installer -> all resolve.
- in-place: copy the kit to `$TMP/.claude/dwarves-kit`, run its `install.sh` -> first cut produced a broken self-symlink; fixed installer prints "installed in place" and the scripts stay real files.

## Edge Cases
1. **`~/.claude/dwarves-kit` does not exist yet** (first ever install, out of place). `DEST_REAL` is empty -> the else branch runs -> `mkdir -p` creates it -> links placed. Correct.
2. **A previous run left a directory symlink** `~/.claude/dwarves-kit/hooks -> repo/hooks` (an earlier manual fix). Step 1b drops the symlink, then owns a real dir of per-file links. Idempotent convergence.
3. **In-place clone reached via a symlinked path.** `pwd -P` resolves both sides, so the compare still matches and the link step is skipped.
4. **Uninstall on an in-place clone.** Only symlinks are removed; the real scripts survive; `rmdir` no-ops on the non-empty dir. The clone is removed by hand (existing end-of-uninstall message).
5. **Plugin install path.** Unaffected: the plugin uses `hooks/hooks.json` with `${CLAUDE_PLUGIN_ROOT}`, not the `$HOME/.claude/dwarves-kit/hooks/` paths. This spec is bash-install only.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Hooks referenced but not installed (the original bug) | SessionStart "No such file or directory"; hooks silently dead | step 1b links them; meta guard (2) fails the build if any path is unresolved |
| In-place install destroys real scripts | hooks become broken self-symlinks; every hook dies after a reinstall | in-place detection skips linking; meta guard (3) fails the build if a script goes unresolvable |
| Stale state from an earlier partial fix | a dir-symlink or stale per-file links at the destination | step 1b drops a dir-symlink and replaces stale links; idempotent |
| Uninstall deletes a real in-place hook | a user loses repo files on uninstall | uninstall removes ONLY symlinks; real files survive |

## Out of Scope
- The Claude Code plugin install path (uses `${CLAUDE_PLUGIN_ROOT}`; never had this bug).
- Auto-symlinking the whole `~/.claude/dwarves-kit` to a dev checkout (logs would then write into the repo; rejected).
- Fixing the user's broken SSH agent (separate environment issue surfaced while pushing the PR).

## Decision Log
- **DEC-001**: Per-file symlink (not copy) for the out-of-place layout, mirroring the existing `commands/` link step, so a maintainer's dev-checkout edits take effect without a reinstall.
- **DEC-002**: Detect the in-place layout by comparing resolved paths (`pwd -P`) and skip linking, because there source == destination and linking is self-destructive. Found by reproducing the breakage during this SDD pass, not at ship.
- **DEC-003**: Uninstall removes only symlinks, so an in-place clone's real scripts are never deleted; the clone is torn down by hand (the existing uninstall message).
- **DEC-004**: No ADR. The mechanism is an instance of an existing pattern (command symlinking), not a new architectural decision.
- **DEC-005 (validation)**: Status held at VALIDATED, not SHIPPED, until PR #5 (plus this follow-up) merges; flip to SHIPPED at `/user:retro`.

## Open questions
(none blocking.)

## Source citations
- Defect: this session, 2026-05-21 (SessionStart hook error on a dev checkout).
- Pattern reused: `install.sh`'s existing `commands/` per-file symlink step.
- Layout contract: `README.md` Install Option 2 (clone to `~/.claude/dwarves-kit`); ADR-0009 (plugin/bash dual-ship).
- Philosophy bars: `docs/PHILOSOPHY.md` ("Verify before proceeding"; bash-over-binaries; every file justifies itself).

## Validation
Bug lane (no 5-reviewer spec-validate). The validation that mattered was the SDD
pass itself: writing this spec and re-reading the README surfaced the in-place
layout the first fix would have destroyed. Reproduced the breakage, fixed it, and
pinned it with meta guard (3). Both suites green (meta 216, hooks 92).
