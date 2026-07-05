# ADR 0003: per-session trigger, reusing cc-harvest's PreCompact/SessionEnd events

**Date:** 2026-06-19
**Status:** accepted (SPEC-103 DEC-006; the reframe that defines the tool's scope)

## Context

The original plan was a full Hermes clone: a per-turn reviewer that captures BOTH memory and skills
every ~10 turns. While planning, we found cc-harvest already ships the memory half (transcript ->
learnings -> ledger) on PreCompact/SessionEnd. A per-turn memory+skill reviewer would duplicate the
most expensive, already-built piece.

## Decision

cc-self-improve is the SKILL half only. Its reviewer fires on **PreCompact / SessionEnd** (its own
hook entry, the same events cc-harvest already uses), which maps faithfully to Hermes's *skill nudge*
(per substantial chunk of work, not per literal turn). The per-turn MEMORY cadence is added to
cc-harvest instead (its `--stop-trigger`), not here.

## Alternatives considered

- **Per-turn reviewer for both memory and skills (the original clone).** Rejected: duplicates shipped
  cc-harvest, and a per-turn skill reviewer would be the most expensive piece for the least signal
  (most turns produce no reusable skill).
- **Fold everything into cc-harvest.** Rejected: cc-harvest is memory-scoped, stable, and merged;
  skill authoring + curation is a different concern that would risk regressing it.

## Trade-offs

Two tools to keep coordinated instead of one. Mitigated by one shared cost ledger schema and one
SessionStart surfacing line that reads both. The split is also *more* faithful to Hermes's actual
dual-cadence design than "per-turn for everything" would have been.

## Open questions

None. The suite-level parity (memory + skill) is asserted at the cc-elevation-r4 mega-goal, not in
this tool's own acceptance.
