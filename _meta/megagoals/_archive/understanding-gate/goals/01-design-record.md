# Sub-goal 01: design record (the BEFORE gate)

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table: a design-bearing fixture spec WITHOUT a `## Design` block is REFUSED by spec-validate (negative control) · a design-bearing spec WITH a mermaid diagram + chosen-approach passes · an obvious/tiny spec collapses to `obvious: <why>` and is NOT required to diagram (proportionality control) · the subgoal-template `Design:` field diff (dotfiles half) captured.
**Depends on:** none.
Model: sonnet
Effort: high
**Branch:** feat/ug-01-design-record
**PR base:** master

## Outcome

Per ADR-0031, a spec above tiny that is DESIGN-BEARING carries a `## Design` block BEFORE `/kit:execute` writes code, so the human gates DIRECTION off a diagram not a diff. Block = approaches+chosen (SPEC-008 shape) + a diagram picked by fit (mermaid-first; sequence/state/ER/flowchart/C4 container-or-component) + ADR link(s) for lasting decisions + boundaries/failure-modes. Design-bearing trigger: above tiny AND (new component / non-obvious control flow / schema change / external integration / irreversible choice / 2+ approaches); else collapses to `obvious: <why>`. C4 is LITE , the one level that clarifies, never four levels cargo-culted.

## Quality bar

Proportional or it becomes compliance theater: obvious work is one line, only real design triggers the diagram. Mermaid over binary images (diffable, GitHub-native). spec-validate ENFORCES it (design-bearing + empty Design = not VALIDATED), the human actually gates on it.

## How to close the loop

`/spec` + `/spec-validate` first (this IS a kit-dogfood design-bearing change , write its OWN `## Design`). Then `bash tests/test-<spec>.sh` covering the three fixtures (refuse-empty NC, pass-with-diagram, obvious-collapses) + `bash tests/test-meta.sh`. Dotfiles half: edit the chezmoi source subgoal-template, apply, stage+commit in ONE call. Assumptions: ROADMAP 01 + ADR-0031 §1.

**Done =** spec.md `## Design` block + trigger live, spec-validate refuses a design-bearing empty Design (NC green), obvious-collapse proven, the `Design:` template field shipped (dotfiles), tests green.

## Scope edges

**In:** commands/spec.md (§3 Design block + trigger), commands/spec-validate.md (the enforcement lens), commands/design.md (emit diagram + ADR-links), WORKFLOW.md (Design row expected for design-bearing), dotfiles subgoal-template `Design:` field, fixtures.
**Out:** the explainer/quiz (03/04); the significance classifier (02 , distinct: significance gates the AFTER explainer, design-bearing gates the BEFORE record).
**Not:** making design a HARD block (advisory + spec-validate refusal, not a build halt); four-level C4; a diagram for obvious work.

## Where to look

commands/spec.md §3 (the soft `### Architecture (diagram if it helps)` to promote), commands/spec-validate.md (lens shape), commands/design.md (`## Solution` writer), SPEC-008 + SPEC-011 (the design-lane specs to amend), ADR-0031 §1, dotfiles `dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md`.

## PR body

Design record (ADR-0031 §1): design-bearing specs carry a `## Design` block (diagram/ADR/C4-lite, proportional) enforced by spec-validate before VALIDATED; `Design:` field added to the mega-goal subgoal template. Verify: three fixtures (refuse-empty NC, pass-with-diagram, obvious-collapse) + test-meta. Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
