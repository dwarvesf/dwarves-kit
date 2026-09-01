# Proof of done: sync identity guards (cross-row corruption + renumber orphaning)

Two defects in the same identity model, shipped together.

**Defect 2, renumber orphaning (ops-toolkit ID-655).** The link map is keyed by
board id, so renumbering a linked row strands its entry under a dead id. The row
then reads as unlinked and the next tick creates a SECOND spoke card for the same
work. The two idempotency namespaces live apart (the filer's own key versus
`bls-<bid>`), so the spoke side can never catch it: a broken link that looks like
a missing one. Found on the personal board, where a vps-mon incident card adopted
as ID-629 was renumbered to ID-634 to resolve a real id collision, and the next
sync minted `ID-634 · [vps-mon] CRIT heartbeat-silent on air.upgrade-check`
alongside the original. Fix reconciles on the row text, which a renumber does not
change, and declines when more than one unmapped row carries it.

**Defect 1, cross-row title corruption.** Root-cause fix for the 2026-09-01
dfoundation board scramble: DF-310/311/312 titles rotated against their notes, identically on two machines syncing one Reminders list. Mechanism: `build_state`'s prefix adoption lacked the `titles_agree` check the link path has, so a mispaired spoke item was adopted with the board's title as snap-truth; the next sync read the spoke text as a retitle and `board_edit_item` overwrote the board row. A 2026-08-16 worktree sync's 180-row cross-board fossil state map seeded the poisoned pairings.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `uv run --with pytest pytest lib/sync/tests/` | 0 | PASS 248/248 (4 new: mispaired adoption refused; rotation guard board-wins; genuine retitle still flows; worktree fence refusal) |
| 2 | `uvx pytest lib/sync/tests/` (after the renumber fix) | 0 | PASS 250/250 (2 new: renumbered row relinks instead of minting a duplicate; ambiguous match declines to relink) |

## Negative control

Defect 1. Fault injected: removed the `titles_agree` gate from `build_state`'s adoption loop. Result: `FAILED test_core.py::test_build_state_refuses_mispaired_prefix_adoption` (1 failed, 37 passed in test_core.py). Restored; full suite green (run #1).

Defect 2. Fault injected: reverted the rename-reconciliation hunk in `plan_sync`'s map-seeding loop to its pre-fix form, leaving the test file untouched. Result: `FAILED test_core.py::test_renumbered_row_relinks_instead_of_minting_a_duplicate` (1 failed, 39 passed in test_core.py), asserting on `creates(p)` holding `ID-10`. Restored via `git checkout --`; full suite green at 250/250, working tree clean.

The regression test deliberately uses a card with no `ID-NNN ·` prefix, because that is how a sensor-filed card looks and it is precisely why prefix matching cannot recover the stranded link.

## Reproduce

```bash
uv run --with pytest pytest lib/sync/tests/
```

## Remediation note (estate-side, not this repo)

For defect 2, one duplicate card survives on the personal Hermes board:
`t_e8340706` (`ID-634 · [vps-mon] CRIT heartbeat-silent on air.upgrade-check`),
alongside the original `t_bde41a05`. The fix stops new duplicates and relinks the
row to the surviving card, but it does not retire a card already created. Left in
place deliberately, pending Han's call on how to close it. `ID-651`
(growatt-datalogger) is part way through the same adoption path and is now safe.

For defect 1, the poisoned artifacts remain outside this repo: the dfoundation Reminders list still holds mispaired titles, and both machines' `~/.cache/backlog-sync/.../reminders.state.json` snapshots recorded them. With these guards a re-sync no longer writes them to the board (id-collision notes surface instead); healing = re-title the reminders from board truth (the engine's board-wins conflict path does this once linked) and quarantine the 2026-08-16 worktree fossil state dir. Tracked as ops-toolkit ID-639.
