# tiered-verification: implementation notes

Spec: `docs/specs/SPEC-421-tiered-verification.md` (revision 3). Only deltas from the spec.

## Build delta

### Decisions and changes
- D1. The build worktree is `.claude/worktrees/tiered-verification-build`, made with a hand `git worktree add -b feat/tiered-verification`. `wrap start` refused: the spec branch's own worktree already holds `.claude/worktrees/tiered-verification`, and `wrap start` derives the directory from the branch slug. The branch name still gives the rid `tiered-verification`.
- D2. The golden is captured by `tests/lib/orchestrate-golden.sh` (dry-run plan plus `_wave_converge` console, events and hook argv for three cases) and committed before any `orchestrate.sh` edit. It pins config to an empty layer and `--board=roadmap`, so a later `kit.toml` default cannot move it.
