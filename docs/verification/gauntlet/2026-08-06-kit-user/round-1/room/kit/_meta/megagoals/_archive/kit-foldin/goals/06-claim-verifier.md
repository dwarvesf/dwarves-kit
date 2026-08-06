# Sub-goal 06: claim-verifier

**Merge policy:** auto (FLAGGED: Han may flip to `gate` , the fan-out agent's behavior is a taste call he may want to eyeball before merge)
**Time budget:** 3-5 hours of loop work
**Proof:** run-table + agent-effectiveness pass , the new `agents/claim-verifier.md` has valid kit frontmatter (dispatch a `kit:agent-effectiveness` lens over it), AND a smoke dispatch on a committed fixture claim returns a STRUCTURED verdict (majority vote across N skeptics, default-refute-if-uncertain). COVERAGE-DELTA row. Rung 3 (a fresh-context recheck confirms the smoke dispatch is real, not a described intention); LLM output is nondeterministic so the proof is "well-formed agent + a real dispatch returned a structured verdict", not an exact-value assertion.
**Design:** bearing (this is NOT a file move , it REDESIGNS the current N-parallel-`claude -p`-subprocess script as an agent that itself fans out N in-harness skeptic dispatches; the fan-out contract is a real design decision , the spec owes a `## Design` block)
**Depends on:** none (writes only `agents/`)
Model: opus
**Effort:** high
**Branch:** feat/kit-foldin-06-claim-verifier
**PR base:** master

## Outcome

The adversarial claim panel (was `tools/verify-claim`, an N-parallel-`claude -p` skeptic CLI) becomes a first-class kit subagent `dwarves-kit/agents/claim-verifier.md`. It takes an ARBITRARY free-text claim and runs it through N independent skeptics (default-refute-if-uncertain, majority vote) , but the mechanism is redesigned: instead of a bash script spawning N headless `claude -p` subprocesses, the agent itself fans out N in-harness skeptic dispatches and aggregates the verdict. It fills a real gap , confirmed NO existing kit verify-shaped agent does this (the others re-execute/critique a SPECIFIC code/spec/task/doc artifact; this judges an arbitrary claim).

## Quality bar

It reads like it was designed for the kit, not ported. The fan-out is honest: N genuinely-independent skeptic perspectives, each told to REFUTE, fail-closed (any hedge or garble counts as a finding). The verdict is structured and auditable (how many refuted, the threshold, the reasoning), not a vibe. A user dispatches it the way they dispatch `kit:advisor` , one clean entry, structured result.

## How to close the loop

- Read `ops-toolkit/tools/verify-claim/` (the current CLI + its N-`claude -p` panel) to capture the intended behavior.
- Design the agent's fan-out contract (Design: bearing , spec it): N skeptics (name the default N), how each is prompted to refute, how the majority threshold is expressed, whether it reuses a `kit:code-reviewer`-style dispatch or a bespoke panel. Resolve the open detail flagged in NOTES ## Proposed additions.
- Write `agents/claim-verifier.md` in the kit's exact agent frontmatter + structure (use `agents/advisor.md` + `agents/meta-agent.md` as the shape reference).
- Commit a fixture claim under `tests/fixtures/` (a clearly-false claim so the smoke has a determinable-ish expectation).
- Smoke: dispatch the agent on the fixture claim, capture the structured verdict.
- `kit:agent-effectiveness` lens over the new def (tools minimal-yet-sufficient, description triggers right, instructions produce a good result, model tier fits).

Kit-adopted: record build + review (+ recheck) via `bash lib/gate-ledger.sh`; this is design-bearing so the spec + `/kit:spec-validate`-equivalent Design block is required.

**Done =** `agents/claim-verifier.md` passes the agent-effectiveness lens AND a smoke dispatch on the fixture claim returns a structured majority-vote verdict, captured in `docs/proof/kit-foldin-claim-verifier.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 retires `ops-toolkit/tools/verify-claim` (status=moved -> kit agent).
3. DECISIONS.md: record the fan-out contract (N, threshold, dispatch style) , it is the durable design.
4. Report in records, EXIT.

## Scope edges

**In:** `dwarves-kit/agents/claim-verifier.md`, its fixture + smoke, the spec/Design record.
**Out:** `lib/`, `hooks/`, `tools/`; the ops retire (SG-07); the other reviewer agents (do not touch existing ones).
**Not:** porting the bash `claude -p` subprocess mechanism verbatim (it is being REPLACED by in-harness fan-out); adding it to `/kit:review-team`'s default lens set (that is a separate later call); building a CLI wrapper (it is a subagent, dispatched, not a bin).

## Where to look

`ops-toolkit/tools/verify-claim/`, `dwarves-kit/agents/{advisor,meta-agent,recheck-verifier}.md` (shape + fan-out reference), the design note's open-Q 2 (RESOLVED: no duplicate, real redesign).

## PR body

New kit subagent `agents/claim-verifier.md` , redesigns verify-claim's N-`claude -p` skeptic panel as an in-harness fan-out (majority-vote, default-refute) over an arbitrary free-text claim. Fills a confirmed gap (no existing kit agent judges arbitrary claims).

Verify: agent-effectiveness lens passes + smoke dispatch on a fixture claim returns a structured verdict. Proof: `docs/proof/kit-foldin-claim-verifier.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
