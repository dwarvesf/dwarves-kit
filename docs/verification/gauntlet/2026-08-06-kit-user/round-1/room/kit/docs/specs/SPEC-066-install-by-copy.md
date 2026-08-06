# SPEC-066: Kit distribution: install by copy, version-pinned

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral (the installed enforcement layer changes shape)
Board: ID-054

## Problem

install.sh symlinked hooks (per-file), lib (whole dir), and the contract files into
`~/.claude/dwarves-kit/`, so the LIVE enforcement code followed the clone's checked-out
branch. Observed 2026-06-08: a fixed safety-gate silently regressed to the old build when
the checkout switched branches mid-session; observed again 2026-06-10 when SPEC-064's
own ship ran the OLD ship-gate. An install that mutates when a developer switches
branches is not an install; it is a foot-gun with a version number.

## Decision

1. **Copy, never symlink** (bash-install mode): hooks copied + chmod +x; lib copied as a
   real dir; AGENTS.md/WORKFLOW.md copied. In-place installs (clone == install dir)
   unchanged. Upgrade path: pull the repo, re-run install.sh; copies are derived state,
   anti-drift (a hand-edited installed hook is reverted by re-install).
2. **INSTALL-STAMP** (`version= / sha= / date= / managed=`) written on every bash-install.
   Kit-managed-ness is the stamp's `managed=` LIST, not stamp presence (review F1: the
   stamp is written by the same run that first sees a user's file, so presence-based
   guarding destroyed the user file on run 2). A contract file never recorded as managed
   is the user's own: never refreshed, never uninstalled.
3. **kit-health staleness probe**: stamp sha != repo HEAD -> "stale install; re-run
   install.sh" (advisory); no stamp + symlinked hooks = pre-SPEC-066, recommend pinning.
4. **uninstall** removes copied files as well as legacy symlinks (kit dir only).
5. `CLAUDE_DIR` env-overridable (default unchanged) so the install is fixture-testable.

## Acceptance criteria

- AC1: fixture install produces real executable hook files, a real lib dir, real contract
  files, and a stamp with version+sha.
- AC2: re-run is idempotent and reverts a hand-edited installed hook (anti-drift).
- AC3: a user's own contract file (no stamp) is left untouched.
- AC4: kit-health carries the staleness probe; uninstall removes copies.

## Test plan

7 fixture tests (real-file asserts, stamp content, idempotent re-run, anti-drift negative
control: hand-edit an installed hook -> re-install reverts it) + 1 meta pin (cp present,
hook ln -s absent, stamp in install.sh + kit-health).

## Verification

- `tests/test-hooks.sh`: 301/301 (288 + 13: fresh install, idempotence, anti-drift
  negative control, the F1 two-run user-file durability probe, managed-list content,
  4 uninstall asserts).
- `tests/test-meta.sh`: 423/423 (+1).
- Live fixture install into a temp CLAUDE_DIR recorded in the PR body.
- Deployment note: the REAL install on this machine still symlinks until this merges and
  `bash install.sh` is re-run; tracked as the wave close-out step.

## Review

Date: 2026-06-10. Adversarial pass (sequences walked live: fresh / re-run / pre-066
upgrade / user-file). Verdict: **FIX-FIRST 5/10**, 2 HIGH + 2 MEDIUM + 2 LOW, all fixed:

1. HIGH, chicken-and-egg: stamp-presence guarding destroyed a user's AGENTS.md on the
   SECOND run (the stamp is written by the run that first sees the file). Fixed: the
   stamp carries a `managed=` list; only listed files are refreshed/uninstalled. Two-run
   durability test added.
2. HIGH, uninstall removed only symlinks, orphaning the copied lib/, contracts, stamp.
   Fixed: removes copies (managed-list-aware); 4 uninstall asserts.
3. MEDIUM, a `$HOME/.claude` hardcode for the logs dir leaked fixture installs into the
   real home. Fixed to `$CLAUDE_DIR`.
4. MEDIUM, "[ok] Copied AGENTS.md + WORKFLOW.md" printed even when AGENTS.md was skipped.
   Fixed: the message lists only what was actually copied.
5. LOW, AC3 was untested. The durability probe above covers it.
6. LOW, stale pre-066 comment in the uninstall block. Rewritten.

Post-fix: hooks 301/301, meta 423/423. Verdict: SHIP.
