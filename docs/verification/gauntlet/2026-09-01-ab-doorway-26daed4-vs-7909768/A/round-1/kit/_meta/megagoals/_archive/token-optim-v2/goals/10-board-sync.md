# SG-10: orchestrator board-view / kanban-sync mode

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: sonnet
Effort: medium

## Directional outcome
Let the orchestrator surface a mega-goal's sub-goal progress on a kanban board (reusing the
repo's existing `backlog.sh` + cockpit), so a human can watch the flow on a board instead of
only the ROADMAP checkboxes, WITHOUT making the board a second source of truth.

## Done =
`lib/orchestrate.sh` gains `--board=roadmap|kanban|both` (default: detect , if the repo has
kanban tooling, `both`; else `roadmap`). In `kanban`/`both` mode it renders the mega-goal's
sub-goals as a SEPARATE per-mega-goal board at `<megagoal-dir>/BOARD.md` via `lib/backlog.sh`.
Status is EVENT-SOURCED (borrowed from pi-swarm): the loop appends status events to a log and
the board is DERIVED by replay, never mutated in place (crash-safe + concurrent-append-safe).
States extend the kanban with `ready` (deps satisfied, workable now), `blocked(reason)`, and
`stalled` (a unit with no progress in N min). ROADMAP.md + the goal files stay canonical (the
board is a derived view; Done= never lives in a board row). `tests/test-orchestrate.sh` covers
detect, sync, the roadmap-only fallback, and the event-replay derivation. PR opened.

## Close the loop (verification)
```
bash tests/test-orchestrate.sh                              # board detect + sync + fallback
bash lib/orchestrate.sh run <fixture> --board=both --dry-run  # shows both surfaces; no repo BACKLOG touched
```

## Scope edges
`lib/orchestrate.sh` + its test + reuse of `lib/backlog.sh` as the renderer. Do NOT make the
board canonical (no Done=/close-the-loop in rows). Do NOT inject sub-goal rows into the repo-wide
`BACKLOG.md` (per-mega-goal `BOARD.md` only); the cockpit sees at most the one existing umbrella
row. Detection must fail safe to `roadmap` when no kanban tooling is found.

## Where to look
`lib/orchestrate.sh` (#81), `lib/backlog.sh` (kanban format + states), the cross-repo cockpit
`_meta/board-all` + `_meta/boards.txt` (ops-toolkit CLAUDE.md "Cross-repo kanban cockpit"), the
2026-06-29 board-sync discussion. Canonical decision: goal-files/ROADMAP are the contract; the
board is a view-sync (Han, 2026-06-29, "your call").

## Proof expectation
A run-table, plus a sample rendered `BOARD.md` and a `--board=both --dry-run` capture showing
both surfaces in sync while the repo BACKLOG is untouched. Full reviewable proof (behavioral).

## PR body
feat(kit): orchestrator board-view / kanban-sync mode , render a mega-goal as a per-mega-goal
kanban via backlog.sh, ROADMAP stays canonical. Gated for team review.

## Borrowed from pi-swarm (2026-06-29)
- Event-sourced status (derive by replay, never mutate) <- `task-store/events.ts`. The biggest
  robustness upgrade: a crashed/concurrent session cannot corrupt an in-place checkbox.
- States `ready` / `blocked(reason)` / `stalled` <- `queries.ts:154/167` (`ready` = deps done;
  `stalled` = no progress in N min).
- Status-icon row renderer `todo ○ -> in_progress ● -> done ✓` <- `render-status.ts`.
See `research/2026-06-29-pi-swarm-comparison.md`.

## From the token-efficient note (2026-06-29)
State-format tamper-resistance: models edit/overwrite JSON less freely than Markdown, and the
initializer pattern restricts WHICH field an agent may change (e.g. only `passes`) with a strong
"do not delete/edit" instruction. Our event-sourced status (derive, never mutate) is stronger
still, but consider a restricted-field JSON for the machine-read state if the MD board proves
tamper-prone. See `research/2026-06-28-token-efficient-design.md` Part 4.3.
