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

## Scenario pack additions (SPEC-227, same branch)

| Check | Command | Exit | Result | Verdict |
|---|---|---|---|---|
| J3 checker rejects an untouched fixture (negative control) | `check-submission-user-J3.sh <plain fixture>` | 1 | `SUBMISSION: RED` (spec, feature, tests, PR.md all FAIL as they should) | PASS (checker can fail) |
| J3 checker honors the honest-stop shape | same, with `BLOCKED.md` present | 3 | prints the block reason, exit 3 | PASS |
| Tier 1 still green after the additions | `bash tests/gauntlet/tier1.sh` | 0 | `TIER1: GREEN` | PASS |
| Lint | `shellcheck check-submission-user-J3.sh` | 0 | clean | PASS |

Green-path run of the J3 checker (against a hand-built passing fixture) is
SPEC-227 P3's own verification, deferred to the make-card task by design; the
negative controls above prove the checker's failure behavior today. Rollback:
the scenario pack is additive files only; reverting the commit restores the
prior prep with no state to unwind.

## Not run here

The clean-room build (`cleanroom/run.sh`) and the probe rounds themselves: those
are the gauntlet RUN, scheduled with the operator (persona A first). This proof
covers the prep artifacts only.
