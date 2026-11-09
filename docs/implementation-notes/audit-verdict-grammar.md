# audit-verdict-grammar: implementation notes

Delta from the brief. No spec backs this change.

## Decisions

- The five-word rule lives once, in `docs/patterns/audit-loop.md` under "Verdict grammar". Skills point at it and carry no copy. The new suite counts the rule sentence at exactly one.
- memory-tidy: `KEEP` is `OK (keep)`, `MERGE` is `REMOVE (merged into <sibling>)`, `STALE` is `REMOVE (stale)`. The evidence column text is unchanged, so the other pins in its contract suite still hold. Only row 8 changed.
- backlog-reconcile sweep: `DONE` is `REMOVE (done: ...)` and applies `shipped`. `OBSOLETE` and `DUPLICATE` are `REMOVE (...)` and apply `dropped`. `HAN` is `UNSURE (han: ...)`. `KEEP` is `OK (keep)`. The PR body groups OK and UNSURE rows by reason, as the old buckets did.
- backlog-reconcile spec check compares classes. Board classes come from `states --class`; spec classes are open (DRAFT, APPROVED, VALIDATED) and closed (SHIPPED, PARKED). Two contradictions flag: spec closed with a board row in an active state, and a board row in a terminal state with a DRAFT spec. An APPROVED spec with a shipped row does not flag, same reason as VALIDATED.
- web-drift keeps its separate report group for sites that did not answer. It is now an `UNSURE (untestable)` group inside the UNSURE list. The action is the same: re-run later, never escalate as a question.
- gauntlet-proof-audit: the apply cell said a flagged discrepancy gets a correction note, while Step 6 said only DANGER does. Step 6 won, so the cell now reads "reported as FIX, and a DANGER one also gets a dated correction note". This is a wording fix to match the actual action.
- greenlight: `stop_waiting_review` is gone from the prose. Phase B stays named as unbuilt; SPEC-019 still carries the state for when Phase B lands.
- dispatch: workers write only `STATUS: READY` or `STATUS: BLOCKED`. FAILED is the lead's reading of a reported error. DISCONNECTED is an attempt-state value.

## Tradeoff

A `dropped` row with a DRAFT spec now flags in Tier 1, because `dropped` is in the terminal class. The Tier 2 scanner judges it OK (an abandoned draft is legitimate). Narrowing Tier 1 to `shipped` would put a board word back in the skill, which is the thing this change removes.

## Open questions

- `agents/audit-scanner.md` (not in this slice) still lists `UNTESTABLE` as a verdict in its output table and says "UNTESTABLE, never REMOVE". `tests/test-audit-scanner-contract.sh` pins that text. It now disagrees with `audit-loop.md`. Fix both together in the slice that owns the agent.
