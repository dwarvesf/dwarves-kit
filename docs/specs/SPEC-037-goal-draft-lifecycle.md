# Spec: Goal-file coherence (filesystem-authoritative drafts + archive-on-ship lifecycle)
Generated: 2026-05-23
Status: VALIDATED
Source: maintainer session 2026-05-23 ("make sure goal files are managed properly; there is also a kit-goals folder"); approved via the `/plan` gate (plan `harmonic-hopping-spindle`). Reuses the `lib/goal-registry.sh` helper shape (SPEC-036) and the SPEC-005 state model.

> The kit has two on-disk "goal" stores that read as duplicates because they share the
> word *goal*: the goal **draft** store (`.claude/goals/<slug>.md`, ADR-0011) and the
> cross-session running-goal **registry** (`.git/kit-goals/<slug>.goal`, ADR-0022). They
> are not duplicates, the slug is the shared key, but the model is incoherent: a phantom
> `INDEX.md` is promised and never built, drafts never retire, and nothing documents the
> two stores side by side. This spec makes the model coherent.

## Problem

Three concrete defects, all in the goal-file model:

1. **Phantom `INDEX.md`.** ADR-0011, SPEC-005, `WORKFLOW.md`, and `commands/assign.md` all promise a derived `.claude/goals/INDEX.md` cache. No command ever writes or rebuilds it; the render commands read the filesystem directly. A documented-but-absent file is the phantom feature the kit's own code-quality rules reject.
2. **No draft lifecycle.** A draft's `status:` never advances past `drafted`, and shipped drafts are never retired. Drafts whose `target_spec` already SHIPPED (SPEC-024, SPEC-027, SPEC-028 at time of writing) keep rendering in `/kit:start` / `/kit:next` as live candidate work. `.claude/goals/` becomes a graveyard.
3. **No single side-by-side model.** The draft store and the registry are documented in separate sections of separate docs; nothing puts them next to each other, so they read as accidental duplicates, the exact confusion that prompted this work.

## Solution

### Approaches considered

1. **Filesystem-authoritative + archive-on-ship helper (chosen).** Drop the `INDEX.md` cache (the filesystem is the source of truth). Add `lib/goal-drafts.sh archive`, a sibling to `lib/goal-registry.sh`, that moves a draft to `.claude/goals/done/` once its `target_spec` ships; wire it into `/kit:ship`. Document the two stores side by side in the architecture state model.
2. **Build `INDEX.md` for real.** Honors ADR-0011 literally, adds a cache the filesystem already provides for free. Rejected: against kit minimalism.
3. **Status-field-only retirement (no move).** Flip `status:` in place and filter by it in the render commands. Rejected: the directory keeps growing and the render commands gain filter code, where a move drops the draft out of the non-recursive `*.md` glob for free.

### Chosen approach and why

- **The filesystem is the sole source of truth.** No derived cache (ADR-0023, supersedes ADR-0011's `INDEX.md`).
- **Lifecycle: drafted -> archived-on-ship.** `lib/goal-drafts.sh archive` scans `.claude/goals/*.md`; for each, it reads `target_spec`, resolves `docs/specs/SPEC-NNN-*.md`, and if that spec's `Status:` is SHIPPED it flips the draft's `status: shipped` and **moves** it (never deletes) to `.claude/goals/done/`. Scanning all drafts each run makes it idempotent and order-independent. `/kit:ship` runs it after the docs step.
- **Move, never delete**, and never clobber an existing `done/<slug>.md`.
- **Two stores side by side** in `docs/architecture.md` "## State model": draft = candidate work / "what's active"; registry = the cross-session lock / "what's executing now"; the slug is the shared key.

### Extensibility and boundaries

- The archive trigger is `/kit:ship`. No daemon, no scheduler, no watch. A skipped ship just leaves drafts until the next idempotent `archive`.
- Specless drafts (`target_spec: (none)` / `(none yet; ...)`) and drafts whose spec is unresolvable or not yet SHIPPED stay in place.
- `lib/goal-drafts.sh` honors `GOAL_DRAFTS_DIR` / `GOAL_SPECS_DIR` overrides for hermetic tests, mirroring the registry's `GOAL_REGISTRY_DIR`.

### Architecture

```
.claude/goals/<slug>.md        goal DRAFT (what's active)  --archive-on-ship-->  .claude/goals/done/<slug>.md
        | slug (shared key)
.git/kit-goals/<slug>.goal     registry CLAIM (what's executing now)            (released on completion)

lib/goal-drafts.sh   archive [--dry-run] | list | dir      <- run by /kit:ship
lib/goal-registry.sh claim | list | log | status | release <- run by /kit:assign, /kit:start
```

## Tasks

- [ ] TASK-1: `lib/goal-drafts.sh` (archive [--dry-run] / list / dir), shellcheck-clean, executable, mirrors `lib/goal-registry.sh` conventions. AC: archive moves only SHIPPED-target drafts to `done/`, flips their status, leaves specless/live drafts; `--dry-run` moves nothing; re-run is a no-op.
- [ ] TASK-2: Wire `bash lib/goal-drafts.sh archive` into `commands/ship.md` (Step 7b + Step 9 summary line).
- [ ] TASK-3: Remove `INDEX.md` from the LIVE contract (`commands/assign.md`, `WORKFLOW.md`); declare the filesystem the sole source of truth.
- [ ] TASK-4: `docs/decisions/0023-goal-draft-lifecycle.md`; annotate ADR-0011's Status line + SPEC-005's reconcile note (supersede, not rewrite).
- [ ] TASK-5: Side-by-side model in `docs/architecture.md` "## State model" (registry row + draft-vs-registry contrast); lifecycle in `WORKFLOW.md`; `done/`-skip note in `commands/start.md` + `commands/next.md`.
- [ ] TASK-6: This spec.
- [ ] TASK-7: Tests: `tests/test-hooks.sh` goal-drafts round-trip; `tests/test-meta.sh` structural guards (lib exists+exec, no `INDEX.md` in live contract, ADR-0023 exists + ADR-0011 names it, side-by-side names both stores, ship wiring).

## Test

```bash
bash tests/test-hooks.sh    # goal-drafts round-trip passes
bash tests/test-meta.sh     # structural guards pass
grep -rn 'INDEX.md' commands/ WORKFLOW.md   # empty (live contract clean)
grep -A20 '## State model' docs/architecture.md | grep -E 'kit-goals' && grep -A20 '## State model' docs/architecture.md | grep -E '\.claude/goals'  # both stores named
```

## Decision log

- **DEC-001 (fork): INDEX.md removal = supersede + annotate, not in-place rewrite.** SPEC-005 is SHIPPED and ADR-0011 accepted; the kit supersedes decisions (ADR-0010 supersedes ADR-0002) rather than erasing shipped history. Live contract cleaned fully; historical mentions retained as annotated record. Consequence: the goal's literal "grep returns nothing in docs/decisions docs/specs" relaxes to "the LIVE contract is INDEX.md-free." Who: maintainer (2026-05-23).
- **DEC-002 (fork): archive = helper wired into /kit:ship, not auto-run in render commands.** `/kit:start` and `/kit:next` stay read-only detectors (the SPEC-006 detector/mutator split); a read-only command must not mutate the filesystem. The archive runs at the natural mutation point, ship. Who: maintainer (2026-05-23).
- **DEC-003: move, never delete.** Honors the maintainer's standing rule; archiving relocates to `done/` and never overwrites an existing archived copy.

## Failure modes

1. **`target_spec` names a spec that does not exist.** Unresolvable -> draft stays (not archived). No error.
2. **A draft and `done/<slug>.md` share a slug.** Archive refuses to overwrite the archived copy (warns, leaves the top-level draft). Never destroys content.
3. **`/kit:ship` skipped.** Drafts linger until the next `archive`; idempotent, so no harm.
4. **`.claude/goals/` absent (fresh machine).** `archive` and `list` print a graceful "(no goal drafts)" and exit 0.
5. **Spec status mid-flight (VALIDATED, not SHIPPED).** Only `Status: SHIPPED` triggers archive; a still-live spec's draft stays.
