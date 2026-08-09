---
name: auto-queue-watcher-pilot
description: The #auto backlog-row + queue-watcher mechanism (SPEC-217) was proven twice, unattended, on ID-463 and ID-309; two known bugs are still unfixed.
metadata:
  type: project
---

`bin/queue watch --apply` (tag a queued board row `#auto` plus a
`#queue{repo=,pointer=}` token, point it at a `.claude/goals/<slug>.md` file)
shipped as SPEC-217 back on 2026-07-31 but had never actually been run before
2026-08-01/02. Two small, well-scoped rows went through it end to end: real
diagnosis, real fix, real tests, a real draft PR, each checked by hand
afterward with an independent negative control before merge (ID-463: PR #342,
a test-suite `$HOME`-sandboxing bug; ID-309: PR #344, the board-sync
id-collision guard). Both held up.

Two mechanism bugs surfaced, still unfixed:

- The `/goal` submit sometimes lands in the input box but never actually
  sends, the launched session sits idle with the goal text unsubmitted.
  Reproduced twice in a row on ID-309's run; a single manual `Enter` sent to
  the tmux window unstuck it both times. `_mux_submit`'s retry-detection
  (`lib/queue/queue.sh`) checks for a literal `❯ /goal` at the prompt, which
  can miss a long single-line paste that renders with only its tail visible.
- Fixed prompt overhead (the XPIA preamble + the EXIT_SIGNAL/draft-PR
  suffixes `_goal_line` appends) eats roughly 1500 of `/goal`'s 4000-char
  budget, leaving well under 2500 chars for the actual pointer content, with
  no pre-flight check or truncation. A slightly-too-long pointer silently
  strands the row: no journal entry, no error, just an idle session.

Both pilot rows ran directly against the operator's main checkout (the
dirty-tree + on-default-branch guards make a side worktree structurally
impossible to use here), so treat the main checkout as a shared, sometimes
busy resource, not an isolated pilot sandbox.

Parked while Han works the gauntlet, tech generation, and mega-goal workflow
instead. Revisit to fix the two bugs above, or to widen the pilot to more
rows, once that other work settles.
