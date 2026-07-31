# Spec: Spec template gains `## Picture` (the pre-build twin of visual proof)
Generated: 2026-07-31
Status: APPROVED
Lane: normal (touches `commands/spec.md`, `commands/spec-validate.md`, `tests/fixtures`; no
auth/data/hook/migration risk , same surface class SPEC-122 used for the sibling `## Design`
change; `bash lib/classify/lane-classify.sh classify` confirms `normal`).
References: `tests/test-design-record.sh` + `docs/specs/SPEC-122-design-record.md` implement the
same shape (a template scaffold + a spec-validate check + a fixture-based structural test) for
`## Design`; this spec reuses that pattern for `## Picture` rather than inventing a new one.

## Problem

`docs/briefs/DECISION-BRIEF-factory-legibility.md` §2 (ID-454): a spec that carries a picture
(a diagram or a prototype) builds better than one that carries prose alone , the factory's
"draw the plan before it costs a night" instinct. The kit already has a post-build visual-proof
MUST (ID-395, queued): a behavioral change owes a screenshot/GIF a reviewer can look at. It has
no pre-build twin: nothing asks a spec to show the shape of the change before anyone builds it.
`/kit:spec-validate` has six reviewers and none of them look at whether a spec is legible at a
glance.

## Solution

### Approaches considered
1. **A new top-level `## Picture` section in the spec template (ASCII/box-drawing only,
   mandatory non-empty for full-lane), checked by an existing `/kit:spec-validate` reviewer.**
   Reuses the SPEC-122 shape (scaffold + reviewer finding) that already proved out for
   `## Design`. The check stays where a closely related check already lives (Reviewer 4,
   Scope Critic, which already looks for gaps between a spec's claims and its task list) rather
   than adding a 7th reviewer.
2. **A 7th, new reviewer dedicated to the picture.** Rejected: `## Design`'s Reviewer 6 is
   explicitly the ONE reviewer this command lets block `VALIDATED` (ADR-0031 §1); a second
   blocking reviewer was not asked for by ID-454, and an advisory 7th reviewer would duplicate
   Reviewer 4's existing "does the spec's claims match its task list" territory for no benefit.
3. **A `lib/` script that parses a spec file and flags a missing `## Picture`.** Rejected:
   `/kit:spec-validate` has no mechanical scripts today , Reviewer 6's own comment names this
   plainly ("prompt text, not code"); its structural contract is instead proven by a bash test
   harness (`tests/test-design-record.sh`) that reproduces the check as a pure function over
   fixtures. Adding a live-running script for Picture but not for Design would be an
   inconsistent enforcement shape for two sibling checks; the test-harness pattern is the one
   the repo already committed to for exactly this kind of prompt-only check.

### Chosen approach + why
Approach 1, with Reviewer 4 as the check's home and the test-harness pattern (not a new
script) for its structural proof. Matches SPEC-122's precedent byte-for-byte in shape, differs
only in where the content lives (Reviewer 4 vs a new Reviewer 6-style block) because Picture is
advisory everywhere except the full-lane presence bar, never blocking , ID-454's row does not
ask for a second reviewer that can refuse `VALIDATED`.

### Extensibility & boundaries
- Load-bearing dimension: the lane bar (full = required, everything else = encouraged). Moving
  the bar (e.g. requiring it at `normal` too) is a one-line edit to Reviewer 4's bullet and the
  template comment; it does not touch the section's shape.
- Unit boundaries: the template edit (`commands/spec.md`) is pure scaffold, no enforcement
  logic. The check (`commands/spec-validate.md` Reviewer 4) is advisory prose, same severity
  ladder as Reviewer 4's other findings. Each is readable without the other.

### Architecture
See `## Design` below.

## Picture
```
  commands/spec.md (template)                    docs/specs/SPEC-NNN-*.md (a real spec)
  +-----------------------------+                 +--------------------------------+
  | ## Solution                 |                 | ## Picture                     |
  | ## Picture      <- NEW  ----+---------------->|   <ASCII diagram, or a          |
  | ## Design                   |  every spec      |    prototype/<name> pointer>   |
  | ## Task Breakdown           |  instantiates    | ## Task Breakdown               |
  +-----------------------------+  this section    +----------------+---------------+
                                                                     |
                                                                     | read together
                                                                     v
  commands/spec-validate.md                       tests/test-picture-section.sh
  +-----------------------------+                 +--------------------------------+
  | Reviewer 4: Scope Critic    |  reads  <--------+ reproduces the presence check   |
  |  + Picture presence check   |                 | as a pure bash fn over fixtures |
  |  + Picture-vs-tasks lens Q  |                 | (full/empty, full/filled,       |
  +-----------------------------+                 |  normal/empty, full/prototype)  |
```

## Design
<!-- Dogfooding: this spec is design-bearing (it changes the spec-authoring template's required
     structure and adds a control-flow branch to /kit:spec-validate's existing decision path),
     same class SPEC-122 used for the sibling `## Design` change. -->

### Approaches considered + chosen
Same as `## Solution` above (approach 1: scaffold + an existing reviewer, test-harness proof).
Not re-litigated here.

### Diagram
See `## Picture` above , the diagram there already shows this spec's own control flow (template
-> real spec -> reviewer -> test), so it is not repeated in a second form here.

### ADR link(s)
None. This spec implements ID-454 directly; it introduces no new lasting/irreversible decision
beyond what the decision brief already records.

### Boundaries & failure modes
Same blast radius as SPEC-122 (the two command files + tests/fixtures), not data or an external
integration, so a full failure-modes table is not owed. One boundary worth naming: Reviewer 4's
Picture bullets are advisory, same as its other findings , they never block `VALIDATED`. Only
Reviewer 6 (`## Design`) keeps that power (ADR-0031 §1, unchanged by this spec).

## Technical Design

### Interfaces (I/O contract)
- **Consumes:** the spec's own `## Picture` section text (present/absent/empty), the spec's
  `Lane:` header (first word, same parse `hooks/ship-gate.sh` already uses), and `## Task
  Breakdown` for the lens question.
- **Produces:** the existing Spec Validation Report gains two Reviewer 4 findings when they
  fire; no change to the report's Verdict grammar (`APPROVED` / `NEEDS REVISION`) or to which
  reviewer can withhold `VALIDATED`.
- **Invariant:** Reviewer 6 stays the only reviewer whose finding can refuse `VALIDATED`.

### Data model changes
None (markdown template + prompt-text changes only).

### API changes
None.

### UI changes
None.

### Infrastructure changes
None.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-001: Add `## Picture` to the spec template in `commands/spec.md`, between
  `## Solution` and `## Design` , mandatory non-empty for full-lane, encouraged for lighter
  lanes, ASCII/box-drawing only (never mermaid), with the `/kit:prototype` pointer alternative
  for UI-shaped specs., heading present at the right position; the comment states the
  full-lane bar, the ASCII-only rule, and the prototype-pointer alternative.

### Phase 2: Core
- [ ] TASK-002: Extend Reviewer 4 (Scope Critic) in `commands/spec-validate.md` with the
  Picture presence check (mechanical, full-lane) and the picture-vs-task-list lens question., both bullets present, neither introduces new BLOCKING language (Reviewer 6 stays the only
  blocking reviewer).

### Phase 3: Polish
- [ ] TASK-003: Add `tests/test-picture-section.sh` + fixtures under
  `tests/fixtures/picture-section/`, mirroring `tests/test-design-record.sh`'s pattern (pure
  bash reproduction of the presence check, run over fixtures, plus structural wiring greps on
  both command files)., negative control (full-lane + empty Picture) FLAGS, full-lane + filled
  PASSES, normal-lane + empty PASSES (proportionality), full-lane + prototype-pointer PASSES.

## After state
- [ ] `commands/spec.md`'s template carries a `## Picture` section between `## Solution` and
  `## Design`. (Today: no such section exists; `## Design`'s diagram is the only pre-build
  visual the template asks for, and only for design-bearing specs.)
- [ ] `commands/spec-validate.md`'s Reviewer 4 names the Picture presence check and the
  picture-vs-task-list lens question. (Today: Reviewer 4 has no Picture-related bullet.)
- [ ] `bash tests/test-picture-section.sh` passes, including the negative control (a full-lane
  spec with an empty `## Picture` is flagged) and the proportionality control (a normal-lane
  spec with an empty `## Picture` is not). (Today: no such test exists.)

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] The 4 fixtures (full/empty NC, full/filled, normal/empty proportionality, full/prototype
  pointer) are all green
- [ ] Reviewers 1-3, 5, 6 in `/kit:spec-validate` are untouched (diff limited to Reviewer 4's
  two new bullets)

## Verification
```
bash tests/test-picture-section.sh
```

## Test plan

| # | AC / claim | Fixture | Expected | Covers |
|---|---|---|---|---|
| 1 | a full-lane spec with an EMPTY `## Picture` is flagged | `tests/fixtures/picture-section/full-lane-empty.md` | verdict FLAG | NEGATIVE CONTROL |
| 2 | a full-lane spec with a FILLED ASCII `## Picture` passes | `tests/fixtures/picture-section/full-lane-filled.md` | verdict PASS | positive |
| 3 | a normal-lane spec with an EMPTY `## Picture` passes (not required below full) | `tests/fixtures/picture-section/normal-lane-empty.md` | verdict PASS | PROPORTIONALITY CONTROL |
| 4 | a full-lane spec whose `## Picture` points at a `/kit:prototype` branch instead of ASCII passes | `tests/fixtures/picture-section/full-lane-prototype-pointer.md` | verdict PASS | UI-shaped routing (ID-448) |
| 5 | `commands/spec.md` carries the new section (heading, full-lane bar, ASCII-only, prototype pointer) | structural grep | all present | template AC |
| 6 | `commands/spec-validate.md` carries both Reviewer 4 bullets, with no new BLOCKING marker | structural grep | bullets present, Reviewer 6 stays the only BLOCKING reviewer | enforcement AC |

**COVERAGE-DELTA:** rows 1-4 exercise the actual presence-check decision (real spec text in,
verdict out) via the same lightweight harness `tests/test-design-record.sh` uses, since
`/kit:spec-validate` is a prompt, not executable code , the honest boundary is the STRUCTURAL
contract (the section exists, is non-empty, or points at a prototype), not the reviewer's live
LLM judgment on whether the picture actually agrees with the task list (same limitation
SPEC-122 already accepted for Reviewer 6).

## Edge Cases
1. A spec predates this template (no `## Picture` heading at all). Reviewer 4 treats a missing
   section the same as an empty one on a full-lane spec (a finding); a non-full-lane legacy
   spec is not penalized for its absence (mirrors Reviewer 5/6's legacy-grace clauses).
2. A UI-shaped full-lane spec runs `/kit:prototype` but never folds the branch pointer back into
   `## Picture`. Presence check still flags it , the pointer is what the mechanical check
   accepts as "non-empty"; a `/kit:prototype` run that never gets recorded in the spec is
   indistinguishable from one that never happened.

## Out of Scope
- A `WORKFLOW.md` Lane×phase depth-matrix row for Picture , ID-454's row asks for the template
  section, the presence check, and the lens question only; a matrix row is a separate, later
  call if Picture earns its own ceremony tier.
- Auto-generating the ASCII diagram from the task list, or any other authoring aid , the
  section is authored by hand, same as `## Design`'s diagram.
- Any change to `## Design` or Reviewer 6; they are read here only as the precedent this spec
  reuses.

## Decision Log
- DEC-001: Picture's presence check lives in Reviewer 4 (Scope Critic), not a new Reviewer 7.
  Rationale: Reviewer 6 is deliberately the one reviewer that can block `VALIDATED`
  (ADR-0031 §1); ID-454 does not ask for a second blocking reviewer, and Reviewer 4 already
  owns "does the spec's claims match its task list" territory.
- DEC-002: no new `lib/` script. Rationale: `/kit:spec-validate` has no mechanical scripts
  today (Reviewer 6's own precedent proves the structural contract via a fixture-based bash
  test instead); adding a script for Picture but not Design would be inconsistent.

## Open questions
(none)
