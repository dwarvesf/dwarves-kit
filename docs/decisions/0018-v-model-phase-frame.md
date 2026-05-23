# ADR-0018: V-model as a lens over the lifecycle; count-agnostic phase criterion

## Status: accepted (2026-05-22). Implements SPEC-031 conflict C2. Decision #1 corrected 2026-05-23 (see Correction at the end).

## Context

WORKFLOW.md's cycle table lists the kit's phases and their enforcers but states no
mirror: which definition phase each verification phase answers. Nothing makes explicit
that the kit's workflow is shaped as a V (a DEFINE arm, a build at the bottom, and a
VERIFY arm that mirrors the DEFINE arm one-for-one).

A side effect of leaving the shape implicit is a hard-coded count in two places:

- `docs/PHILOSOPHY.md` rejection criterion #2: "serves fewer than 2 of the 8 phases"
- `commands/kit-health.md` reject-list item 4: same "8 workflow phases" count

SPEC-031 (V-model lens + lead-owned convergence contract) expands the phase set beyond
eight: the V explicitly names the brief/requirement phases on the DEFINE arm and the
UI-design opt-in arm, none of which map cleanly to the eight-phase count. The
hard-coded count will mis-fire against the new framing.

This is conflict **C2** from the backlog re-evaluation (`_meta/BACKLOG.md`,
2026-05-22 re-eval row for ID-034).

## Decision

1. **The kit's lifecycle is described as a V-model phase set.** The DEFINE arm
   (brief/requirement, solution-design, test-design, optional UI-design) mirrors the
   VERIFY arm (acceptance, integration, unit/task, docs), with Code at the bottom.
   Convergence is the lead-owned integration step after all workers finish.

2. **The V-model is a lens over WORKFLOW.md's cycle table, not a replacement.**
   WORKFLOW.md's cycle table remains the single source of truth for the phase list.
   The V-model section in WORKFLOW.md references those phase names; it does not
   restate them as a competing list. One source, one table, no drift. (DEC-004,
   SPEC-031.)

3. **Feature-rejection criterion #2 is reworded from a hard phase count to a
   count-agnostic statement.** The new phrasing is: "serves fewer than 2 lifecycle
   phases." This preserves the intent (features must cut across the lifecycle to
   justify their surface) while tolerating a phase-set that grows as the V-model
   lens names more pairs. The specific count "8" is removed from PHILOSOPHY.md and
   kit-health because it is now wrong and will rot further as the V grows.

## Alternatives considered

- **Keep "8 phases" and update the count.** Rejected: a hard count is a drift
  surface. The V-model lens will expand the named phase set; any specific number
  re-introduces the same fragility. The criterion's intent is "touches enough of the
  lifecycle," not "matches the count of the week."
- **Replace the cycle table with a new V-model table.** Rejected (DEC-004): two
  tables competing for the phase list is the relabel trap in doc form. The lens
  overlay preserves one source of truth.
- **Define the V-model as a new command or runtime artifact.** Rejected (DEC-001):
  the kit already owns the lifecycle, the verification pipeline, and the ship gate.
  The gap is structural (the mirror is unnamed), not mechanical. Adding new commands
  to rename existing affordances is the relabel trap.

## Consequences

- WORKFLOW.md gains a `## The V-model lens` section that names every define-verify
  pair, the build at the bottom, and the two mirror gaps that are covered today only
  by the ship acceptance criterion and the narrative retro. The cycle table is not
  touched; it remains the canonical phase list.
- `docs/PHILOSOPHY.md` rejection criterion #2 and `commands/kit-health.md` item 4
  lose the "8" count; both say "fewer than 2 lifecycle phases." The 2+-phase
  threshold is preserved; only the count framing changes. (TASK-002, SPEC-031.)
- `tests/test-meta.sh` gains an assertion that no `8 (workflow|lifecycle )?phases`
  string survives in `docs/ commands/ WORKFLOW.md` (excluding `docs/research/`
  historical snapshots). The absence is machine-checked going forward.
- The V-model lens is extensible: when a new phase pair is added (e.g. a future
  security-design arm), the lens gains one define-verify row; the test-meta parity
  check forces the inventory table to move in step. No structural rewrite.
- Source: SPEC-031 (DEC-004, DEC-006, DEC-007) and `_meta/BACKLOG.md` 2026-05-22
  re-evaluation. Relates to ADR-0017 (mega-decomposition lane) and
  ADR-0019/ADR-0020 (parallel-execution boundary, dispatch primitive lock) which
  ride on the phase contract defined here.

## Correction (2026-05-23): build-left / test-right reframe

Decision #1's arm assignment was wrong. It framed the arms as DEFINE (left,
including test-design) mirrored by VERIFY (right). Two errors:

1. **It mixed commands and agents on an arm.** The "verify arm" listed agents
   (`task-verifier`, `integration-checker`) as if they were peer affordances to
   commands. Commands are invoked; agents are dispatched by commands. The lens now
   keeps the diagram to commands and names dispatched agents separately.
2. **It put test design on the left as if the kit shifts testing left.** The
   classic V-model designs a test at every left phase (acceptance test during
   requirements, etc.), which is why test design sits left there. The kit does NOT
   do this: it has a single late `/kit:test-plan` step, not a test designed per
   phase. So for the kit the honest shape is **build-left / test-right**.

Corrected framing:

- **Left arm = BUILD**: decompose + implement (Brief/Requirement -> Solution-design
  -> Spec -> Code at the vertex).
- **Right arm = TEST**: the whole testing wing -- test design via `/kit:test-plan`,
  then the unit -> integration -> system -> acceptance levels execute and report
  (`task-verifier`, `integration-checker`, the project suite, the `/kit:ship` gate).
- **Static review gates** (`/kit:spec-validate`, `/kit:devs-team`, `/kit:review`,
  `/kit:review-team`, `/kit:visual-team`, `/kit:docs`) sit at the artifact each one reviews (not a separate lane) and are NOT test
  levels; they verify by review, not execution.

This supersedes Decision #1's arm assignment ONLY. Decision #2 (the V is a lens
over the cycle table, not a competing list) and Decision #3 (count-agnostic
criterion #2) stand unchanged. `WORKFLOW.md`'s `## The V-model lens` and the
`docs/architecture.md` V-phase inventory were reworked to match; the inventory's
arm labels are now build / code / test / gate / cross-phase. Source: the 2026-05-23
V-model framing review (maintainer caught that the right arm is the test levels and
that the kit does not shift test design left).
