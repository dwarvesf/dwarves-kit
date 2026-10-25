# Implementation notes: guides-pieces

## Decisions the brief did not settle
- Dropped the "exit criterion" claim from the old mega-goal guide. `commands/mega.md` names no exit-criterion check; the close is the advisor review plus a gated final PR and `RUN_REPORT.md`. Kept as nothing, not softened.
- Dropped "build, then merge IS the terminus" detail and other mega internals (consolidate mode, harness routing). They are command reference, not a guide task.
- Fixed the debug phase list: the old guide showed phase 0 as "reproduce" and phase 1 as "evidence ledger". The command defines phase 0 as the feedback loop, 1 root cause, 2 pattern analysis, 3 hypothesis, 4 implementation.
- The old debug guide said the ledger is not committed because `.claude/` is ignored by default. That holds only for this repo's `.gitignore`, so the guide now says to check your own.
- `docs/guides/README.md` is not in my slice. I removed the dispatch-vs-mega row and widened the mega-goal row (one-line repoint, as the brief allows).
- `grill.md` writes docs/QUALITY.md without backticks: the file does not exist here (the kit creates it on first use), and the Tier 1 path scan flags a backticked dead path.

## Sample output
- Dispatch gate lines and the debug and grill ledger lines come from runs in temp repos. The mega plan lines come from `orchestrate.sh run <dir> --dry-run` on a sample roadmap.

## Source discrepancy found, not fixed (not my file)
- `commands/dispatch.md` says `dispatch-gate.sh plan` exits non-zero with REJECT for a spec without `## Touches`. Real behavior: `plan` exits 0 and prints `WAIT` for it; only `dispatch-gate.sh disjoint` prints REJECT (exit 2). The guide says both without claiming an exit code.

## Open
- Figures `several-pieces`, `execute` and `debug` are embedded by id; the Tier 1 path scan reports them dead until the figure PR lands.
