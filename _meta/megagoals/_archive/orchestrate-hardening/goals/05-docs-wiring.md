# Sub-goal 05: docs + wiring (the delegate run model, honestly)

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table: WORKFLOW.md + AGENTS.md describe the DELEGATE run model + the ledger-under-delegation guarantee (gate/proof by construction, token via stream-to-file, debt split) + the opt-in multiplexer option · the NO-ORPHAN wiring check confirms each documented capability has a LIVE dispatch path (the `Model:`->`--model` routing fires, the token stream-to-file records, the TIER-4 close runs, a pane spawns when enabled) · negative control: a documented-but-unwired claim (or an over-claim, e.g. "multiplexer on by default" when it is off) is a CAUGHT finding (mirrors kit-hardening c6fbd99).
**Depends on:** ALL (01-04; docs-last, reflect the final wired state , the kit-face lesson).
Model: sonnet
Effort: medium
**Branch:** feat/oh-05-docs
**PR base:** feat/oh-04-multiplexer

## Outcome

The kit's operate-contract docs describe the hardened delegate run model truthfully: WORKFLOW.md + AGENTS.md gain (or correct) the sections covering the DELEGATE run mode (thin conductor, plain `-p`, per-sub-goal model routing), the ledger-under-delegation guarantee (gate/proof survive by construction, token via stream-to-file, debt split conductor/worker), the mega TIER-4 close, and the OPT-IN multiplexer. Every claim is backed by a LIVE dispatch path , the no-orphan wiring check (kit-hardening c6fbd99 bug class) runs over the whole wave: the `Model:` field actually reaches `--model` (01), token capture actually records under delegation (02), the TIER-4 close actually runs the verifiers (03), and a pane actually spawns when the multiplexer is enabled (04). A documented-but-unwired capability or an over-claim (e.g. describing the multiplexer as default-on) is a blocking finding. If a plan-for-mega-goal pointer-template touch is needed it is a dotfiles half (edit chezmoi source, apply, stage+commit in ONE call).

## Quality bar

Honesty over completeness (the c6fbd99 lesson) , claim only what dispatches. Docs LAST so they reflect the final wired state (all of 01-04 shipped), not a mid-wave snapshot. State the hard rules plainly: `/goal` stays the official outer loop (delegate changes what it does, not the runner); `--stream` only to a FILE, never to the conductor; the multiplexer is opt-in / off by default.

## How to close the loop

`/spec` + `/spec-validate` first. Then `bash tests/test-docs-wiring.sh` (WORKFLOW.md + AGENTS.md describe the delegate model + ledger guarantee + multiplexer) + the no-orphan sweep over the wave's artifacts (routing-fires -> token-records -> TIER-4-runs -> pane-spawns) + the over-claim NC (a default-on multiplexer claim, or any documented-but-unwired capability, is caught). Assumptions: ROADMAP 05.

**Done =** WORKFLOW.md + AGENTS.md truthfully describe the delegate run model + the ledger-under-delegation guarantee + the opt-in multiplexer, the no-orphan sweep confirms every claim dispatches (routing, token, TIER-4, pane), the over-claim NC is caught, tests green.

## Scope edges

**In:** the WORKFLOW.md + AGENTS.md sections (delegate run model, ledger-under-delegation guarantee, multiplexer option), the no-orphan wiring check, any dotfiles pointer-template half, tests.
**Out:** the machinery (01-04); the mega-goal ROADMAP (already written).
**Not:** claiming a capability operational that nothing dispatches (the c6fbd99 over-claim class); describing the multiplexer as default-on (it is opt-in); re-documenting `/goal` internals the kit does not own (ADR-0017 activator-agnostic stands).

## Where to look

`WORKFLOW.md` + `AGENTS.md` (the operate-contract docs to update), the kit-hardening `c6fbd99` fix (the no-orphan / over-claim precedent, and WORKFLOW.md's prior over-claim), ADR-0032 (the run model to describe , the source of truth), the plan-for-mega-goal skill + its pointer template (a possible dotfiles half), all of 01-04's shipped artifacts (what actually dispatches , the no-orphan sweep reads these).

## PR body

Docs + wiring: WORKFLOW.md + AGENTS.md describe the hardened DELEGATE run model + the ledger-under-delegation guarantee (gate/proof by construction, token via stream-to-file, debt split) + the opt-in multiplexer , claiming only what dispatches, plus the no-orphan wiring check (routing fires -> token records -> TIER-4 runs -> pane spawns). Executes ADR-0032. Stacked on #<04's PR>; final PR of the mega-goal, HELD for Han. Verify: `bash tests/test-docs-wiring.sh` (docs present + no-orphan sweep + over-claim NC). Roadmap: ops-toolkit `_meta/megagoals/orchestrate-hardening/ROADMAP.md`.

## Notes

<empty>
