# SPEC-086: Stop-hook source-file scan cost (prune + bound + lock it in)

Status: VALIDATED
Date: 2026-06-19
Lane: full (classified: full, kit-machinery hook behavior change)
Type: bug-fix / perf + regression test
Board: ID-086 (incident: Air ran hot, load 13.6 on a 10-core)

## Problem

`slop-cleaner.sh` (Stop, advisory) and `session-state-save.sh` (Stop, convenience)
each enumerate source files modified since session start with:

```sh
find . \( -name "*.ts" ... \) -newer /tmp/.dwarves-kit-session-start \
  | grep -v node_modules | grep -v vendor | grep -v dist
```

The `grep -v` filters the *output*, but `find` has already walked the entire
tree first: every `node_modules`, every nested `.git`, build outputs, and (on a
mixed workspace) an Obsidian vault's `.smtcmp_*` vector DBs and `.claude/worktrees/`
full checkouts. These are **Stop hooks**: they fire on every turn-end, not once
per session. Measured on a ~25-repo workspace root: **13.1s of system CPU, 4.6s
wall, per scan**. With N concurrent Claude sessions all ending turns, the scans
saturate the cores. Observed live: 8 simultaneous `find` processes at ~80% CPU,
load average 13.58 on a 10-core M4, the laptop hot to the touch.

This pattern was **already diagnosed and fixed once** in `context-readiness.sh`
(SessionStart), whose inline comment reads: "prune the heavy dirs DURING
traversal (not grep -v after, which still descends into them and cost ~4s cold
on a big repo)." The fix was never propagated to the two Stop hooks, and no test
locked it in. **The recurrence vector is fix-drift across hooks.**

Two residual issues surfaced in the same investigation:

1. **Blast radius is unbounded outside a repo.** Pruning bounds per-dir cost but
   `find .` from a non-repo cwd (a session at `$HOME`, or a multi-repo workspace
   root) still walks an arbitrarily large tree. These hooks reason about a coding
   session in a repo; outside one there is nothing meaningful to scan.
2. **`slop-cleaner.log` grows unbounded** (one appended line per detection, never
   rotated). Out of scope here (disk, not the heat); tracked as a follow-up.

## Decision

Three changes to **each** of `slop-cleaner.sh` and `session-state-save.sh`:

1. **Prune heavy dirs during traversal**, replacing the post-filter `grep -v`.
   Prune list is the superset that matters in practice (the sibling
   `context-readiness.sh` pruned only `node_modules .git .venv .cache`; the Stop
   hooks need more because `.claude/worktrees/` and a vault's `.obsidian` /
   `.smtcmp_*` are the heavy dirs on a mixed workspace):
   `node_modules vendor dist .git target build .venv __pycache__ .obsidian .claude .smtcmp_*`.
2. **Git-work-tree guard.** Skip the scan entirely when not inside a git work
   tree (`git rev-parse --is-inside-work-tree`). `slop-cleaner` exits 0;
   `session-state-save` records `none` and still writes the rest of its state.
   This bounds the `$HOME` / workspace-root case that pruning alone cannot.
3. **Overridable marker path** via `DWARVES_KIT_SESSION_MARKER`
   (default `/tmp/.dwarves-kit-session-start`, production behavior unchanged).
   Purely to make the scan testable in isolation without touching the shared
   real marker, mirroring the existing `DWARVES_KIT_LOG_DIR` pattern.

`context-readiness.sh` already prunes and fires only once per session (SessionStart),
so it is not the per-turn heat amplifier and is left unchanged; its narrower prune
list is adequate for its count-only purpose.

## Acceptance criteria

- AC1: neither Stop hook descends into pruned dirs. Falsifiable canary: a changed
  source file under `build/` (covered by the new prune, NOT by the old
  `grep -v node_modules|vendor|dist`) is absent from the hook's reported set.
  NC: revert to grep-after-find and the canary reappears.
- AC2: a genuinely changed top-level source file IS still reported (the scan works).
- AC3: outside a git work tree, neither hook scans (slop-cleaner emits no nudge;
  session-state records `none`). NC: a bloated file in a non-repo dir is not reported.
- AC4: marker path honors `DWARVES_KIT_SESSION_MARKER`; default unchanged.
- AC5: `bash tests/test-hooks.sh` green; the new assertions live in that suite.

## Test plan

Regression assertions added to `tests/test-hooks.sh` (per CONTRIBUTING), in the
existing `slop-cleaner.sh` section plus a new `session-state-save.sh` section.
Each runs the real hook in a throwaway git repo with a temp marker:

- prune canary: `build/canary.py` newer than marker -> absent from output (AC1).
- positive: `touched.py` at repo root newer than marker -> present (AC2).
- guard: same fixture in a non-git temp dir -> no scan (AC3).
- marker override: `DWARVES_KIT_SESSION_MARKER` points at the temp marker (AC4).

Whole-tree CPU-descent (the 13s -> 0.9s win) is verified by benchmark in the
proof-of-done, not the unit suite (timing is flaky in CI); the canary locks the
prune-not-grep *contract* that produces it.
