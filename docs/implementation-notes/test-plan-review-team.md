# Implementation notes: /kit:test-plan-review-team (SPEC-047)

Adversarial test-design critique command. Mirrors `/kit:devs-team` one altitude down (the test
design, not the solution design). Slots between `/kit:test-plan` and `/kit:execute`.

## 2026-06-09 , branch in-place (tooling)
- EnterWorktree can't nest into a second repo from within the ops-toolkit worktree session, and hand
  `git worktree add` is policy-forbidden. dwarves-kit is clean (only unrelated `M docs/ABSORPTION.md`),
  so branched in-place (`feat/test-plan-review-team`). Same call as Phase A (ADR-0026 PR #20).

## 2026-06-09 , report-only + revise-loop reconciliation
- The two locked decisions look in tension (report-only vs auto-revise loop). Resolution: the loop
  edits the spec's `## Test plan` (producer role, a DISTINCT reviser subagent) and re-critiques until
  findings hit 0 or a 3-round cap; then it reports an advisory SOLID/REVISE/RECONSIDER verdict. It
  improves the artifact but never blocks `/kit:execute`. Producer != reviewer preserved (separate
  Task dispatches per round).

## 2026-06-09 , no separate agent files for the 5 lenses
- `/kit:devs-team` inlines its 5 lenses in the command and dispatches generic read-only Task
  subagents; it has NO per-lens agent file. Mirrored that (minimum infra): the 5 lenses live inline in
  `commands/test-plan-review-team.md`. The reviser is also an inline Task dispatch.

## 2026-06-09 , the 5 lenses map 1:1 to test-design-standard.md
- Coverage completeness (std §1/§5/§6), Oracle & falsifiability (§3/§4), Feasibility & reproducibility
  (§3/§5), Test-ladder & boundary depth (§2/§1), Determinism & maintainability (the flakiness lens, the
  one rule the standard implies but does not name a section for). This grounds the command in the
  existing standard rather than inventing fresh criteria.

## 2026-06-09 , meta-test drift guard
- Pinned the literal `## Test plan critique` heading + the `spec-first` write target in the command,
  mirroring the SPEC-023 devs-team/visual-team pins (tests/test-meta.sh). No command READS this
  critique (human-facing), so a wording pin is the right guard (same call the kit made for devs-team).
