# Sub-goal 03: backlog-kanban

**Time budget:** 3-6 hours of loop work, after PR-02 merges
**Depends on:** 02
**Branch:** `feat/north-star-03-kanban` (dwarves-kit)

## Outcome

The kit BACKLOG behaves like a kanban board while staying a markdown file:

- **State machine.** Each `_meta/BACKLOG.md` row carries a Status from a documented set: `queued -> claimed -> in-progress -> in-review -> done`, plus `blocked` and `parked` side-states. The BACKLOG header documents the states and legal transitions. Existing rows are migrated to honest states (most are `done`-equivalent already).
- **Board view.** A `lib/` helper (e.g. `lib/backlog.sh board`) renders the kanban columns from the file (status -> list of ID + title), and `lib/backlog.sh set <ID> <status>` flips a row's state mechanically (so flips are scriptable + testable, not hand-edits). `/kit:start` shows the board (or its summary counts) when the repo has queued items.
- **Pull mode.** `/kit:assign --next` takes the top `queued` item (document the priority rule: top-to-bottom file order is the queue), claims it in the cross-session goal-registry (machinery exists: `lib/goal-registry.sh`), flips it to `claimed`, and proceeds with the existing assign flow (type routing from 02 included).
- **Coexistence + minimum infra.** Operator-named work (`/kit:assign ID-NNN`) keeps working unchanged. No daemon, no cron, no auto-trigger: autonomous pulling is explicitly out (NOTES.md Proposed-additions material), per the minimum-infra default.

This is the SDD trace of north-star N2.

## Quality bar

A returning maintainer answers "what is queued, what is moving, what is stuck" from one board render, without reading row prose. A pull is one command, and two sessions cannot claim the same item (the goal-registry already guards this; reuse it, do not reinvent).

## How to close the loop

```sh
cd ~/workspace/tieubao/dwarves-kit
bash lib/backlog.sh board                                   # renders columns, exit 0
# fixture round-trip on a temp copy: queued -> claimed -> done flips mechanically:
bash tests/test-hooks.sh                                    # includes new backlog state tests
grep -c 'queued' _meta/BACKLOG.md                           # >= 1 (states live in the real file)
grep -qF -- '--next' commands/assign.md && echo wired       # pull mode documented
bash lib/lane-classify.sh classify "add a status state machine + pull mode to the kit backlog"  # likely full (kit-machinery); run that lane's gates
```

**Done =** states documented + real rows migrated, `board` renders and `set` flips states under test, `assign --next` pulls + claims + flips a fixture item end-to-end, suites green, PR open + CI green.

## Scope edges

**In:** _meta/BACKLOG.md (header + row migration), new `lib/backlog.sh`, commands/assign.md, commands/start.md, tests, a SPEC, CHANGELOG row.
**Out:** type loops (02), test dialects (04), any ops-toolkit BACKLOG change (the kit's own board first; consumer repos adopt later via /kit:adopt, a future SPEC).
**Not:** a daemon/cron/webhook trigger; a web UI; a Notion/GitHub-Projects sync; priority fields beyond file order (YAGNI until the queue is long).

## Where to look

`_meta/BACKLOG.md` current row shape; `lib/goal-registry.sh` (claim semantics to reuse); `commands/assign.md` Step 5/5b; ops-toolkit's OpenClaw Workboard (#154) as prior art for board-shape taste, not code.

## PR body

> Realizes north-star N2 (PHILOSOPHY §6): the BACKLOG becomes a pull-able kanban. Status state machine documented + rows migrated; `lib/backlog.sh board|set` renders + flips mechanically; `/kit:assign --next` pulls the top queued item and claims it via the existing goal-registry. No daemon; operator-push unchanged. Verify: see "How to close the loop" in ops-toolkit `_meta/megagoals/kit-north-star/goals/03-backlog-kanban.md`. Depends on PR-02.

## Notes
- 2026-06-10: DEVIATION from the outcome sketch's state names: the kit BACKLOG already had a SPEC-005 lifecycle (queued -> speccing -> validated -> executing -> shipped, + parked/dropped). Reused it (one source of truth) and added only `claimed`; the sketch's `in-progress` maps to speccing/validated/executing, `in-review` rides the executing phase, `done` = shipped. Done= semantics unchanged.
- 2026-06-10: board's first real render found 3 drifted rows (ID-020/021 shipped-but-queued; ID-012 illegal P1 status); migrated via `backlog.sh set` (the dogfood evidence the spec records as AC4).
