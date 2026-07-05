# Sub-goal 03: /kit:explain (the explainer)

**Merge policy:** auto
**Time budget:** 4-6 hours (the widest build , composes 3 skills into a new artifact).
**Proof:** run-table: `/kit:explain <ref>` on a real merged change produces the literate explainer (background -> intuition -> prose-ORDERED diff -> diagram) · a captured artifact shows prose ordering NOT git/alphabetical order · the diagram renders (mermaid) · NEGATIVE CONTROL / hard constraint: the explainer content traces to the ACTUAL diff + recorded test results, not the agent's narrative (a fixture where the agent's stated intent differs from the diff must explain the DIFF).
**Depends on:** none (builds without the classifier; 02/04 decide when to invoke it).
Model: opus
Effort: high
**Branch:** feat/ug-03-explain
**PR base:** master

## Outcome

`/kit:explain <commit|PR|spec>` , a new command that emits a literate-diff EXPLAINER for a change: background (existing context the reader needs) -> goal + intuition (concepts before code) -> a PROSE-ORDERED diff (snippets in reading order with explanation, NOT `git diff` alphabetical order) -> a diagram (via svg-knowledge-diagram / mermaid). It COMPOSES existing skills , `narrate-log` for the session->prose arc, `svg-knowledge-diagram` for the diagram , rather than reinventing them. The artifact is what the human reads to UNDERSTAND (Litt), replacing the raw diff. The 5-question quiz is SG-04 (this sub-goal produces the material the quiz is built from).

## Quality bar

The HARD constraint (Litt's caveat): the explainer is grounded in the ACTUAL diff + recorded test results, NEVER the agent's own narrative of what it did , else it teaches the agent's misconceptions. Prose ordering is the point (a raw diff is "a pile of files edited in alphabetical order"); if the output is just `git diff` with headers, it failed. Reuse the learning skills; do not fork pedagogy into the kit.

## How to close the loop

`/spec` + `/spec-validate` first (this is design-bearing , write a `## Design` block per SG-01 if 01 merged, else per ADR-0031). Then `bash tests/test-explain.sh`: the literate-order assertion, the mermaid-renders assertion, and the grounded-in-diff NC (agent-intent-differs-from-diff fixture). Capture the explainer artifact in the proof. Assumptions: ROADMAP 03 + ADR-0031 §2.

**Done =** `/kit:explain` produces a background/intuition/prose-ordered-diff/diagram artifact from the actual diff+tests (grounded-NC green), prose ordering proven, composing narrate-log + svg-knowledge-diagram, tests green.

## Scope edges

**In:** commands/explain.md, the literate-diff formatter, the narrate-log + svg-knowledge-diagram composition, tests + the captured artifact.
**Out:** the quiz (04); the significance trigger (02); the batch flow (05).
**Not:** a new narrative/diagram engine (compose the existing skills); an explainer from the agent's narrative instead of the diff; interactive micro-worlds (deferred per ADR-0031, use interactive-concept-board later if a subsystem earns it).

## Where to look

commands/docs.md (the closest existing command , but it does doc-DRIFT, not human-EXPLAIN; contrast), the ops-toolkit skills `narrate-log` + `svg-knowledge-diagram` (compose these), `deep-understand` (04 will consume this artifact), ADR-0031 §2, the git diff + `docs/verification/*` test records (the grounding source).

## PR body

`/kit:explain` (ADR-0031 §2): a literate-diff explainer (background -> intuition -> prose-ordered diff -> diagram) composing narrate-log + svg-knowledge-diagram, grounded in the actual diff + test results (not the agent's narrative). Verify: `bash tests/test-explain.sh` (literate-order + mermaid + grounded-NC). Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
