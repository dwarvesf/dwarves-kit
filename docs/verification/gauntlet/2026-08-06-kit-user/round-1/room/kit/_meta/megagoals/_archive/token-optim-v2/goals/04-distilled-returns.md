# SG-04: distilled subagent returns (Mechanism C)

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: opus
Effort: high

## Directional outcome
Bound the growth INSIDE a single sub-goal: dispatched subagents return a bounded structured
summary, not a full diff/log dump, so the lead grows by hundreds of tokens per subagent instead
of 16-25K.

## Done =
The kit's dispatched-role agent defs (worker, task-verifier, integration-checker, reviewer /
review-team, research-*) carry a return-contract section (`verdict` / `key findings` /
`artifacts` / `read-next`); `/kit:execute` dispatch prose instructs the lead to absorb the
summary and pull detail on demand; full output stays recoverable in the subagent transcript. A
before/after token check (or a structural verification that every role carries the contract) is
recorded. PR opened.

## Close the loop (verification)
```
# every dispatched role carries the contract
grep -L 'return contract\|read-next' agents/{worker,task-verifier,integration-checker,reviewer}.md  # empty = all present
```
Plus, if feasible, a measured dispatch showing a smaller return vs the old shape.

## Scope edges
`agents/*.md` + the `/kit:execute` dispatch prose. Do NOT change any role's tool grants. Don't
discard output, point at the transcript.

## Where to look
SPEC-087 Mechanism C, `agents/`, `commands/` (the execute dispatch), the token-hygiene
distilled-returns design (DEC-001/003).

## Proof expectation
A run-table / the grep above showing the contract in each role; an optional token-delta capture
from a real dispatch. Full reviewable proof.

## PR body
feat(kit): distilled subagent return contract across dispatched roles (Mechanism C). Bounds the
within-sub-goal growth. Gated for team review.

## Borrowed from pi-swarm (2026-06-29)
The return-contract wording is theirs (`spawn.ts:180`): "Report findings IN the record (the summary), not your response text; the lead reads the record." Verdict field uses "Concrete accomplishment with evidence." See `research/2026-06-29-pi-swarm-comparison.md`.

## From the token-efficient note (2026-06-29)
Bake in the decision rule: a subagent is NOT automatically cheaper (a subagent-heavy workflow
can cost ~7x a single thread). Use one only when isolating noise from the main context is worth
the setup overhead , NOT for one-prompt tasks, single tool calls, or when near a rate/budget
limit. See `research/2026-06-28-token-efficient-design.md` Part 1.
