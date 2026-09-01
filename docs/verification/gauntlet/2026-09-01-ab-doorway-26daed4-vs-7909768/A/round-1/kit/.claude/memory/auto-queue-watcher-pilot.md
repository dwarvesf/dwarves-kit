---
name: auto-queue-watcher-pilot
description: The #auto backlog-row + queue-watcher mechanism (SPEC-217) went 4-for-4, unattended, across ID-463/ID-309/ID-466/ID-467; both mechanism bugs (submit glitch, char budget) are fixed.
metadata:
  type: project
---

`bin/queue watch --apply` (tag a queued board row `#auto` plus a
`#queue{repo=,pointer=}` token, point it at a `.claude/goals/<slug>.md` file)
shipped as SPEC-217 back on 2026-07-31 but had never actually been run before
2026-08-01. Four small, well-scoped rows have gone through it end to end since:
real diagnosis, real fix, real tests, a real draft PR, each checked by hand
afterward with an independent negative control before merge (ID-463: PR #342,
a test-suite `$HOME`-sandboxing bug; ID-309: PR #344, the board-sync
id-collision guard; ID-466: PR #366, a test-plan-coverage advisory at the
ship gate; ID-467: PR #369, the test-meta self-heal + doc-count drift). All
four held up.

One mechanism bug is fixed, one remains:

- FIXED (PR #368): the `/goal` submit used to land in the input box but never
  actually send, reproduced on 3 consecutive live runs. `_mux_submit`'s
  retry-detection matched a literal `❯ /goal` at the prompt, which missed a
  long single-line paste rendering with only its tail visible. Detection is
  now "any prompt line still carries content"; ID-467 ran with zero manual
  touches, confirming the fix live.
- FIXED (PR #371): fixed prompt overhead (the XPIA preamble + the
  EXIT_SIGNAL/draft-PR suffixes `_goal_line` appends) eats roughly 1500 of
  `/goal`'s 4000-char budget, and an over-budget pointer used to silently
  strand the row. `QUEUE_GOAL_CHAR_LIMIT` (default 4000) is now pre-flighted
  before any window opens; an oversized pointer journals `error` with the
  reason named. Keep pointers under roughly 2400 chars anyway: the margin is
  what the suffix overhead leaves.

All four pilot rows ran directly against the operator's main checkout (the
dirty-tree + on-default-branch guards make a side worktree structurally
impossible to use here), so treat the main checkout as a shared, sometimes
busy resource, not an isolated pilot sandbox. The "3 pre-existing failing
negative controls" finding (ID-468) resolved as state pollution, not test
rot: the suite sandboxed its journal but not its beat/status/guard files, so
leaked counters in the real `~/.local/state` crossed the runaway-breaker trip
and rewrote the expected `stalled` verdict, machine-local only. Fixed by
sandboxing `KIT_LEDGER_DIR` in the suite (PR #372). Lesson worth keeping: a
"pre-existing failure identical on master" can still be an environment
artifact of THIS machine; check the state dirs a suite touches before filing
it as code rot.
