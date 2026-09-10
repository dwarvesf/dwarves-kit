# Implementation notes: learning-boundary mega-goal

Delta from `_meta/megagoals/learning-boundary/ROADMAP.md` and its goal files. Decisions the roadmap left open, deviations, and things the next session should know.

## 2026-09-10 10:20 The axis replaced the first cut before any code

Context: the first roadmap draft (merged as #555) said "every learning-shaped surface moves to learning-kit" and listed `explain`, `quiz-gate`, `absorb` as moves. The operator asked how that squares with the dev kit's own auto-improvement half.
Decision: split by who changes (system: Reflect, engine; human about shipped work: Understand, gate in engine + teacher in learning-kit via `understand.teach`; human expanding: Study, learning-kit). `absorb` stays whole; `explain` and `quiz-gate` stay as gate-side entry points and only their pedagogy bodies move.
Why: ADR-0031 was right about the gate's placement; it never separated the gate from the teacher. Moving the commands would strand engine-only adopters with no gate at all.
Alternatives: move everything learning-shaped (rejected above); keep everything in the engine (violates SPEC-249, keeps the dotfiles reach-across).
Impact: sub-goal 02 renamed `dev-learner-teacher`; seam key renamed `wrap.learn` to `understand.teach` across 01, 03, 05; ADR-0036 carries the axis table.
Open questions: none; the ADR is the operator's click.

## 2026-09-10 10:35 Two "dotfiles" skills live in a different repo

Context: a read-only verifier refuted the roadmap's claim that nine learning skills live as directories under `dotfiles/home/dot_claude/skills/`.
Decision: `knowledge-capture` and `learn-skill` are chezmoi `symlink_*` entries pointing at `~/workspace/claude-skills/skills/`; the roadmap and goals 03 and 04 now name claude-skills as the source repo for those two, and the dotfiles half of each move is removing the symlink entry, not a skill directory.
Why: a `git mv` from the wrong repo would move a symlink file and leave the body behind.
Impact: sub-goals 03 and 04 each touch three repos (source, destination, dotfiles) for those two skills instead of two.

## 2026-09-10 10:35 The main checkout carries the superseded roadmap until this PR merges

Context: the same verifier noted the main dwarves-kit checkout still holds the #555 draft (seam `wrap.learn`, `absorb` moving).
Decision: no action; it is the unmerged state of this branch. Anyone dispatching a sub-goal before this PR merges reads the wrong cut.
Impact: do not run `orchestrate.sh` on this mega-goal until the ADR PR is merged with Status Accepted.
