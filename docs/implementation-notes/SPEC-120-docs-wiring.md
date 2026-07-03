# Implementation notes: SPEC-120 (mega-goal delegate docs + no-orphan wiring)

Delta from the spec/goal file only; decisions not already pinned there.

## 2026-07-03 10:20 Spec authored without the /kit:spec research fan-out

Context: this is sub-goal 05 of the `orchestrate-hardening` mega-goal (docs-last).
`/kit:spec`'s Mode A/B research dispatch (research-stack/features/architecture/pitfalls)
exists to map an unfamiliar brownfield area before drafting. This session already read
ADR-0032, all of `lib/orchestrate.sh`'s delegate/token/TIER-4/multiplexer sections, and
the kit-hardening c6fbd99 no-orphan precedent directly (goal file's "Where to look" list).

Decision: wrote SPEC-120 directly against the standard template instead of dispatching
the 4 research subagents.
Why: the research fan-out's value is context-recovery for an area the writer hasn't
read; re-deriving facts already gathered inline would burn the sub-goal's 1-2h budget
re-reading the same file through subagents.
Alternatives: dispatch research agents anyway for form's sake -- rejected, no new
information would result.
Impact: `/kit:spec-validate` (the adversarial 5-lens review) still runs for real against
the drafted spec, so the process's actual safety net (catching a wrong or incomplete
spec before build) is intact; only the research-gathering step was skipped as redundant.

## 2026-07-03 10:25 AGENTS.md gets a pointer, not a new zone

The goal file says "AGENTS.md gain (or correct) the sections". AGENTS.md's own text pins
its four zones as stable ("Keep the four zone names stable; renaming one ... breaks the
projection") and explicitly defers "how the pieces fit" to WORKFLOW.md/architecture.md as
"reference, not required per task" (zone 1, item 4).

Decision: added ONE sentence to zone 1 item 4 pointing at WORKFLOW.md's new
"Mega-goal delegate execution" section, rather than a new zone or a duplicated
description of the delegate model in AGENTS.md itself.
Why: avoids re-documenting `/goal` internals in two places (the goal file's own `Not:`
list bars "re-documenting /goal internals the kit does not own"); WORKFLOW.md stays the
single source of the delegate-model prose.
