# Spec: freeform front door (intent -> ID -> lane, no manual bookkeeping)
Generated: 2026-05-22
Status: DRAFT

> Source: the PLAYBOOK.md scenarios (S2 "apply SDD to X", S5 vague brief) and SPEC-024's
> deferred "freeform griller entry". Backlog: ID-022.

## Problem
The kit's orchestration is BACKLOG-ID-first: `/user:assign` takes an `ID-NNN`. A freeform
intent with no ID ("apply SDD to this feature", a vague brief) has no front door. Today Claude
bridges it by hand every time (`docs/PLAYBOOK.md` Section 8): crystallize -> write a BACKLOG row
-> `/user:assign ID` -> lane. That bridge is correct but is unmanaged: it lives only in Claude's
interpretation, so it is inconsistent run to run, and it is the friction SPEC-024 named when it
deferred the "freeform griller entry" (Out of Scope, that cycle's scope call).

Consequence: every ad-hoc idea pays a bookkeeping detour before the lane can run, and the most
common way an operator actually starts work (freeform intent in chat) is the one path the kit
does not support natively.

## Solution

### Approaches considered
- **A: Extend `/user:assign` to accept freeform intent as well as `ID-NNN` (chosen).** The one
  mutator gains a freeform path that crystallizes, auto-allocates the next ID, writes the BACKLOG
  row, then proceeds exactly as the ID-first path. Tradeoff: `/assign`'s contract widens; the
  crystallize step makes it non-trivially longer than today's lookup.
- **B: A new `/user:griller` (or `/user:intake`) command** dedicated to freeform capture, separate
  from `/assign`. Rejected: a second intake mutator splits the detector/mutator model (the kit has
  exactly one mutator by design, SPEC-006) and duplicates the routing logic.
- **C: A skill/keyword recognizer** (Claude detects "apply SDD / build X" and runs the bridge with
  no command change). Rejected as the primary mechanism: it leaves the front door purely in model
  interpretation (the exact fragility this spec exists to remove), and "guardrails over guidance"
  prefers an invoked command over a prose convention. (A light recognizer convention can still
  point at `/assign <freeform>`; see Out of Scope.)

### Chosen approach + why
Widen `/user:assign` so its argument is either an existing `ID-NNN` (today's path, unchanged) or
freeform intent text. On the freeform path it: (1) crystallizes the intent (challenge + scope via
the existing `/user:think` / brainstorming behavior, only as far as needed to name an outcome and
a lane), (2) allocates the next `ID-NNN` and appends a BACKLOG Active-queue row (`Status: queued`),
(3) then runs the identical ID-first path (goal draft, lane pick, activator detect, hand-off). One
mutator, one routing path, ID traceability preserved (the ID is created on the fly, never skipped).

### Extensibility & boundaries
- **Load-bearing dimension: intake shape.** Today: one shape (ID). After: two shapes (ID,
  freeform) behind one entry. A future third shape (e.g. an imported issue) is another branch in
  the same resolver, not a new command.
- **Units (independently testable):** the intent resolver (ID vs freeform), the ID allocator +
  BACKLOG writer, the crystallize gate, the unchanged ID-first tail. Each describable in <=3
  sentences.

### Architecture
```text
  /user:assign <arg>
       │
       ▼
   resolve arg ──┬── looks like ID-NNN ──▶ (today's path, unchanged) ──┐
                 │                                                       │
                 └── freeform text ──▶ crystallize (think/brainstorm)   │
                                       └▶ allocate next ID + write       │
                                          BACKLOG row (queued)           │
                                          └▶ [human approves objective]──┤
                                                                         ▼
                                              goal draft -> lane pick -> activator -> hand off
```

## Technical Design

### Interfaces (I/O contract)
- **`commands/assign.md`** consumes: `$ARGUMENTS` = either `ID-NNN` OR freeform intent text.
  Produces (freeform path): a new `_meta/BACKLOG.md` row with an allocated ID + `Status: queued`,
  then the existing `.claude/goals/<slug>.md` draft. Invariant: the freeform path MUST write the
  BACKLOG row before the goal draft (ID traceability first); it MUST pause for human approval of
  the crystallized objective before allocating, so a vague brief never auto-creates a row.
- Invariant: the ID-first path (an `ID-NNN` argument) is byte-for-byte unchanged.

### Data model changes
None to the schemas. The BACKLOG Active-queue row shape (SPEC-005 schema) is reused; the freeform
path just writes one. `Source` column records "freeform intake (date)".

### API changes (the `/user:assign` contract)
`$ARGUMENTS` widens from "an `ID-NNN`" to "an `ID-NNN` or freeform intent". Detection rule:
matches `^ID-[0-9]+$` (after trim) -> ID path; else -> freeform path.

### UI changes
None. The kit ships no UI.

### Infrastructure changes
- `commands/assign.md`: the resolver + freeform path + the approval gate.
- `tests/test-meta.sh`: assert `assign.md` documents both paths and the "row before draft" +
  "approve before allocate" invariants.
- `docs/PLAYBOOK.md`: replace Section 8's "manual bridge" note with the native path once shipped.
- `WORKFLOW.md` `## The spine`: note `/assign` accepts freeform, not only an ID.

## Task Breakdown
### Phase 1: Resolver + freeform path
- [ ] TASK-001: Add the arg resolver to `commands/assign.md` (`ID-NNN` vs freeform) with the ID
  path unchanged. - AC: `assign.md` documents the two-shape argument + the `^ID-[0-9]+$` rule.
- [ ] TASK-002: Specify the freeform path: crystallize -> approval gate -> allocate next ID +
  write BACKLOG row -> existing ID-first tail. - AC: `assign.md` carries the ordered freeform
  steps and both invariants (row-before-draft, approve-before-allocate).

### Phase 2: Guards + docs
- [ ] TASK-003: `tests/test-meta.sh` assertions for the two-path contract + invariants. - AC:
  `bash tests/test-meta.sh` exercises them and passes.
- [ ] TASK-004: Update `docs/PLAYBOOK.md` (S2/S5/S8 -> native path) and `WORKFLOW.md` spine note.
  - AC: PLAYBOOK no longer calls the bridge "manual today"; WORKFLOW spine says `/assign` accepts
  freeform.

## After state
Observable; each bullet is false now and a real check once shipped.
- [ ] `/user:assign "apply SDD to X"` (freeform) crystallizes, allocates an ID, writes a BACKLOG
  row, and routes into the lane, with one approval gate. (Today: `/assign` only accepts `ID-NNN`.)
- [ ] `/user:assign ID-007` behaves exactly as before (no regression on the ID path).
- [ ] `docs/PLAYBOOK.md` Section 8 describes a native front door, not a manual bridge.
- [ ] `tests/test-meta.sh` pins the two-path contract + the row-before-draft + approve-before-allocate invariants.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] `/assign` accepts freeform OR `ID-NNN`; freeform writes a tracked BACKLOG row before any draft; the ID path is unchanged.
- [ ] No regressions: `bash tests/test-meta.sh && bash tests/test-hooks.sh` both exit 0.

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` exit 0 AND `commands/assign.md` documents both the `ID-NNN` and freeform paths AND the row-before-draft + approve-before-allocate invariants are present.

## Edge Cases
1. Ambiguous arg (looks like an ID but is not in the queue): treat as ID path, report "unknown id" (today's behavior), do NOT silently create a freeform row from a typo'd ID.
2. Freeform intent that is still too vague to name an outcome: the crystallize step loops (think/brainstorming) and does NOT allocate an ID until the objective is approved (no half-baked rows).
3. Duplicate freeform intent (a row already exists for the same idea): surface the existing row instead of allocating a second ID (mirror the SPEC-005 idempotency edge).

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Freeform path auto-creates rows from vague briefs | BACKLOG fills with half-baked queued rows | the approve-before-allocate invariant: no row until the objective is approved |
| ID path regresses behind the new resolver | an `ID-NNN` assign behaves differently | the ID path is unchanged + a no-regression AC + meta assertion |
| Untracked freeform work | a lane runs with no BACKLOG row | the row-before-draft invariant: the row is written before the goal draft |

## Out of Scope
- **A prose keyword-recognizer that auto-runs `/assign` without the operator invoking it** (approach C as the primary mechanism): the front door is an invoked command, not a model convention. A light "you can run `/assign <freeform>`" pointer is fine; auto-execution on a detected phrase is not.
- **Removing BACKLOG-ID-first**: the ID stays canonical; this spec only changes WHEN the ID is allocated (on the fly for freeform), not WHETHER.
- **Autonomy level of the subsequent lane**: governed by the operator's pre-authorization (PLAYBOOK Section 9), not by this front door.

## Decision Log
- DEC-001: Extend `/assign` (approach A) rather than add a second intake command (B) or rely on a keyword recognizer (C). Rationale: one mutator (SPEC-006), guardrails over guidance, ID traceability preserved. Who: drafted from the PLAYBOOK scenarios 2026-05-22.
- DEC-002: Freeform path pauses for human approval of the crystallized objective BEFORE allocating an ID. Rationale: a vague brief turned straight into a tracked row + spec is how scope drift starts (PLAYBOOK S5). Who: same.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
