# `lib/`, kit engine helpers, grouped by subsystem

The kit's `lib/` scripts are call-by-path helpers (`bash "$DIR/x.sh"`, `$DIR`
resolved from the caller's own `BASH_SOURCE`). Claude Code's loader does not
depth-constrain `lib/`, so the files are grouped into subsystem subdirectories.
Each real file lives in exactly ONE place, its subsystem dir; there are **no
alias symlinks** (`find lib -maxdepth 1 -type l` is empty). Single-purpose
orphans with no cluster stay as bare scripts at the root.

## Subsystems

| Dir | Files |
|---|---|
| `board/` | `board.sh` `board-mirror.sh` `board-writeback.sh` `parse-board.sh` `backlog.sh` |
| `queue/` | `orchestrate.sh` `queue.sh` `weekend-batch.sh` |
| `gate/` | `gate-ledger.sh` `proof-gate.sh` `proof-ledger.sh` `proof-table-gen.py` `proof-table-gen.sh` `dispatch-gate.sh` `quiz-gate.sh` `coverage-delta.sh` `verify-counts.sh` `mutation-smoke.sh` |
| `classify/` | `lane-classify.sh` `role-classify.sh` `significance-classify.sh` `task-type-classify.sh` `route-suggest.sh` |
| `spec/` | `spec-index.sh` `spec-next.sh` |
| `goal/` | `goal-drafts.sh` `goal-registry.sh` `mega-merge.sh` `stack-merge.sh` `handoff-gen` + `handoff/` (`handoff_gen.py`, `cc_compact.py`) |
| `telemetry/` | `lane-telemetry.sh` `kit-log-dir.sh` |
| `session/` | `parse_transcript.py` `parse-transcript.sh` (the shared transcript parser + its tests) |
| *(root)* | `adopt.sh` `explain.sh` `pitch.sh` `precedent.sh`, orphans, no cluster |

## Resolution scheme (the `LIB_ROOT` anchor, no shims)

Every `lib/` script resolves its own dir from `BASH_SOURCE` (`SELF_DIR`) and,
when it needs a cross-subsystem sibling, computes ONE anchor:

```sh
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"   # the lib/ dir
```

- **Same-subsystem** sibling  ->  `"$SELF_DIR/<callee>.sh"` (the real file sits
  right beside the caller).
- **Cross-subsystem** sibling  ->  `"$LIB_ROOT/<callee-subsystem>/<callee>.sh"`
  (e.g. `queue/orchestrate.sh` calls `"$LIB_ROOT/gate/gate-ledger.sh"`).
- **Repo-root** file (WORKFLOW.md, docs/, _meta/)  ->  `"$LIB_ROOT/.."` (two
  levels above a `lib/<subsystem>/` script). A bare root orphan (`pitch.sh`,
  `precedent.sh`) sets `LIB_ROOT="$SELF_DIR"` since its own dir already IS `lib/`.

There are NO alias symlinks and NO dispatcher; the anchor is the whole mechanism.
External callers (hooks, commands, tests, `install.sh`) reference the real
subsystem path `lib/<subsystem>/<name>.sh` directly.

**Adding a file to a subsystem:** drop it in the subsystem dir. If it makes a
cross-subsystem sibling call, reference it as `"$LIB_ROOT/<subsystem>/<name>.sh"`
(add the `LIB_ROOT` line if the script does not have one yet). Nothing else, no
shim to register.
