# audit-verdict-grammar: implementation notes

Delta from the brief. No spec backs this change.

## Decisions

- The five-word rule lives once, in `docs/patterns/audit-loop.md` under "Verdict grammar". Skills point at it and carry no copy. The new suite counts the rule sentence at exactly one.
- memory-tidy: `KEEP` is `OK (keep)`, `MERGE` is `REMOVE (merged into <sibling>)`, `STALE` is `REMOVE (stale)`. The evidence column text is unchanged, so the other pins in its contract suite still hold. Only row 8 changed.
- backlog-reconcile sweep: `DONE` is `REMOVE (done: ...)` and applies `shipped`. `OBSOLETE` and `DUPLICATE` are `REMOVE (...)` and apply `dropped`. `HAN` is `UNSURE (han: ...)`. `KEEP` is `OK (keep)`. The PR body groups OK and UNSURE rows by reason, as the old buckets did.
- backlog-reconcile spec check compares classes. Board classes come from `states --class`; spec classes are open (DRAFT, APPROVED, VALIDATED) and closed (SHIPPED, PARKED). One contradiction flags: spec closed while the board row is active. Any shipped row with an open spec is header lag, and a dropped row with a DRAFT spec is abandoned work, so neither flags.
- web-drift keeps its separate report group for sites that did not answer. It is now an `UNSURE (untestable)` group inside the UNSURE list. The action is the same: re-run later, never escalate as a question.
- gauntlet-proof-audit: the apply cell said a flagged discrepancy gets a correction note, while Step 6 said only DANGER does. Step 6 won, so the cell now reads "reported as FIX, and a DANGER one also gets a dated correction note". This is a wording fix to match the actual action.
- greenlight: `stop_waiting_review` is gone from the prose. Phase B stays named as unbuilt; SPEC-019 still carries the state for when Phase B lands.
- dispatch: workers write only `STATUS: READY` or `STATUS: BLOCKED`. FAILED is the lead's reading of a reported error. DISCONNECTED is an attempt-state value.
- audit-scanner agent: `UNTESTABLE` is no longer a verdict or a column in its report. The rule reads `UNSURE (untestable)`, never REMOVE, and the contract suite pins it.
