# Implementation notes -- mega-tick-verb

Delta from `docs/specs/SPEC-430-mega-tick-verb.md` (APPROVED, round 3). The spec text is unchanged; everything that differs or adds detail is here.

## Final-round reviewer warnings, and what the build does with them

- NC37 (the TICK_OLD compare) is listed under TASK-003 in the build, with C51 in the same suite section, not TASK-004.
- C43 sets `FLIP_LOCK_STALE_SECS=0` before calling `orchestrate.sh _lock_stale`, so the pid check is the only thing that keeps the lock fresh.
- TASK-005's check covers `lib/README.md` as well: `rg -n 'mega tick' lib/mega/README.md lib/README.md docs/WORKFLOW.md`.
- The lock pid file is validated as `^[0-9]+$` before `kill -0`. Anything else counts as "no pid": the lock is held, and exit 7 follows after the wait.
- The pid is read a second time just before a dead-lock move-aside. The move happens only when both reads agree, so a driver that reclaimed and re-took the lock in between is left alone.
- Moved-aside pid files and temp files get `mktemp` names under `${TMPDIR:-/tmp}` (`mega-tick-pid.XXXXXX`, `mega-tick-tmp.XXXXXX`), never `$$.$RANDOM`.
- The `--branch-override` reason is printed on stderr too (`mega tick: branch-override <goal> != <head>: <reason>`), besides the AUDIT line.
- The C47 gh stub logs only `GH_PROMPT_DISABLED` from the environment, never the whole env.
- The usage text marks `MEGA_TICK_TEST` and `MEGA_TICK_TEST_PAUSE_FILE` as test-only.
- The step [7] primary-PR compare applies to done-box lines only. An open target line's own prose `PR #N` is not compared. Case C52 covers an open target line that cites another PR (`- [ ] 52-cites-other, see PR #37, PR #`, ticked with PR 48).
- The flowchart step [1] label covers the override reason as well as the note (both exit 3 on a control character or over 200 bytes).
- `_tick_branch_norm` is in the unit list (it is its own function).
- `.orchestrate/` is kept after the lock is released, on purpose. The driver owns that dir and keeps state in it.
- `_tick_lock` carries a comment that it mirrors `orchestrate.sh` `_lock` / `_lock_stale` / `_lock_reclaim` / `_unlock` (lines 336 to 393) and must change with them.
- C39 bound: `MEGA_TICK_LOCK_WAIT_SECS=0.4` gives 2 polls of 0.2 s, and the case asserts the run ends within 5 s wall time (generous for a loaded host).

## Build decisions

- `_tick_branch_norm` trims whitespace once more, before the ` (...)` strip as well as after it, so a value like `ci/x (existing)  ` (trailing spaces after the paren) still normalizes. The spec's order is otherwise kept: CR, group, trim, backticks, trim.
- The control-character check compares byte counts before and after `LC_ALL=C tr -d '\001-\037\177'`. A grep-based check would miss an embedded newline, because grep is line based.
- gh's stderr is captured to a `mktemp` file that is removed after reading. bash cannot capture stdout and stderr separately without a file.
- PR fields are read with `jq -j` (no trailing newline added), so an injected trailing newline still trips the control-character check instead of being stripped by `$( )`.
- A missing ROADMAP.md is exit 8, the same as "not a regular file" (spec: "must be a regular file ... else exit 8").
- `attempt-state.sh` is invoked as `bash "$ATTEMPT_STATE_BIN"`, so a stub only needs to be a bash script, not executable.
- `mega.sh` now runs `main` only when executed (the `attempt-state.sh` guard), so tests and TASK-001's check can source it. No caller sourced it before.
