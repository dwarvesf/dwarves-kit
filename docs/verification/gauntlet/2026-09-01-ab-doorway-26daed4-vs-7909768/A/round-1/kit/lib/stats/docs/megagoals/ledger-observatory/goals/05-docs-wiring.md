# Sub-goal 05: docs + wiring (the tool, honestly)

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table: `tools/ledger-observatory/` has a README + a co-located `docs/proof-of-done.md` (ops-tool-shape/ops-tool-docs shape) + a tool.toml/MANIFEST row · the NO-ORPHAN wiring check confirms each artifact has a LIVE invocation path (the render skill fires on its triggers; the `ledger` CLI is actually invoked by the skill; work-intake actually receives a proposed row from 04) · negative control: a documented-but-unwired claim (or an over-claim) is a caught finding (mirrors kit-hardening c6fbd99).
**Depends on:** ALL (01-04; docs-last, reflect the final wired state , the kit-face lesson).
Model: sonnet
Effort: medium
**Branch:** feat/lo-05-docs
**PR base:** feat/lo-04-feedback

## Outcome

The tool's front docs land truthfully: `tools/ledger-observatory/README.md` (front door: what it is, the read-only-lens contract, the `ledger show/query/rebuild` commands, the render skill, the feedback loop) + a co-located `docs/proof-of-done.md` in the table-first review format (SPEC-016), shaped per `ops-tool-shape` (structure) then `ops-tool-docs` (content). Plus the `tool.toml` + `MANIFEST.md` topology row. Every claim is backed by a LIVE invocation path , the no-orphan wiring check (kit-hardening c6fbd99 bug class) runs over the whole wave: the render skill actually fires on its triggers, the skill actually calls the `ledger` CLI, and 04 actually hands work-intake a proposed row. A documented-but-unwired artifact or an over-claim is a blocking finding.

## Quality bar

Honesty over completeness (the c6fbd99 lesson) , claim only what dispatches. Docs LAST so they reflect the final wired state, not a mid-wave snapshot. The read-only-lens + files-canonical contract is stated plainly (the tool never mutates a ledger; delete-and-rematerialize).

## How to close the loop

`/spec` + `/spec-validate` first. Then `bash tests/test-docs-wiring.sh` (the tool has README + proof-of-done + tool.toml/MANIFEST row) + the no-orphan sweep over the wave's artifacts (skill-fires -> CLI-invoked -> work-intake-fed) + the over-claim NC. Follow `ops-tool-shape` then `ops-tool-docs`. Assumptions: ROADMAP 05.

**Done =** README + co-located proof-of-done + tool.toml/MANIFEST row land in the ops-tool-shape/docs shape, the no-orphan sweep confirms every claim dispatches (skill fires, CLI invoked, work-intake fed), the over-claim NC is caught, tests green.

## Scope edges

**In:** `tools/ledger-observatory/README.md`, `docs/proof-of-done.md`, `tool.toml` + the `MANIFEST.md` row, the no-orphan wiring check.
**Out:** the machinery (01-04); the mega-goal ROADMAP (already written).
**Not:** claiming an artifact operational that nothing dispatches; a doc surface the tool does not need; re-documenting the ledgers' producers (out of scope , this tool reads them).

## Where to look

the `ops-tool-shape` + `ops-tool-docs` skills (structure then content), `tools/tide/` (the canonical doc voice + shape , read, do not copy), `tools/icy-ops/` + `tools/growatt-pull/` (proof-of-done shape for a read-only tool + a multi-feature index), `_meta/INVENTORY.md` + `MANIFEST.md` (the topology rows), the kit-hardening c6fbd99 fix (the no-orphan precedent), all of 01-04's shipped artifacts (what actually dispatches).

## PR body

Docs + wiring: `tools/ledger-observatory/` README + co-located proof-of-done (ops-tool-shape/ops-tool-docs shape) + tool.toml/MANIFEST row, plus the no-orphan wiring check (render skill fires -> `ledger` CLI invoked -> work-intake fed). Claims only what dispatches. Stacked on #<04's PR>; final PR of the mega-goal, HELD for Han. Verify: `bash tests/test-docs-wiring.sh` (docs present + no-orphan sweep + over-claim NC). Roadmap: ops-toolkit `_meta/megagoals/ledger-observatory/ROADMAP.md`.

## Notes

<empty>
