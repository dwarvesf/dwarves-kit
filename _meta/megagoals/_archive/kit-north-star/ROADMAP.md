# Mega-goal: kit-north-star

**Destination:** dwarves-kit routes EVERY kind of task (not just coding) through a right-sized loop: chat stays chat; tasks classify by type AND lane; non-code types (research / eval / compare / test-design / cleanup / doc) get their own defined loops with a designated or dynamic agent; the kit BACKLOG becomes a status-driven kanban an agent can pull from; every loop designs its tests FIRST in the dialect that fits its type and stores run records as proofs.
**Quality bar:** The kit takes its own medicine. Every sub-goal ships through the kit's lanes with recorded gates; spec statuses stay truthful; nothing phantom (no documented-but-unimplemented feature, the SPEC-039/040 lesson).
**Stacking tool:** gh (sequential: a dependent PR opens only after its parent merges)
**Started:** 2026-06-10
**Work repo:** `~/workspace/tieubao/dwarves-kit` (shared repo; never push master; one PR per sub-goal)

## Sub-goals

- [x] 01-north-star-doc, PHILOSOPHY.md §6 carries the three north-star criteria (N1 right-sized type loops, N2 pull-based kanban, N3 type-shaped test-first quality) in the doc's existing principle voice, PR #31
- [x] 02-type-loops, every task type in the registry has a defined loop (entry -> phases -> exit artifact -> proof shape) + an agent mode; WORKFLOW shows the type-loop table; assign/start route by type, PR #32
- [x] 03-backlog-kanban, kit BACKLOG rows carry a status state machine; a board view renders it; `assign --next` pulls + claims the top queued item, PR #33
- [x] 04-test-dialects, each work type maps to its test-design dialect; /kit:test-plan picks the dialect from the type; test-plan default-suggested for normal/full, PR #34
- [x] 05-dogfood, one real non-code task runs end-to-end: enqueued -> pulled -> type-loop -> dialect-shaped tests -> proof recorded -> board shows done, PR #35

## Dependencies

- 02 depends on 01 (the criteria doc is what 02's design traces to)
- 03 depends on 02 (board rows and pull routing key on the type registry)
- 04 depends on 02 (dialects key on the type registry)
- 05 depends on 02 + 03 + 04 (it exercises all three)

## Audit cheat sheet

Extract PR numbers and audit each (run in the dwarves-kit repo):

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
