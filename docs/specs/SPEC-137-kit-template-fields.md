# Spec: kit template fields (optional References, Design ordering, meta-agent Post-condition)
Generated: 2026-07-04
Status: VALIDATED
Lane: normal
References: research/2026-07-04-fable-unknowns-absorption.md Design 3 (ops-toolkit; not present
in this repo, so this spec stands on its own contract , mega-goal kit-absorptions, sub-goal 03).

## Problem
Three small, independently-useful template absorptions surfaced by a prior Fable-unknowns
review sat unfilled in `/kit:spec`, `/kit:design`, and the meta-agent's drafting templates:
1. A spec has no place to point at existing source/docs that already implement the wanted
   semantics , authors re-describe from scratch instead of citing prior art.
2. The Design section carries no guidance on WHICH decisions to write about first when several
   are in play, so authors write in whatever order occurred to them instead of prioritizing the
   parts most expensive to revise later.
3. The meta-agent's Mode C (inline role spec, immediate-dispatch) hands the caller a worker
   preamble with no stated way to verify the worker's output before trusting it done.

## Solution

### Approaches considered
1. Add all three as REQUIRED new fields/gates. Rejected: none of the three needs enforcement,
   and a new required field on `/kit:spec-validate` would be a new gate, out of scope for this
   sub-goal (contract: "NO new gate, no new required field").
2. Add all three as OPTIONAL prose , a field, a documented ordering convention, and an optional
   return-field , with no new validator logic. Chosen.
3. Skip the meta-agent Post-condition line entirely and let each drafted worker improvise a
   verification approach. Rejected: the caller (usually `/kit:execute`) needs SOME concrete
   check to run before trusting an inline-dispatched worker's output; leaving it fully
   improvised reproduces the exact gap this sub-goal absorbs.

### Chosen approach + why
Approach 2. All three land as prose additions to existing templates: an optional `References:`
metadata field (spec.md), an ordering instruction in the `## Design` guidance (spec.md +
design.md, kept in sync since both build the same design content), and a `Post-condition:`
field in the meta-agent's Mode C return shape (mandatory only within that already-optional
mode, never touching Modes A/B or any registered agent file).

### Extensibility & boundaries
- References: grows to "one or more pointers", already stated as a list-shaped field ("one or
  more pointers... each with one line"); no schema to enforce, since spec-validate does not
  parse it.
- Design ordering: a convention, not a gate; if a future spec needs a stricter order it is a
  separate, larger change (out of scope here).
- Post-condition: scoped to Mode C only (ephemeral, no persisted file); Modes A/B are untouched
  so no retrofit of existing hand-written agents is implied.

### Architecture
See `## Design` below.

## Design
obvious: three additive prose changes to existing templates/instructions, no new component, no
control-flow change, no schema, no external integration, no irreversible choice, and the one
approach considered above is the only reasonable shape , collapses per ADR-0031 §1.

## Technical Design

### Interfaces (I/O contract)
- `commands/spec.md`: the generated `docs/specs/SPEC-NNN-*.md` template gains an optional
  `References:` metadata line (peer to `Generated:`/`Status:`/`Lane:`) and an `**Ordering:**`
  instruction inside `## Design`. Both are prose; nothing parses or requires them.
- `commands/design.md`: Step 4's section list gains the same ordering instruction, so the
  interactive lane and the spec template stay consistent.
- `agents/meta-agent.md`: Mode C's returned block gains an optional-but-mandated-when-a-
  specialist-is-returned `Post-condition:` line. Mode C is never persisted to a file (per its
  existing contract), so this changes what the meta-agent RETURNS to its caller, not any
  on-disk agent registry.

## After state
- [ ] `commands/spec.md`'s generated spec template carries a `References:` field marked
  optional. (Today: no such field existed.)
- [ ] `commands/spec.md`'s `## Design` guidance and `commands/design.md`'s Step 4 both state the
  likelihood-to-tweak ordering (data models/public interfaces first, UX flows next, mechanical
  refactors last). (Today: no ordering guidance existed in either.)
- [ ] `agents/meta-agent.md` Mode C's returned shape carries a `Post-condition:` line. (Today:
  Mode C returned NAME/TOOLS/PREAMBLE only, no caller-side verification hook.)
- [ ] `/kit:spec-validate`'s 6 reviewers are behaviorally unchanged: a fixture spec WITH
  `References:` and the byte-identical fixture WITHOUT it both pass Reviewer 6 (the one
  blocking reviewer), proving no new gate. Checkable by `bash tests/test-references-field.sh`.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] `bash tests/test-references-field.sh`, `bash tests/test-design-record.sh`,
      `bash tests/test-meta-agent.sh`, and `bash tests/test-meta.sh` all pass unchanged in count
      (no regressions)

## Verification
`bash tests/test-references-field.sh && bash tests/test-design-record.sh && bash tests/test-meta-agent.sh && bash tests/test-meta.sh`

## Edge Cases
1. A spec author fills `References:` with a pointer that turns out to be wrong/stale , this is
   an authoring-quality issue, not something spec-validate is asked to catch (out of scope, same
   as any other prose field's factual accuracy).
2. A drafted Mode C role has no meaningful post-condition (e.g. a pure prose task) , the
   PREAMBLE + Rules already require the field to be concrete; a genuinely trivial task should
   return `NO_SPECIALIST` instead (existing Mode C branch), sidestepping the question.

## Out of Scope
- Any REQUIRED field or new gate (explicit sub-goal boundary).
- Sub-goal 04 (grill) and 05 (emits) and `mega.md` (09) , separate sub-goals in the same
  mega-goal.
- Retrofitting Post-condition-shaped verification into Mode A/B or any existing hand-written
  `agents/*.md` file.

## Decision Log
- DEC-001: prose-only additions to three existing templates; no new command, no new validator
  logic, no new required field. Rationale: the sub-goal contract explicitly forbids a new gate;
  the fixture pair (`tests/test-references-field.sh`) is the reproducible proof of that
  boundary.
- DEC-002: `Post-condition:` scoped to meta-agent Mode C only (not Modes A/B), because Mode C is
  the ephemeral immediate-dispatch case where the caller most needs a verification hook and
  where adding the field carries zero retrofit risk to existing registered agents.

## Open questions
(none)
