# Implementation notes: SPEC-143 stale-adr-inversion

No deviations; matches the sub-goal contract
(`ops-toolkit/_meta/megagoals/gate-review-absorptions/goals/01-stale-adr-inversion.md`)
verbatim on scope and the 3 surfaces.

One placement decision the contract left to the worker's judgment, recorded here since
it is not already pinned upstream:

- **Where inside `commands/review-team.md` to inject the rule.** The contract names the
  file as a surface but not which of its several dispatch-prompt blocks (security,
  architecture, test-coverage, advisor Step 2b) should carry the rule. Picked the
  Architecture-lens dispatch prompt (Reviewer 2), because (a) it is the one block that
  already partially implies reading intent docs via its "Architecture context" input and
  the deep-module vocabulary's structural framing, and (b) the `advisor` agent dispatched
  from Step 2b loads `agents/advisor.md` as its own system prompt when invoked by name
  through the Task tool, so it already inherits the rule from surface 1 and does not need
  a second copy inside `review-team.md`'s short Step 2b prompt text -- adding it there
  too would be the duplicate-injection the contract's Quality bar rules out ("one rule,
  stated once per surface"). Security and test-coverage lenses were left untouched: the
  rule is about spec/ADR-vs-code drift, which is architecture's territory, not
  security's or test-coverage's.
