# 0027. Inter-sub-goal context hygiene: distilled returns + operator checkpoint, never self-/clear

Date: 2026-06-29
Status: Proposed
Relates-to: SPEC-087 (the design this records), ops-toolkit token-hygiene mega-goal (the driver), ops-toolkit `research/2026-06-28-token-spend-forensic.md` (the evidence), WORKFLOW.md `## State model` + the execute loop (the accumulation surface), ADR-0022 (multi-session boundary, the prior art on session limits)

## Decision (one line)

The kit reduces a mega-goal run's marathon-context growth two ways, both additive: (1) dispatched subagents return a distilled summary the lead absorbs instead of full output, and (2) the loop emits an operator checkpoint signal at each sub-goal boundary so the operator can `/clear` and resume from POINTER_PROMPT. The kit never self-`/clear`s.

## Context

A mega-goal run is one un-cleared session whose context grows across 6-10h, and the cost of an LLM turn scales with the context re-read each turn (`cache_read`, ~58.5% of measured spend; ops-toolkit `research/2026-06-28-token-spend-forensic.md`). Two kit behaviors feed that growth:

1. **Full subagent returns.** `/kit:execute` fans out 5-9 subagents per sub-goal and the lead absorbs each one's full output. The state flow distils nothing between phases (`WORKFLOW.md:651-652`), and the execute loop re-enters the lead after every increment (`WORKFLOW.md:707-712`), so each 16-25K-token return is permanent context for the rest of the run.

2. **No safe-seam signal.** The loop never marks a point where `/clear` is lossless, so the marathon never breaks into clear-able units.

The obvious fix for (2), a `/clear` inside the loop, is unavailable: clearing the session that drives the loop kills the loop. Whatever the kit does about (2) must keep the loop alive, which means the actual clear is the operator's (or an outer harness's), not the kit's.

## Decision

1. **Return contract (Mechanism 1).** Every kit-dispatched subagent role (worker, task-verifier, integration-checker, reviewer / review-team, research-*) gains a return contract: its final message, the thing the lead absorbs, is a bounded structured summary (`verdict`, `key findings`, `artifacts`, `read-next`), not the full diff / log / transcript. The full output remains recoverable in the subagent's own transcript; the lead pulls detail only when a finding demands it.

2. **Operator checkpoint signal (Mechanism 2).** At a sub-goal boundary (merged-or-held + ROADMAP updated) the loop prints an advisory checkpoint: "safe to `/clear`, resume from POINTER_PROMPT", gated on a POINTER_PROMPT-freshness check so the advised clear is always lossless. The operator or an outer harness performs the clear.

3. **Never self-`/clear`.** The kit emits the signal but never executes the clear; doing so would destroy its own driving context. This is the hard boundary that shapes the whole design.

4. **Strictly additive.** Both mechanisms are convention + prompt + advisory-output changes. No change to the three-store state model, the execute control flow, or any gate. The implementation (token-hygiene SG-04) realizes this; this ADR + SPEC-087 are design only.

## Alternatives considered

- **Self-`/clear` inside the loop.** Rejected: kills the loop's own context. This is the constraint, not an option.
- **Route full subagent output to a side file the lead re-reads on demand.** Rejected (SPEC-087 DEC-001): re-reading is still absorption; distilling at the source is the cheaper token.
- **Rely on the operator runbook (token-hygiene SG-02) alone.** Rejected: the runbook is the manual practice; the structural win needs the kit to shrink returns by default, not by operator vigilance.
- **A hard token budget that aborts the loop.** Rejected: blunt; the goal is lower cost per equivalent run, not a truncated run.

## Consequences

- The lead grows by hundreds of tokens per subagent instead of tens of thousands; each sub-goal becomes a clear-able unit, so `/clear` + resume between sub-goals removes the dominant `cache_read` growth.
- Evidence is preserved: distillation points at the full transcript rather than discarding it.
- Reversible: the change is docs + prompts + one advisory output; reverting the SG-04 diff restores prior behavior with no state migration.
- Success is measurable: a before / after `token-forensic --loops` comparison of an equivalent run (lower `cache_read`/turn and lower total) is the mega-goal's acceptance metric (SPEC-087 AC5).
- Slightly more prose in each dispatched-role definition (the return contract); mitigated by a shared contract shape reused across roles.
