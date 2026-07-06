# Implementation notes: /kit:adopt command (sub-goal 01 of kit-adopt-enforce)

Mega-goal: `ops-toolkit/_meta/megagoals/kit-adopt-enforce/` (sub-goal `goals/01-adopt-command.md`).
Branch: `feat/kit-adopt-01-cmd` off `master`. Built through the kit's full lane (dogfood).

## 2026-06-09, turn-1 setup + classification

- Context: started sub-goal 01 (the `/kit:adopt` command) from a `/goal` loop whose session cwd
  is ops-toolkit, building into this (dwarves-kit) shared repo.
- Decisions / deviations forced by the environment, logged for future-me:
  1. **Slash-command dogfood done via direct steps, not the `/kit:*` UI.** The `/kit:*` slash
     commands run against the session cwd (ops-toolkit) and I cannot move the session into
     dwarves-kit, so invoking `/kit:spec` here would write to the wrong repo. I dogfood the lane
     by driving its real machinery directly: `lib/classify/lane-classify.sh`, `lib/classify/task-type-classify.sh`,
     `lib/gate/proof-gate.sh`, `lib/gate/gate-ledger.sh`, and the reviewer agents. Same lane, same gates,
     same ledger the fail-closed gate (sub-goal 02) consumes. (FEEDBACK filed upstream.)
  2. **Branch in the main checkout, no worktree.** The native worktree tool only targets the
     session repo (ops-toolkit); manual `git worktree add` is disallowed by policy. Single
     sequential writer on a shared repo, branch-only, PR-not-merge, so the index.lock risk the
     worktree rule guards against does not apply. The unrelated dirty file `docs/ABSORPTION.md`
     was parked with `git stash` (recover: `git switch master && git stash pop`).
  3. **Lane: classifier said `normal`, OVERRIDDEN to `full`.** `lane-classify.sh classify` returns
     `normal` for the adopt command (it does not trip the full triggers literally). Overridden to
     full because: it is foundational kit machinery (wires the proof/lane classifiers + injects the
     operate-contract), it couples with sub-goal 02 which IS full (it edits the `ship-gate` hook +
     changes enforcement), WORKFLOW says "when in doubt, heavier", and the operator asked for the
     full lane. Recorded as a gate-ledger ACTION on `kit-adopt-01-cmd`. Full-lane gate set:
     think, design, design-critique, spec, validate, test-plan, build, review, docs, ship, reflect.
  4. **`master`, not `main`.** dwarves-kit's default branch is `master`; the mega-goal pointer +
     sub-goal files assumed `main`. Corrected in the ops-toolkit scaffold.
- proof-gate contract: `type=spec-feature class=behavioral` -> owes the REAL primary flow run
  end-to-end + a recorded run in `docs/verification/<slug>.md` + a negative control. That shapes
  the spec's Verification + the build's proof.
- Next: the `think` gate (challenge the design) then `spec` (SPEC-047), per the full lane.

## Open finding (dogfood signal, for FEEDBACK)

`lane-classify` under-classifies a change to the kit's OWN enforcement/contract machinery as
`normal`. A human reads it as full. Candidate fix: a full-lane trigger for "modifies the kit's
gate/lane/proof machinery or the operate-contract it injects". Captured in the mega-goal FEEDBACK.md.
