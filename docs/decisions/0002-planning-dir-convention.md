# ADR-0002: .planning/ directory convention (from GSD)

## Status: accepted

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
- Contractors see specs in a predictable location across all Dwarves projects.
- Historical archive of shipped specs lives in `docs/specs/SPEC-NNN-<slug>.md`. `.planning/` is for in-flight work; `docs/specs/` is for the record. Migration of a shipped spec is a manual step at release time.
