# ADR-0010: Unify the spec-location convention onto docs/specs/ (supersedes ADR-0002)

## Status: accepted (2026-05-21). Supersedes ADR-0002.

## Context
ADR-0002 split the spec location: downstream projects wrote `.planning/SPEC.md` (GSD lineage), the kit itself wrote `docs/specs/SPEC-NNN-<slug>.md`. The stated reason to keep `.planning/` downstream was GSD interop ("both check `.planning/`").

The mid-2026 SDD-convention research (see SPEC-010) makes the split obsolete:
1. The kit already uses `docs/specs/SPEC-NNN` for itself, and the field standard is now multi-spec directories (Spec Kit, OpenSpec, Agent OS, gsd-2 all use per-feature/per-change dirs). This reason stands on its own.
2. Current GSD no longer uses a single `.planning/SPEC.md` (it uses `.planning/phases/`), so the interop argument is moot. (The exact GSD version of the switch is unconfirmed, a post-cutoff web finding; the decision does not hinge on it.)

## Decision
One convention everywhere: `docs/specs/SPEC-NNN-<slug>.md` for both the kit and downstream. Satellite artifacts map flat + shared: research -> `docs/research/`, retro -> `docs/retro/`, CONTEXT -> `docs/specs/CONTEXT.md`, decision-brief folded into the spec's Decision-brief section (transient handoff at `docs/specs/DECISION-BRIEF.md`).

The 5 spec-aware hooks resolve the active spec from `docs/specs/` (interim selector: highest-numbered non-SHIPPED/PARKED `SPEC-NNN`; SPEC-005 dual-detect later refines this to branch-based) and fall back to legacy `.planning/SPEC.md` with a deprecation warning for one minor version, after which the fallback is removed.

## Alternatives considered
- **Hard cut** (remove `.planning/` immediately): breaks existing downstream projects on upgrade; rejected in favor of a bounded deprecation window.
- **OpenSpec two-tree** (`changes/` deltas + canonical `specs/`): solves the latent fragmentation problem but is a heavier, different storage model; deferred (revisit if fragmentation bites).
- **Per-spec subdirs** (Spec Kit style, `docs/specs/SPEC-NNN-slug/{spec,context,research}`): groups each cycle's working set but changes the kit's own flat single-file convention; rejected in favor of flat + shared.

## Consequences
- One convention; no kit-vs-downstream split. Less confusion (the split confused even the maintainer).
- Existing downstream `.planning/` projects keep working for one deprecation window; migration is a one-liner: `mv .planning/SPEC.md docs/specs/SPEC-001-<slug>.md`.
- The `.gsd/` handling from ADR-0002 is retained where present; current GSD's `.planning/phases/` is not read by the kit, so there is no collision with `docs/specs/`.
- Worktree concurrency: each git worktree carries its own `docs/specs/` (working-tree-native isolation); kit state is namespaced per worktree. Orchestrating parallel worktrees stays external (gsd-2 / Agent Teams), per PHILOSOPHY one-session.
- The interim active-spec selector is not branch-aware until SPEC-005 (dual-detect) ships.

## Source
SPEC-010 (the spec that drove this), the mid-2026 SDD-convention research, and ADR-0002 (superseded).
