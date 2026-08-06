# Sub-goal 01: README hero + parity pin

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** 2-3 captures of the GitHub-rendered mermaid (before/after) + run-table: agents table 18/18 vs live dir · new agents-summary parity pin green · existing SPEC-085/SPEC-032 README pins still green (regression control).
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/kit-face-01-readme
**PR base:** master

## Outcome

README is current and its hero is a native-rendered mermaid lifecycle diagram (6 phases, one-line desc each, gate class blocking/advisory at each boundary) REPLACING the ASCII hero; one trust-story sentence folds in the kit-hardening upgrade (fresh-context re-audit + advisor + deployable-done); the agents table and directory-layout counts match reality (18 agents, 17 hooks) and a NEW computed parity pin in test-meta makes the agents-summary drift class die like the hooks/commands ones did (SPEC-085 shape). WORKFLOW.md keeps the ASCII canon and gains the `docs/v-model.svg` link (disposition of the orphaned asset).

## Quality bar

The diagram must read in 10 seconds on github.com , 6 phases, not the full V-model. Tighten prose only; Credits stay intact; nothing asserted that a pin does not check.

## How to close the loop

`/spec` + `/spec-validate` first. Then: `bash tests/test-meta.sh` (old pins + the new agents pin); render check via the GitHub UI or `gh api` markdown preview, captured. Assumptions: ROADMAP `## Assumptions` 01 block.

**Done =** mermaid hero renders on GitHub (captures committed), agents/layout counts corrected AND pinned, `test-meta.sh` green.

## Scope edges

**In:** README.md, WORKFLOW.md (svg link), the new test-meta parity pin.
**Out:** docs index (02); MANUAL.md (already correct at 18).
**Not:** delegating README tables to MANUAL (test-pinned to stay); a full-V-model diagram; touching Credits.

## Where to look

README.md:10-21 (the ASCII hero to replace) + :124-149 (second diagram, keep), test-meta.sh SPEC-085 block (~:2400) for the pin shape, MANUAL.md agents table (the correct 18), `docs/v-model.svg`.

## PR body

README hero: mermaid lifecycle (replaces ASCII), trust-story sentence, agents 11->18 + layout counts fixed, agents-summary parity pin added (SPEC-085 shape). Verify: `bash tests/test-meta.sh` + rendered captures in the proof. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
