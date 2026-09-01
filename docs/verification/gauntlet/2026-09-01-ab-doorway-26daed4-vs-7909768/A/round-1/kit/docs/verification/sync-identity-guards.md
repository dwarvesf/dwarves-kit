# Proof of done: sync identity guards (cross-row title corruption)

Root-cause fix for the 2026-09-01 dfoundation board scramble: DF-310/311/312 titles rotated against their notes, identically on two machines syncing one Reminders list. Mechanism: `build_state`'s prefix adoption lacked the `titles_agree` check the link path has, so a mispaired spoke item was adopted with the board's title as snap-truth; the next sync read the spoke text as a retitle and `board_edit_item` overwrote the board row. A 2026-08-16 worktree sync's 180-row cross-board fossil state map seeded the poisoned pairings.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `uv run --with pytest pytest lib/sync/tests/` | 0 | PASS 248/248 (4 new: mispaired adoption refused; rotation guard board-wins; genuine retitle still flows; worktree fence refusal) |

## Negative control

Fault injected: removed the `titles_agree` gate from `build_state`'s adoption loop. Result: `FAILED test_core.py::test_build_state_refuses_mispaired_prefix_adoption` (1 failed, 37 passed in test_core.py). Restored; full suite green (run #1).

## Reproduce

```bash
uv run --with pytest pytest lib/sync/tests/
```

## Remediation note (estate-side, not this repo)

The poisoned artifacts remain outside this repo: the dfoundation Reminders list still holds mispaired titles, and both machines' `~/.cache/backlog-sync/.../reminders.state.json` snapshots recorded them. With these guards a re-sync no longer writes them to the board (id-collision notes surface instead); healing = re-title the reminders from board truth (the engine's board-wins conflict path does this once linked) and quarantine the 2026-08-16 worktree fossil state dir. Tracked as ops-toolkit ID-639.
