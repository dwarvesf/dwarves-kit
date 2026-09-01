# Sub-goal 02: type-loops

**Time budget:** 3-6 hours of loop work, after PR-01 merges
**Depends on:** 01
**Branch:** `feat/north-star-02-type-loops` (dwarves-kit)

## Outcome

Every work type the kit can classify has a DEFINED right-sized loop, written down where the machinery already lives:

- `docs/verification/task-types.md` (the type registry) gains two columns per type: **loop** (entry command/skill -> phases -> exit artifact, sized to the type's weight) and **agent** (preassigned: a named subagent or owning skill; or dynamic: persona/profile selected at dispatch). The six existing types (eval, research, doc, migration, data-tool, spec-feature) all get filled; spec-feature's loop = the existing lane table (pointer, not a copy).
- `WORKFLOW.md` gains a compact **"Type loops"** table as a sibling of "Size the work first" (lanes answer "how risky" for code; type loops answer "what cycle" for non-code). Example shapes: research = frame -> sweep -> verify claims -> cited report; eval = the tool-eval-experiment ladder -> TEST-REPORT; cleanup/migration = inventory -> classify conform/drift -> migrate -> reference-fix -> gate check.
- `/kit:assign` and `/kit:start` route by type: when `task-type-classify` says non-spec-feature, the goal draft / suggestion names the type's loop and agent mode instead of silently assuming the code cycle.

This is the SDD trace of north-star N1. Existing prior art to mine, not reinvent: `lib/task-type-classify.sh` precedence rules, ops-toolkit `tool-eval-experiment` skill (eval loop already exists there), the `/kit:migrate-convention` idea (ops-toolkit BACKLOG row, 2026-06-10) which IS the cleanup loop.

## Quality bar

A maintainer reading WORKFLOW.md sees ONE coherent intake: classify type -> if code, pick lane -> else run the type's loop. No type answers "shrug, just chat". No loop is ceremony for ceremony's sake: a research task's loop fits a research task.

## How to close the loop

```sh
cd ~/workspace/<owner>/dwarves-kit
# every type row carries a loop + agent entry:
awk '/^\|/' docs/verification/task-types.md | grep -c ' -> '   # >= 5 (loop arrows per non-pointer row)
grep -c 'Type loops' WORKFLOW.md                                # >= 1
grep -c 'task-type' commands/assign.md                          # >= 1 (routing wired)
bash tests/test-meta.sh && bash tests/test-hooks.sh             # all green incl. new pins
bash lib/lane-classify.sh classify "define per-type loops in the task-type registry and wire assign/start routing"  # likely full (kit-machinery); run that lane's gates via lib/gate-ledger.sh
```

**Done =** all six types have loop + agent defined in the registry, WORKFLOW shows the type-loop table, assign/start route by type, new meta pins exist and the suites are green, PR open + CI green.

## Scope edges

**In:** task-types.md, WORKFLOW.md, commands/assign.md, commands/start.md, tests, a SPEC under docs/specs/ (next free number), CHANGELOG/BACKLOG rows.
**Out:** lane machinery (lane-classify.sh stays untouched); BACKLOG status states (that is 03); test dialects (that is 04).
**Not:** new per-type slash commands (the loop names EXISTING commands/skills); a persona-selection engine (the registry records the agent MODE only; dynamic selection mechanics are a future SPEC); rebuilding tool-eval-experiment inside the kit (point at it).

## Where to look

The type registry + classifier (`docs/verification/task-types.md`, `lib/task-type-classify.sh`); WORKFLOW's lane intake section; assign/start command prose; ops-toolkit's tool-eval-experiment skill for the eval loop shape.

## PR body

> Realizes north-star N1 (PHILOSOPHY §6): every work type gets a defined right-sized loop. Type registry gains loop + agent columns; WORKFLOW gains the Type-loops table beside the lane table; /kit:assign + /kit:start route non-code types to their loop. No new commands; existing skills/commands are the loop bodies. Verify: see "How to close the loop" in ops-toolkit `_meta/megagoals/kit-north-star/goals/02-type-loops.md`. Depends on PR-01 (the criteria doc).

## Notes

