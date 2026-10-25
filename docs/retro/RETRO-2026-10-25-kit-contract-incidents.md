# Retro: kit-contract incident stories
Date: 2026-10-25
Source: moved out of `docs/kit-contract.md`, which keeps the rules. The incidents date from 2026-07-14 to 2026-07-17.

## What the negative-control discipline caught (2026-07-14)

In one afternoon the discipline caught, in this order:
- the `rg`-on-CI vacuous pass;
- a lint that flagged its own fixture;
- C1 blind to `os.environ.get('X')` in single quotes, to `os.environ["X"]`, and to a bare `export X=`;
- C6 blind to every extensionless executable, which is the kit's own house style, so it was blind to most of the kit;
- C7 blind to `rg "pat" file` with no flag;
- C5 fooled by a bespoke writer that name-dropped the renderer in a comment;
- a module-scope definition under which C3/C4 examined 3 of the kit's 12 modules while reporting green.

Every one of those was found by a review lens re-planting the violation differently, not by the suite itself.

## Three agents in one checkout (2026-07-15)

Three agents were dispatched into the SAME checkout to close three doc gaps in parallel. Git branches share a working tree, so within minutes:
- HEAD had been switched out from under two of them;
- one agent's commit landed on another's branch;
- the contract test flapped red from a half-built scaffold that was not its own;
- `git .../index.lock` collisions appeared in the session's own telemetry.

Both agents detected the collision and untangled it with plumbing (`commit-tree`, an atomic ref update) without destroying anything. That recovery was luck plus care, not design.

During the same fan-out an agent recorded one contract run at `23 passed, 1 failed` and could not reproduce it in 15 subsequent runs; the lead could not in 10 more. The most plausible cause is not a flaky lint: the run read the tree while another writer was mid-edit.

Rule kept in `docs/kit-contract.md`: one worktree per writer.

## A commit that lost its files (2026-07-17)

A conductor's staging ran inside an `&&` chain where an innocent `grep -c` (zero matches, exit 1) broke the chain BEFORE `git add`. The commit sailed through with only the auto-staged `git mv` rename. The PR merged looking healthy, and the exit-discard silently destroyed the three files that were the actual point of the change.

Rule kept in `docs/kit-contract.md`: check `git show --stat HEAD` before discarding a worktree; never put `git add` or `git commit` downstream of a command whose nonzero exit is informational.
