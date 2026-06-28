# SPEC-087: Inter-sub-goal context hygiene (distilled returns + checkpoint signal)

Status: DRAFT
Date: 2026-06-29
Lane: normal (classified: normal)
Type: design (design-only; implementation is a follow-up, token-hygiene SG-04)
Board: token-hygiene mega-goal SG-03 (ops-toolkit `_meta/megagoals/token-hygiene/`); kit intake ID operator-assigned

## Problem

A mega-goal run under the kit is one un-cleared session whose context grows monotonically
across 6-10h. Two structural drivers:

1. **Full subagent returns.** `/kit:execute` dispatches 5-9 subagents per sub-goal (workers,
   task-verifiers, reviewers) and the lead absorbs each one's FULL output. The kit's own
   state flow shows three stores with nothing distilled between phases
   (`WORKFLOW.md:651-652`); the execute loop re-enters the lead after every increment
   (`WORKFLOW.md:707-712`). A 16-25K-token return per subagent, multiplied across a sub-goal,
   lands permanently in the lead context.

2. **No clear-able boundary.** The loop never signals a safe seam to `/clear`. Cost is
   dominated by `cache_read`: the whole accumulated context is re-read every turn (~58.5% of
   spend; ops-toolkit `research/2026-06-28-token-spend-forensic.md`). The longer the
   un-cleared marathon, the more each turn costs.

The kit cannot fix (2) by self-clearing: a `/clear` inside the loop kills the loop's own
driving context. So the design centers on (a) shrinking what the lead absorbs per subagent
and (b) emitting an operator signal at each safe seam, leaving the actual `/clear` to the
operator or an outer harness.

## Design

### Mechanism 1: distilled subagent returns (return contract)

Subagent definitions and the dispatch convention gain a **return contract**: a subagent's
final message (the value the lead absorbs) is a bounded, structured summary, not the full
diff / log / transcript.

- Structured fields: `verdict` (pass / fail / inconclusive), `key findings` (a few bullets),
  `artifacts` (paths or refs where the full detail lives), `read-next` (the one slice the
  lead should pull IF a finding needs more).
- The full output is not lost: it stays in the subagent's own transcript
  (`agent-<id>.jsonl` / the task output file), recoverable on demand. The lead absorbs the
  summary and pulls detail only when a finding requires it.
- Applies to the kit's dispatched roles: worker (execute), task-verifier,
  integration-checker, reviewer / review-team, research-* (spec). Each role's agent
  definition states its return-contract shape.

Effect: the lead grows by a few hundred tokens per subagent instead of 16-25K.

### Mechanism 2: post-sub-goal checkpoint signal

At a sub-goal completion boundary (sub-goal merged-or-held AND its ROADMAP line updated), the
loop emits an explicit operator signal:

```
Sub-goal NN complete (PR #N). Context checkpoint.
  Safe to /clear now; resume by pasting POINTER_PROMPT.md into a fresh /goal.
  POINTER_PROMPT freshness: <verified current | STALE: update before clearing>.
```

- The signal is advisory: the kit prints it; the operator or an outer harness performs the
  `/clear` + resume. The kit never self-clears.
- Precondition guard: before advising `/clear`, the loop checks that POINTER_PROMPT.md +
  ROADMAP.md encode enough to re-bootstrap losslessly (the resume contract). If
  POINTER_PROMPT is stale, the signal says STALE and the loop refreshes it (or asks the
  operator) instead of advising a lossy clear.
- This makes each sub-goal a clear-able unit: `/clear` + POINTER_PROMPT resume between
  sub-goals kills the monotonic growth (the #1 cost driver) without losing the thread.

### Where it lives (impl pointers for SG-04, not built here)

- Return contract: the dispatched-role agent definitions (`agents/*.md`: worker,
  task-verifier, integration-checker, reviewer) plus the dispatch prose in `/kit:execute` and
  `WORKFLOW.md`.
- Checkpoint signal: the sub-goal-boundary step of the mega-goal loop (`plan-for-mega-goal` /
  the `/goal` loop's sub-goal-complete path) plus a POINTER_PROMPT freshness check.

## Acceptance criteria (for the SG-04 implementation)

- AC1: Each kit-dispatched subagent role's definition carries a return-contract section
  bounding its final message to a structured summary + artifact pointers, not full output.
- AC2: `/kit:execute` and the dispatch prose instruct the lead to absorb the summary and pull
  detail on demand only.
- AC3: A sub-goal-boundary checkpoint signal is emitted (advisory, operator-performed
  `/clear`), gated on a POINTER_PROMPT freshness check.
- AC4: The kit never self-`/clear`s; verified by inspection (no `/clear` emitted as an
  executed command in the loop).
- AC5: A before / after `token-forensic --loops` comparison of an equivalent mega-goal run
  shows lower `cache_read`/turn and lower total (the mega-goal's success metric).

## Verification

```
# in the dwarves-kit checkout
ls docs/specs/ | grep -i context-hygiene      # SPEC present
ls docs/decisions/ | grep -i context-hygiene  # ADR present
```

Design-only; the behavioral verification (AC5) is owned by the SG-04 implementation PR.

## Out of scope

- The implementation itself (token-hygiene SG-04).
- Self-clearing inside the loop (rejected: kills the loop's own context; see ADR-0027).
- Changing the three-store state model or the execute loop's control flow. This is additive
  (what the lead absorbs + an advisory signal), not a re-architecture.

## Decision log

- DEC-001: Distill returns rather than route subagent output to a side file the lead must
  re-read. Rationale: the cheapest token is the one never absorbed; a structured summary is
  the absorption.
- DEC-002: Checkpoint is an operator signal, not a self-`/clear`. Rationale: the kit cannot
  clear its own driving context without killing the loop. The operator or outer harness owns
  the clear; the kit owns the safe-seam signal + resume contract.
- DEC-003: Full output stays recoverable in the subagent transcript, not discarded.
  Rationale: honesty + debuggability; distillation must not destroy evidence.

## Open questions

- OQ-001: Does the checkpoint signal belong in `plan-for-mega-goal`, the built-in `/goal`
  loop, or a kit hook? Resolved at SG-04 impl by where the sub-goal boundary is observable.
- OQ-002: Exact return-contract field set + length bound per role. Tuned at impl; AC1 fixes
  the shape, not the numbers.
