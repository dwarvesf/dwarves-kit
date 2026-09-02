# Spec: Task Board push never re-creates a page that came from the pull

Generated: 2026-09-02
Status: VALIDATED (lead approval 2026-09-02, normal lane: spec-validate phase is skip per the lane matrix)
Lane: normal
File: `docs/specs/SPEC-243-taskboard-push-marker-dedupe.md`
References: `lib/sync/sources/notion_taskboard_pull.py` (`MARKER_PREFIX`, `_item`, `_NEUTRALIZE`: the marker this guard reads, and the reason it cannot be forged from the Notion side); `lib/sync/sync_core.py` `plan_pull_only` (the sibling guard that already dedupes on the same marker, matched against raw board text, the algorithm to imitate); `lib/sync/sync_core.py` `plan_create_only` + `lib/sync/backlog_sync.py` `sync_create_only` (the push planner and its state checkpoint); `lib/sync/tests/test_notion_taskboard.py` (fake-transport fixture style); dfoundation `.kit.toml` `[sync] notion_taskboard_skip_tags` and `docs/verification/notion-taskboard-pull.md` (the incident and the stopgap).

## Problem

dfoundation runs both legs against one Notion Task Board. The pull leg reads team-approved pages into `_meta/BACKLOG.md`. The push leg sends board rows out as new Notion pages. Nothing tells the push leg that a row was born on the very board it pushes to.

The push dedupes on two things only. The local state map keyed by board id, in `plan_create_only`:

```python
known = set(state.get("map", {}))
for bid, row in rows.items():
    if bid in known:
        continue
```

And the `in_scope()` tag filter. An intake row has no state-map entry, because the push never created it. So only the tag filter holds it back.

That filter is a stopgap. dfoundation's `.kit.toml` sets `notion_taskboard_skip_tags = "inbox"` after DF-409 through DF-417 were pushed back to the Task Board on 2026-09-01 00:40 and cleaned up by hand. `#inbox` is the intake quarantine tag that `apply_board` stamps on a new row. Triage strips it. The moment triage strips it, `in_scope()` returns true, `plan_create_only` emits a create, and the push mints a second, title-prefixed copy (`DF-412 · <item>`) of a page that still exists in Notion.

The pull leg already solves the same identity problem correctly. Every intake row carries the source page id in its notes cell, and `plan_pull_only` skips any item whose marker is already in the board text. The push leg ignores that marker.

## Solution

### Approaches considered

1. **Marker-aware push identity.** `plan_create_only` treats a row whose notes carry `notion-page:<pid>` as already bound: no create, and the binding is recorded in the state map so later runs are cheap. Tradeoff: it only catches duplicates the pull leg caused, not ones a human made.
2. **Remote title-prefix query before every create.** Query the Task Board for a page whose title starts with `<bid> ·` and skip the create when one exists. Tradeoff: one network read per run (or per create), and it catches only the prefixed form, so it cannot see the unprefixed original page an intake row came from.
3. **Keep widening `skip_tags`.** Rejected. It is per-consumer config that depends on a tag surviving human triage, which is exactly the assumption that failed.

### Chosen approach + why

Approach 1 as the primary fix, in the kit's own `lib/sync`, so every adopter gets it and no config carries the guarantee. It is deterministic, needs no network, and reads an identity the Notion side cannot forge: `_NEUTRALIZE` in the pull adapter already replaces `notion-page:`, a bare 32-hex string, and any `ID-NNN` token with `[defanged]` before untrusted text reaches the row. So a marker in a board row was written by the pull adapter, never by a Task Board editor.

Approach 2 is recommended as a follow-up, not part of this spec's required scope, and it is listed in Out of Scope with its own trigger. It covers a different failure class: a hand-made duplicate, and a push after the local state map is lost (the map lives in `~/.cache/backlog-sync/<slug>/notion-taskboard.state.json`, which no backup owns). Neither class is what burned dfoundation, and adding a remote read to a planner that is currently pure costs more than it buys today.

### Extensibility & boundaries

- The load-bearing dimension is board size, not page count. The guard is a regex over each row's notes cell, so it stays linear in rows and adds no I/O.
- The marker string stays owned by the pull adapter. The push planner must not import the pull module: the two adapters are independent by design and `sync_core` imports neither. Put the pattern in `sync_core` and have the pull adapter's `MARKER_PREFIX` stay the writer's copy, with a test asserting the two agree.
- Unit boundary: `plan_create_only` decides, `sync_create_only` persists. The planner stays pure and returns the adoption as plan data, exactly as it already returns creates.

## Picture

```
Notion Task Board (team-owned, one database)
   |                                    ^
   | pull leg (read-only)               | push leg (insert-only)
   v                                    |
_meta/BACKLOG.md row                    |
  notes: "... #notion-intake ;          |
          notion-page:<32-hex> ;        |
          ... ; #inbox"                 |
   |                                    |
   |  triage strips #inbox              |
   v                                    |
  notes: "... notion-page:<32-hex> ..." |
   |                                    |
   +--> plan_create_only                |
          |                             |
          |  TODAY: no state entry,     |
          |  in_scope() true            |
          +---- src_create -------------+   ==> duplicate page

          |  AFTER: marker found
          +---- src_adopt (bid, pid) --> state map, no create
```

## Design

### Diagram (state of one board row, push leg)

```
 unpushed ----(no marker, in scope)----> src_create --> Notion page --> mapped
     |
     +--------(marker in notes)--------> src_adopt --------------------> mapped
                                          (no network call)
 mapped ------------------------------->  frozen (bid in state map)
```

### Interfaces (I/O contract)

- New in `sync_core`: `PULL_MARKER_RE = re.compile(r"notion-page:([0-9a-f]{32})")`, and a helper `bound_page_id(notes: str) -> str | None` returning the first match's group 1.
- New `Plan` field: `src_adopt: list  # [(bid, rid)]`, and `Plan.empty()` unchanged (an adoption is not work on either side, it only records what is already true; state persistence is a side effect of the run, not a plan action).
- `plan_create_only`: for each row not in `known` and not skipped by status or scope, if `bound_page_id(row.notes)` returns an id, append `(bid, pid)` to `src_adopt` and continue; otherwise append to `src_create` as today.
- `sync_create_only`: before the apply, write each `src_adopt` pair into `new_map` as `{"rid": pid, "via": "pull-marker"}` and checkpoint once. The `via` field marks a binding that no POST created, so an operator reading the state file can tell the two apart. Nothing in the create-only path dereferences `rid`, so the dash-free form the marker carries is safe to store as is.
- `describe()`: one line per adoption, in the existing grammar, e.g. `  = spoke     DF-412 bound to an existing Notion page (pull marker), not created`.

### Order of checks

The marker check runs after the status skip and after `in_scope()`. A dropped or filtered row produces neither a create nor an adoption, which keeps the existing skip semantics untouched.

### ADR link(s)

None. This restates an identity rule the pull leg already holds; it makes no lasting new decision.

## Task Breakdown

### Phase 1

- [ ] TASK-001: Add `PULL_MARKER_RE` + `bound_page_id()` and the `src_adopt` field to `lib/sync/sync_core.py`; teach `plan_create_only` to emit an adoption instead of a create when a row carries a marker. Acceptance: a `Row` whose notes carry a marker and no `#inbox` tag produces zero `src_create` and one `src_adopt`.
- [ ] TASK-002: Persist adoptions in `sync_create_only` (`lib/sync/backlog_sync.py`) and render them in `describe()`. Acceptance: after a run, the state map holds the bid with the marker's page id and `via: pull-marker`; a second run plans nothing for that row.
- [ ] TASK-003: Tests in `lib/sync/tests/test_notion_taskboard.py`, fake transport only, per the file's `rows()` and `FakeNtn` fixtures. Acceptance: the three cases in `## Acceptance Criteria` are asserted, plus one asserting `sync_core.PULL_MARKER_RE` matches the string the pull adapter writes (`MARKER_PREFIX + pid`), so a rename on either side turns the suite red.
- [ ] TASK-004: Update `lib/sync/README.md` and `lib/sync/docs/proof-of-done.md` with the guard and its run evidence.

## After state

- [ ] A board row carrying `notion-page:<pid>` is never pushed to the Task Board, whatever its tags. (Today: it is pushed as soon as triage strips `#inbox`.)
- [ ] The push run records the binding, so the row is skipped by the cheap state check from the second run on. (Today: there is no binding to record.)
- [ ] dfoundation's `notion_taskboard_skip_tags = "inbox"` becomes belt-and-braces rather than the only guard. (Today: it is the only guard.)
- [ ] `bash tests/test-sync.sh` green, including the new cases.

## Acceptance Criteria (global)

1. A row with a pull marker in its notes and no `#inbox` tag plans no create, and plans one adoption carrying the marker's page id.
2. A normal row, no marker, still plans a create, unchanged.
3. After `sync_create_only`, the state map contains the adopted bid; a second plan against the same board is empty for that row, with no ntn call issued for it (`FakeNtn.page_bodies()` empty).
4. A dropped row, or one filtered out by `skip_tags`, plans neither a create nor an adoption.
5. No test issues a write to Notion: every ntn call recorded by the fake is a read, as `test_notion_taskboard_pull.py` already asserts with its `READ_CALLS` allowlist.
6. Negative control: revert the guard in `sync_core.py`, keep the new tests, and case 1 fails.

## Verification

```
uv run --no-project --with pytest -- pytest lib/sync/tests/test_notion_taskboard.py -q
bash tests/test-sync.sh
# negative control:
git stash push -- lib/sync/sync_core.py
uv run --no-project --with pytest -- pytest lib/sync/tests/test_notion_taskboard.py -k marker -v
git stash pop
```

## Edge Cases

1. A row carries two markers (a merged row). The first match wins, and the row is never created. Recording one binding is enough; the create is what must not happen.
2. A marker appears in a row that also sits in state already. The state check runs first, so nothing changes.
3. A marker with wrong case or dashes. The pull adapter writes lowercase, dash-free ids, so the pattern stays anchored to that form. A malformed marker means no adoption and a create, which is the pre-existing behavior, not a regression.
4. A Task Board editor pastes `notion-page:<some id>` into a task's Notes. `_NEUTRALIZE` rewrites it to `[defanged]` before the pull adapter builds the row, so no forged marker reaches the board.
5. The state file is deleted. Marker rows re-adopt for free on the next run. Rows the push originally created still re-push; that is the gap approach 2 would close.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| The pull adapter's marker format changes and the push guard stops matching | The cross-module test in TASK-003 goes red | The two constants are asserted equal in the suite, so the change cannot merge silently |
| A pushed page is later deleted in Notion while its adoption stays in the map | Nothing; the push is insert-only and never reads back | Out of scope by contract: the team owns the card after it lands |
| State-map loss re-pushes rows the push itself created | Duplicate prefixed cards on the Task Board | Approach 2 (remote title-prefix query), tracked as a follow-up |

## Out of Scope

- The remote title-prefix dedupe (approach 2). Its trigger is a second duplicate incident from either a hand-made copy or a lost state map. It belongs in `NotionTaskBoardSource.preflight`, where the schema read already happens, not in the pure planner.
- Changing dfoundation's `.kit.toml`. `notion_taskboard_skip_tags = "inbox"` stays as a second layer; a consumer keeping its own guard is correct even once the kit holds the durable one.
- Any live Notion write during tests. Every case runs against the fake transport.
- Deleting or reconciling the duplicate pages already cleaned up by hand.

## Touches

- lib/sync/**
- tests/**

## Decision Log

- DEC-001: Guard in the kit, not in consumer config. Config depends on a tag surviving human triage; the marker does not.
- DEC-002: The marker pattern lives in `sync_core`, and the pull adapter keeps its own `MARKER_PREFIX`. A cross-import would couple two adapters the design keeps independent; a test asserts the two agree instead.
- DEC-003: Adoption is plan data, not a side effect inside the planner. `plan_create_only` stays pure, matching every other planner in the file.

## Open questions

None blocking. Whether `src_adopt` should also count toward `Plan.empty()` is the implementer's call; treating an adoption as non-work keeps a steady-state run reporting `(nothing to do)`, which is the reading operators already trust.
