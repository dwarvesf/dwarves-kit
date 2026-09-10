# Sub-goal 02: learning-kit ships the dev-learner teacher

**Merge policy:** auto
**Time budget:** 4 hours (cross-repo: learning-kit receives, dwarves-kit thins, dotfiles retires)
**Proof:** run-table: `learning-kit/skills/dev-learner/{explain,quiz,paydown}/SKILL.md` exist with a `Moved-from:` line naming the source path and commit; `learning-kit/lanes.d/dev-learner.plan` exists; the install step writes `understand.teach = "dev-learner"` into the operator `kit.toml` when absent and leaves an existing value alone (test mirrors `tests/test_seam.sh`); dwarves-kit `commands/explain.md` and `commands/quiz-gate.md` are thin (gather diff, tests, DEBT rows; invoke the seam; report) and its suite is green; the routing assertions #554 retired live in learning-kit's tests now; dotfiles `.chezmoiremove` lists `weekend-debt-paydown`; NEGATIVE CONTROL: with `understand.teach` empty, `/kit:explain` prints `skipped: no teacher` plus the path of the diff it gathered, and `/kit:wrap` Step 7a still writes the DEBT marker.
**Depends on:** 01.
Model: sonnet
Effort: high
**Branch:** feat/dev-learner-teacher (learning-kit); refactor/thin-understand-commands (dwarves-kit); chore/retire-weekend-paydown (dotfiles)

## Outcome

The teacher half of the understanding axis, separated from the gate. Three skill bodies move into learning-kit under one `dev-learner` lane: `explain` (the literate-diff explainer: background, intuition, prose-ordered diff, diagram), `quiz` (the five questions from the actual diff and tests), `paydown` (the weekend Flow B orchestration, from dotfiles `weekend-debt-paydown`). Bodies unchanged beyond path fixes. In dwarves-kit, `commands/explain.md` and `commands/quiz-gate.md` keep their names and their triggers and become gate-side entry points: they gather what the teacher needs (the diff, the test results, the DEBT rows, the impl-notes) and invoke whatever `understand.teach` names. The lane plan mirrors `study.plan`. The tests that proved the pedagogy in dwarves-kit move with it.

## Quality bar

A move, not a rewrite: diff each moved body against its source and the only hunks are paths and the `Moved-from:` line. The thinned engine commands keep every trigger phrase they had. An engine-only adopter sees `skipped: no teacher` and the gathered material, never a degraded lesson. learning-kit's suite covers what dwarves-kit's suite covered for the bodies; the engine's suite covers the gathering and the skip.

## How to close the loop

learning-kit first (receive), then dwarves-kit (thin, in a PR whose body links the receiving PR), then dotfiles. Verify `bin/config seams` on the operator machine after `chezmoi apply` and `claude plugin install ./learning-kit`, then run `/kit:explain` on a real merged PR once and confirm the `dev-learner` teacher answered.

**Done =** three bodies present in learning-kit with tests, engine commands thin, seam filled, proofs above.

## Scope edges

**In:** the three bodies, their tests, the lane plan, the install step, the thinning, the retirement.
**Out:** `absorb` (Reflect, stays whole in the engine); the study lane; the concept ledger (03); context-kit.
**Not:** editing any teaching behavior; moving the gate, the nudge, or the DEBT ledger.
