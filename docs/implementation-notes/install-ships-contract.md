# Implementation notes: install ships the operate-contract (sub-goal 04 of kit-adopt-enforce)

Spec: SPEC-049. Branch: `feat/kit-adopt-04-install` off master. Lane: normal (lane-classify
returned `normal`; packaging change, not enforcement). Normal lane = spec, build, review, ship.

## 2026-06-09, the fix

- Context: sub-goal 03 surfaced that `~/.claude/dwarves-kit/` lacks AGENTS.md + WORKFLOW.md, so
  adopt (needs a source AGENTS.md) and gate-ledger (reads `$KIT_ROOT/WORKFLOW.md`) break from the
  install. install.sh symlinks hooks + lib but never the two root contract files.
- Decision: symlink `AGENTS.md` + `WORKFLOW.md` into `$CLAUDE_DIR/dwarves-kit/` in install.sh's
  out-of-place branch (mirroring hooks + lib: a symlink keeps repo edits live). In-place installs
  already have them. Uninstall removes the two symlinks. No change to adopt.sh / gate-ledger
  resolution logic (the symlink fixes them as-is).
- Applied LIVE: created the two symlinks in `~/.claude/dwarves-kit/` so adopt + the lane gate work
  for Han now, not only after a fresh install. Re-tested the exact sub-goal 03 failures: both pass.
- Verification: `tests/test-install-contract.sh` 3/3 (adopt from install, gate-ledger reads matrix,
  control fails without the symlinks); `tests/test-meta.sh` 392/392.
- This closes the gap between the mega-goal's 3 original sub-goals and the destination
  "self-install" actually holding from the install.
