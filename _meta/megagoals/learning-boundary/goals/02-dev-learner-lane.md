# Sub-goal 02: learning-kit gains the dev-learner lane

**Merge policy:** auto
**Time budget:** 4 hours (cross-repo: learning-kit receives, dwarves-kit and dotfiles retire)
**Proof:** run-table: `learning-kit/skills/{explain,quiz-gate,absorb,weekend-paydown}/SKILL.md` exist with a `Moved-from:` line naming the source path and commit; `learning-kit/lanes.d/dev-learner.plan` exists; the install step writes `wrap.learn = "weekend-paydown"` into the operator `kit.toml` when absent and leaves an existing value alone (test mirrors `tests/test_seam.sh`); dwarves-kit `commands/{explain,quiz-gate,absorb}.md` are gone and its suite is green; dotfiles `.chezmoiremove` lists `weekend-debt-paydown`; NEGATIVE CONTROL: with `wrap.learn` empty, `/kit:wrap` Step 7a prints `skipped: no learn seam` and nothing else changes.
**Depends on:** 01.
Model: sonnet
Effort: high
**Branch:** feat/dev-learner-lane (learning-kit); chore/retire-learning-commands (dwarves-kit); chore/retire-weekend-paydown (dotfiles)

## Outcome

The dev learner is a second lane beside `study`: an engineer who wants to understand the code an agent shipped. Four skills move in, bodies unchanged beyond path fixes: `explain` (the literate-diff explainer), `quiz-gate` (the five-question nudge), `absorb` (the external-idea intake), `weekend-paydown` (the Flow B orchestration, from dotfiles `weekend-debt-paydown`). The lane plan mirrors `study.plan`. The tests that proved these in dwarves-kit move with them (`test-explain*`, `test-quiz-gate*`, and the AC2/AC4 routing assertions that `fix(learn): the kit stops reading the operator's dotfiles skill` retired from `test-weekend-batch.sh`, restored here where they belong).

## Quality bar

A move, not a rewrite: diff each moved SKILL.md against its source and the only hunks are paths and the `Moved-from:` line. learning-kit's suite covers what dwarves-kit's suite covered for these four. The engine's suite loses only the tests that moved.

## How to close the loop

learning-kit first (receive), then dwarves-kit (retire, in a PR whose body links the receiving PR), then dotfiles. Verify `bin/config seams` on the operator machine after `chezmoi apply` and `claude plugin install ./learning-kit`.

**Done =** four skills present in learning-kit with tests, gone from their sources, seam filled, proofs above.

## Scope edges

**In:** the four skills, their tests, the lane plan, the install step, the retirements.
**Out:** the study lane; the concept ledger (03); context-kit.
**Not:** editing any skill's behavior.
