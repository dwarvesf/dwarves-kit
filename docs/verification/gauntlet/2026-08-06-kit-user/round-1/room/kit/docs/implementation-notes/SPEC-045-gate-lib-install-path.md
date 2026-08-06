# Implementation notes: SPEC-045 gate lib install path

## 2026-06-08 Decisions

- **Lib deploy = dir symlink** `~/.claude/dwarves-kit/lib -> $KIT_DIR/lib` (not per-file copy), mirroring how hooks are deployed and keeping repo edits live (matters for the maintainer's --plugin-dir workflow). In-place install (KIT_DIR == ~/.claude/dwarves-kit) skips it, same guard as hooks.
- **`pwd -P` in proof-gate.sh**: with a symlinked lib, `$(dirname BASH_SOURCE)` + plain `pwd` is the logical path (~/.claude/dwarves-kit/lib), so `../docs/verification/task-types.md` would miss. `pwd -P` resolves to the real repo lib so the registry loads. proof-ledger does NOT need this (its block decision is self-contained, no registry), so the GATE works regardless; this is only so `contract` keeps working from the installed path.
- **Stable path = `$HOME/.claude/dwarves-kit`** (the bash-install root), as the `${CLAUDE_PLUGIN_ROOT:-...}` fallback. Plugin mode (CLAUDE_PLUGIN_ROOT set) is unchanged.
- **Did not touch the gate's block logic.** Only the lib RESOLUTION path moved; proof-ledger / classify / fresh-proof check are byte-identical.

## 2026-06-08 Verification

- `tests/test-meta.sh` 390/390 (new pin: install materializes lib/gate/proof-ledger.sh).
- End-to-end consumer-gate repro recorded in `docs/verification/SPEC-045.md`: lib-unreachable -> exit 0 (fail open, the bug); lib-via-install -> exit 2 (BLOCK, the fix) with the SPEC-044 type-aware message; proof added -> exit 0 (PASS).
- Cross-repo-session caveat (same as SPEC-044): driven from an ops-toolkit session, so validate/review run as adversarial sub-agents, not `/kit:*`.
