# 0027. Inter-sub-goal context hygiene: move the loop out of the LLM session (non-LLM orchestrator)

Date: 2026-06-29
Status: Proposed
Relates-to: SPEC-087 (the design this records), ops-toolkit token-hygiene mega-goal (the driver), ops-toolkit `research/2026-06-28-token-spend-forensic.md` (the evidence), WORKFLOW.md `## State model` + the execute loop (the accumulation surface), ADR-0022 (multi-session boundary, the prior art on session limits)

## Decision (one line)

A mega-goal run stops being one un-cleared marathon by moving the loop OUT of the LLM session: a non-LLM orchestrator runs each sub-goal in a fresh `claude -p` session (so the `/clear` is free), each session writes a feed-forward `HANDOFF.md` for the next (so the fresh start skips re-discovery), and inside a sub-goal the dispatched subagents return distilled summaries. The kit never self-`/clear`s, and the orchestrator halts at gate sub-goals.

## Context

A mega-goal run is one un-cleared session whose context grows across 6-10h, and the cost of an LLM turn scales with the context re-read each turn (`cache_read`, ~58.5% of measured spend; ops-toolkit `research/2026-06-28-token-spend-forensic.md`). Three behaviors feed the growth:

1. **One marathon session.** The `/goal` loop runs every sub-goal in a single session whose context only grows.
2. **Full subagent returns.** `/kit:execute` fans out 5-9 subagents per sub-goal and the lead absorbs each one's full output (`WORKFLOW.md:651-652`, `707-712`); each 16-25K-token return is permanent context for the rest of the run.
3. **Re-discovery tax.** Each step re-finds context an earlier step already knew, because nothing is handed forward (operator observation, 2026-06-29).

This ADR's v1 proposed an advisory "safe to /clear" signal that a human performs. Rejected on review (Han, 2026-06-29): a human-in-the-middle clear defeats the kit's reason to exist (unattended automation). The clear that the kit cannot do to itself, an outer driver can do for free by simply starting a new session.

## Decision

1. **Non-LLM orchestrator (Mechanism A).** A dumb driver (`lib/queue/orchestrate.sh`, bash; the Agent SDK is the upgrade path) owns the loop and runs each sub-goal in a fresh `claude -p` session. No session holds more than one sub-goal's context, so the marathon growth is gone. The driver MUST NOT be an LLM context: an LLM orchestrator spawning a subagent per sub-goal would re-accumulate every return and become the new marathon. This is the load-bearing call.

2. **Feed-forward handoff (Mechanism B).** Each sub-goal session writes a grounded `HANDOFF.md` (next sub-goal, files/symbols already located, fixed constraints, open risks); the orchestrator injects it into the next session's prompt, turning re-discovery into a read. It is dynamic and per-transition, distinct from the static `POINTER_PROMPT.md`, and the receiver verifies before trusting.

3. **Distilled subagent returns (Mechanism C, phase 2).** Within a sub-goal, each dispatched role returns a bounded structured summary (`verdict`, `key findings`, `artifacts`, `read-next`) instead of full output; the full output stays recoverable in the transcript. Bounds the within-sub-goal growth that the orchestrator does not touch.

4. **Gate sub-goals halt the orchestrator; the kit never self-`/clear`s.** The auto chain runs unattended; a shared-repo (`gate`) sub-goal stops the loop for team review. The kit emits no `/clear` against its own session.

5. **Additive.** No change to the three-store state model, the execute control flow, or any gate. The interactive `/goal` loop still works for hands-on runs; the orchestrator is an additional outer driver.

6. **Carve-out from ADR-0022's goal-ordering-chain fence.** ADR-0022 keeps goal-ordering chains (B waits for A to merge) at L5, and the README says the kit stops short of a DAG scheduler / coordinating daemon / cross-machine orchestration. This orchestrator runs sub-goals in order and advances on a checkbox flip, which is a *linear* ordering chain, so the boundary must be argued, not assumed. It is in scope because it is narrowly bounded: ONE mega-goal, ONE machine, a one-shot script (not a daemon), strictly LINEAR (not a DAG, no parallel fan-out), and it HALTS at the first gate (it never auto-crosses a shared-repo merge). What stays fenced at L5 / out of scope is unchanged: cross-repo or cross-machine coordination, 3+ concurrent operators, parallel DAG fan-out, and any always-on supervising daemon. The orchestrator is the linear-single-mega-goal slice of that space, deliberately the smallest thing that removes the marathon.

## Alternatives considered

- **Operator checkpoint signal (this ADR's v1).** Rejected: needs a human to perform the clear; defeats the automation premise.
- **LLM orchestrator that spawns a subagent per sub-goal.** Rejected (DEC-004): the orchestrating session re-accumulates every return and becomes the new marathon. The driver must be dumb.
- **Self-`/clear` inside the loop.** Rejected: kills the loop's own driving context.
- **Route full subagent output to a side file the lead re-reads.** Rejected: re-reading is still absorption; distilling at the source is cheaper.
- **A hard token budget that aborts the loop.** Rejected: blunt; the goal is lower cost per equivalent run, not a truncated run.

## Consequences

- The dominant cost driver (a context that grows for hours and is re-read every turn) is removed structurally, not trimmed: each sub-goal runs in a near-fresh session.
- A bounded cold-start tax replaces it (each fresh session reloads CLAUDE.md + pointer + handoff, a few K tokens); the grounded handoff keeps it small. Net win is large and measurable via `token-forensic --loops` (before / after an equivalent run).
- Reversible: the orchestrator is additive bash + a doc convention; removing it restores the in-session loop with no state migration.
- The orchestrator is harder to watch live than one session, but yields one clean transcript per sub-goal (better post-hoc forensics).
- Evidence preserved throughout: handoffs and distilled returns point at full artifacts rather than discarding them.
