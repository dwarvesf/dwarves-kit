# `lib/`, kit engine helpers, grouped by subsystem

The kit's `lib/` scripts are call-by-path helpers (`bash "$DIR/x.sh"`, `$DIR`
resolved from the caller's own `BASH_SOURCE`). Claude Code's loader does not
depth-constrain `lib/`, so the files are grouped into subsystem subdirectories
for navigation. Orphans with no cluster stay at the root.

## Subsystems

| Dir | Files |
|---|---|
| `board/` | `board.sh` `board-mirror.sh` `board-writeback.sh` `parse-board.sh` `backlog.sh` |
| `queue/` | `orchestrate.sh` `queue.sh` `weekend-batch.sh` |
| `gate/` | `gate-ledger.sh` `proof-gate.sh` `proof-ledger.sh` `proof-table-gen.py` `proof-table-gen.sh` `dispatch-gate.sh` `quiz-gate.sh` `coverage-delta.sh` `verif-counts.sh` `mutation-smoke.sh` |
| `classify/` | `lane-classify.sh` `role-classify.sh` `significance-classify.sh` `task-type-classify.sh` `route-suggest.sh` |
| `spec/` | `spec-index.sh` `spec-next.sh` |
| `goal/` | `goal-drafts.sh` `goal-registry.sh` `mega-merge.sh` `stack-merge.sh` `handoff-gen` + `handoff/` (`handoff_gen.py`, `cc_compact.py`) |
| `telemetry/` | `lane-telemetry.sh` `kit-log-dir.sh` |
| `session/` | *(empty; reserved for the shared transcript parser)* |
| *(root)* | `adopt.sh` `explain.sh` `pitch.sh` `precedent.sh`, orphans, no cluster |

## Resolution scheme (why the symlinks exist)

Every `lib/` script resolves its own `$DIR` from `BASH_SOURCE` and calls its
siblings as `$DIR/<callee>.sh`. Moving a file into a subsystem dir changes its
`$DIR`, which would break two classes of caller. Both are covered by symlinks so
that **no call-site was edited** (strategy (b): per-subsystem shims):

1. **Root compatibility shims**, `lib/<name>.sh -> <subsystem>/<name>.sh` for
   every moved file. External callers (tests, hooks, commands, `install.sh`) that
   reference the old flat path `lib/<name>.sh` keep working, and any call chain
   whose entry runs at the root path resolves every sibling at the root shims.

2. **Cross-subsystem shims**, `lib/<caller-subsys>/<callee>.sh -> ../<callee-subsys>/<callee>.sh`.
   When a script is invoked at its real subsystem path (so `$DIR` is a subsystem
   dir), its cross-subsystem sibling calls resolve through a shim placed *inside*
   the caller's own subsystem dir. A shim at the old flat root would never be
   consulted here (the moved caller looks only in its new dir), this is the
   false-green the naive one-shim-at-root plan hits, and why these shims live in
   the subsystem dirs. The set is the transitive closure of each subsystem's
   cross-subsystem calls (e.g. `queue/gate-ledger.sh` also needs
   `queue/kit-log-dir.sh`, because `gate-ledger.sh` sources `kit-log-dir.sh`).

**Adding a file to a subsystem:** drop it in the subsystem dir, add a root
compat shim `lib/<name>.sh -> <subsystem>/<name>.sh`, and if it makes a
cross-subsystem sibling call, add the matching shim (and its transitive callees)
inside its subsystem dir.
