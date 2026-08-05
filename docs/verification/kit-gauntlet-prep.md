# Proof of done: kit gauntlet prep (tests/gauntlet/)

Behavioral claim: the kit's own gauntlet Tier 1 suite runs green on the current
tree, goes red when a surface artifact disappears, and the prep scripts lint
clean.

## Run table (2026-08-06, worktree kit-gauntlet-prep)

| Check | Command | Exit | Result | Verdict |
|---|---|---|---|---|
| Tier 1 green | `bash tests/gauntlet/tier1.sh` | 0 | 15 PASS (docs presence, onboard-detect, full adopt cycle on a throwaway fixture incl. idempotent re-adopt, tests/test-adopt.sh, shellcheck) -> `TIER1: GREEN` | PASS |
| Negative control, break | `mv commands/gauntlet.md` away, rerun | 1 | `FAIL doc: commands/gauntlet.md` -> `TIER1: RED` | PASS (suite can fail) |
| Negative control, restore | restore the file, rerun | 0 | `TIER1: GREEN` | PASS |
| Lint | `shellcheck tests/gauntlet/*.sh tests/gauntlet/cleanroom/run.sh` | 0 | clean | PASS |

## Not run here

The clean-room build (`cleanroom/run.sh`) and the probe rounds themselves: those
are the gauntlet RUN, scheduled with the operator (persona A first). This proof
covers the prep artifacts only.
