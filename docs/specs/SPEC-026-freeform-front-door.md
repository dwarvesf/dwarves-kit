# Spec: freeform front door (intent -> ID -> lane, no manual bookkeeping)
Generated: 2026-05-22
Status: VALIDATED

> Source: the PLAYBOOK.md scenarios (S2 "apply SDD to X", S5 vague brief) and SPEC-024's
> deferred "freeform griller entry". Backlog: ID-022.
> Validated 2026-05-22 via /user:spec-validate (5 lenses); NEEDS REVISION -> revised
> (DEC-003 delegate-to-think, DEC-004 sanitize, DEC-005 atomic-allocate; dedup + concurrency edges added).

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
freeform intent text. On the freeform path it: (1) **delegates** crystallization to `/user:think`
(the existing idea-griller) rather than absorbing the interview, so `/assign` stays the quick
mutator SPEC-006 defined (it does not run a multi-turn interview itself); `/think` returns a
crystallized objective + a lane, (2) `/assign` then does only its mutation tail: sanitize the
intent, allocate the next `ID-NNN`, append a BACKLOG Active-queue row (`Status: queued`), (3) then
runs the identical ID-first path (goal draft, lane pick, activator detect, hand-off). One mutator,
one routing path, ID traceability preserved (the ID is created on the fly, never skipped), and the
interactive part lives in `/think` where it belongs (DEC-003).

Boundary note: `/assign` orchestrates the freeform path but the **interview is delegated**, not
embedded. `/assign`'s own work stays "allocate + route", consistent with the detector/mutator
split (SPEC-006).

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
                 └── freeform text ──▶ crystallize via /user:think   │
                                       └▶ approve, sanitize, allocate, write       │
                                          BACKLOG row (queued)           │
                                          └▶ [human approves objective]──┤
                                                                         ▼
                                              goal draft -> lane pick -> activator -> hand off
```

## Technical Design

### Interfaces (I/O contract)
- **`commands/assign.md`** consumes: `$ARGUMENTS` = either `ID-NNN` OR freeform intent text.
  Produces (freeform path): a new `_meta/BACKLOG.md` row with an allocated ID + `Status: queued`,
  then the existing `.claude/goals/<slug>.md` draft.
- Invariant (delegation): the freeform path delegates the interview to `/user:think`; `/assign`
  itself does not run a multi-turn interview (DEC-003), so the mutator stays light.
- Invariant (approve-before-allocate): the freeform path MUST pause for human approval of the
  crystallized objective before it allocates an ID, so a vague brief never auto-creates a row.
- Invariant (row-before-draft): the BACKLOG row is written before the goal draft (ID traceability first).
- Invariant (sanitization, DEC-004): freeform intent is sanitized before it touches a file. Table
  cells escape `|` (and newlines) so a freeform string cannot break the `_meta/BACKLOG.md` pipe
  table; the derived slug is reduced to `[a-z0-9-]+` (no `/`, no `..`) so it cannot traverse out of
  `.claude/goals/`.
- Invariant (allocate-atomically, DEC-005): the ID is allocated by re-reading the current max in
  the same step that writes the row, and a post-write collision check (two equal IDs) fails loud
  rather than silently colliding (mirrors the existing SPEC/ADR dup-number guard).
- Invariant: the ID-first path (an `ID-NNN` argument) is byte-for-byte unchanged.

### Data model changes
None to the schemas. The BACKLOG Active-queue row shape (SPEC-005 schema) is reused; the freeform
path just writes one (sanitized, per the sanitization invariant). `Source` column records
"freeform intake (date)". The derived slug follows the existing kebab convention but is hardened to
`[a-z0-9-]+`.

### API changes (the `/user:assign` contract)
`$ARGUMENTS` widens from "an `ID-NNN`" to "an `ID-NNN` or freeform intent". Detection rule:
matches `^ID-[0-9]+$` (after trim) -> ID path; else -> freeform path.

### UI changes
None. The kit ships no UI.

### Infrastructure changes
- `commands/assign.md`: the resolver + freeform path (delegating crystallize to `/user:think`) +
  the approval gate + sanitization + atomic allocation.
- `tests/test-meta.sh`: assert `assign.md` documents both paths, the `/user:think` delegation, and
  the four invariants (row-before-draft, approve-before-allocate, sanitization, atomic-allocate).
- `docs/PLAYBOOK.md`: replace Section 8's "manual bridge" note with the native path once shipped.
- `WORKFLOW.md` `## The spine`: note `/assign` accepts freeform, not only an ID.

## Task Breakdown
### Phase 1: Resolver + freeform path
- [ ] TASK-001: Add the arg resolver to `commands/assign.md` (`ID-NNN` vs freeform) with the ID
  path unchanged. - AC: `assign.md` documents the two-shape argument + the `^ID-[0-9]+$` rule.
- [ ] TASK-002: Specify the freeform path: **delegate crystallize to `/user:think`** -> approval
  gate -> sanitize -> allocate ID + write BACKLOG row -> existing ID-first tail. The interview is
  delegated, not embedded (DEC-003). - AC: `assign.md` carries the ordered freeform steps, names the
  `/user:think` delegation, and the row-before-draft + approve-before-allocate invariants.

### Phase 2: Hardening
- [ ] TASK-003: Sanitization + concurrency guard in `commands/assign.md`'s freeform path: escape
  `|`/newlines in the BACKLOG row cells (table integrity); reduce the slug to `[a-z0-9-]+` (no `/`,
  no `..`); allocate the ID by re-reading max in the write step + a post-write equal-ID collision
  check that fails loud. - AC: `assign.md` documents the sanitization + atomic-allocate invariants
  (DEC-004, DEC-005).

### Phase 3: Guards + docs
- [ ] TASK-004: `tests/test-meta.sh` assertions: `assign.md` documents both paths, the delegation,
  and all four invariants (row-before-draft, approve-before-allocate, sanitization, atomic-allocate).
  - AC: `bash tests/test-meta.sh` exercises them and passes.
- [ ] TASK-005: Update `docs/PLAYBOOK.md` (S2/S5/S8 -> native path) and the `WORKFLOW.md` spine
  note. - AC: PLAYBOOK no longer calls the bridge "manual today"; the WORKFLOW spine says `/assign`
  accepts freeform.

## After state
Observable; each bullet is false now and a real check once shipped.
- [ ] `/user:assign "apply SDD to X"` (freeform) crystallizes, allocates an ID, writes a BACKLOG
  row, and routes into the lane, with one approval gate. (Today: `/assign` only accepts `ID-NNN`.)
- [ ] `/user:assign ID-007` behaves exactly as before (no regression on the ID path).
- [ ] `docs/PLAYBOOK.md` Section 8 describes a native front door, not a manual bridge.
- [ ] The freeform path delegates the interview to `/user:think` (the mutator does not embed it).
- [ ] A freeform intent containing `|` does not corrupt the `_meta/BACKLOG.md` table, and a slug-hostile intent (e.g. `../x`) cannot write outside `.claude/goals/`.
- [ ] `tests/test-meta.sh` pins the two-path contract + all four invariants (row-before-draft, approve-before-allocate, sanitization, atomic-allocate).

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria.
- [ ] `/assign` accepts freeform OR `ID-NNN`; freeform delegates the interview to `/user:think`, sanitizes input, writes a tracked BACKLOG row before any draft; the ID path is unchanged.
- [ ] No regressions: `bash tests/test-meta.sh && bash tests/test-hooks.sh` both exit 0.

## Verification
`bash tests/test-meta.sh && bash tests/test-hooks.sh` exit 0 AND `commands/assign.md` documents both the `ID-NNN` and freeform paths, the `/user:think` delegation, and all four invariants (row-before-draft, approve-before-allocate, sanitization, atomic-allocate).

## Edge Cases
1. Ambiguous arg (looks like an ID but is not in the queue): treat as ID path, report "unknown id" (today's behavior), do NOT silently create a freeform row from a typo'd ID.
2. Freeform intent that is still too vague to name an outcome: the crystallize step loops (think/brainstorming) and does NOT allocate an ID until the objective is approved (no half-baked rows).
3. Duplicate freeform intent (a row already exists for the same idea): detection is by **slug match after crystallize** (the crystallized objective produces a slug; if that slug already has a row/draft, surface it instead of allocating a second ID). Semantic dedup (two differently-worded briefs for the same idea) is **best-effort**: on a near-match slug, ask rather than silently merge or duplicate. (Mirrors the SPEC-005 filesystem-is-truth idempotency, made explicit for freeform.)
4. Concurrent freeform allocation (two sessions allocate at once): both re-read max in the write step; the post-write equal-ID collision check fails loud (the operator re-runs), rather than two rows silently sharing an ID.
5. Pipe / newline in the freeform intent: sanitized (escaped) before the BACKLOG row is written, so the markdown table stays well-formed.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Freeform path auto-creates rows from vague briefs | BACKLOG fills with half-baked queued rows | the approve-before-allocate invariant: no row until the objective is approved |
| ID path regresses behind the new resolver | an `ID-NNN` assign behaves differently | the ID path is unchanged + a no-regression AC + meta assertion |
| Untracked freeform work | a lane runs with no BACKLOG row | the row-before-draft invariant: the row is written before the goal draft |
| Freeform `|`/newline corrupts the BACKLOG pipe table | the Active-queue table renders broken; a row has wrong columns | the sanitization invariant (DEC-004): escape `|`/newlines in row cells before writing |
| Slug path-traversal from freeform (`../`, `/`) | a draft is written outside `.claude/goals/` | the sanitization invariant (DEC-004): slug reduced to `[a-z0-9-]+` |
| Concurrent allocation picks the same ID | two Active-queue rows share an ID (caught at CI by the dup-number guard, but late) | the atomic-allocate invariant (DEC-005): re-read max in the write step + a loud post-write collision check |

## Out of Scope
- **A prose keyword-recognizer that auto-runs `/assign` without the operator invoking it** (approach C as the primary mechanism): the front door is an invoked command, not a model convention. A light "you can run `/assign <freeform>`" pointer is fine; auto-execution on a detected phrase is not.
- **Removing BACKLOG-ID-first**: the ID stays canonical; this spec only changes WHEN the ID is allocated (on the fly for freeform), not WHETHER.
- **Autonomy level of the subsequent lane**: governed by the operator's pre-authorization (PLAYBOOK Section 9), not by this front door.

## Decision Log
- DEC-001: Extend `/assign` (approach A) rather than add a second intake command (B) or rely on a keyword recognizer (C). Rationale: one mutator (SPEC-006), guardrails over guidance, ID traceability preserved. Who: drafted from the PLAYBOOK scenarios 2026-05-22.
- DEC-002: Freeform path pauses for human approval of the crystallized objective BEFORE allocating an ID. Rationale: a vague brief turned straight into a tracked row + spec is how scope drift starts (PLAYBOOK S5). Who: same.
- DEC-003: The freeform path DELEGATES crystallize to `/user:think`; `/assign` does not embed a multi-turn interview. Rationale: SPEC-006 defines `/assign` as a light mutator-dispatcher that "does not execute"; absorbing an interactive interview would break that boundary. The interview lives in `/think`; `/assign` keeps only allocate + route. Who: spec-validate Reviewer 5 (2026-05-22).
- DEC-004: Freeform intent is sanitized before it touches a file: escape `|`/newlines in BACKLOG table cells; reduce the slug to `[a-z0-9-]+` (no `/`, no `..`). Rationale: a freeform string is operator-controlled text written into a pipe-delimited markdown table and a filesystem path; without escaping it can corrupt the queue table or traverse out of `.claude/goals/`. Who: spec-validate Reviewer 1 (2026-05-22).
- DEC-005: The ID is allocated by re-reading the current max in the same step that writes the row, with a loud post-write equal-ID collision check. Rationale: two concurrent freeform allocations would otherwise pick the same `max+1` and collide (the CI dup-number guard catches it, but late). Who: spec-validate Reviewer 2 (2026-05-22).

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
