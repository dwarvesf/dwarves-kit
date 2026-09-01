# ADR-0002: .planning/ directory convention (from GSD)

## Status: superseded by ADR-0010 (2026-05-21)

> Superseded: the kit unified onto `docs/specs/` for both itself and downstream
> (ADR-0010). The GSD-interop rationale below is obsolete: current GSD no longer
> uses a single `.planning/SPEC.md`. The hooks keep a bounded `.planning/`
> deprecation fallback for one minor version. The original record is preserved
> below unchanged.

## Context
Spec output needs a predictable location that hooks and commands can reference. GSD uses `.planning/`, other tools use `docs/`, `specs/`, or inline CLAUDE.md sections.

## Decision
Adopted GSD's `.planning/` convention. Spec files live there. Hooks (context-readiness, spec-drift-guard) check for this directory.

## Alternatives considered
- `docs/specs/`: more traditional but buried. Hooks would need deeper path matching.
- Inline in CLAUDE.md: pollutes the main config file. CLAUDE.md should reference specs, not contain them.
- `.gsd/`: too coupled to GSD's specific format. We want our own spec format.

## Consequences
- Compatible with GSD if user also installs GSD (both check .planning/).
- context-readiness hook also checks for `.gsd/` as a fallback.
- Contractors see specs in a predictable location across all Dwarves projects that use the kit's tools.
- **Convention split (added 2026-05-20)**: the kit's hooks/commands write to `.planning/SPEC.md` for the downstream-project case. For the kit ITSELF as a project, specs are drafted directly at `docs/specs/SPEC-NNN-<slug>.md` (matching ops-toolkit `tools/tide/` shape). The `.planning/` to `docs/specs/` migration step is retired for the kit's own work; the file's `Status:` header (DRAFT / VALIDATED / SHIPPED) tracks state in place. Downstream projects that use the kit continue to follow the `.planning/` convention until a future kit refactor unifies the two.
