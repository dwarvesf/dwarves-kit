# Implementation notes: SPEC-235 gauntlet generalization

Delta from the spec only.

## 2026-08-31 spec drafted before implementation

Context: operator asked for the generalization and to dogfood the kit for it.
Decision: grill phase-0 ran as the operator conversation (the intent, the /goal duality, the preset list came from the operator verbatim); no separate interview.
Why: the conversation already answered the grill's questions; re-asking an absent operator blocks an autonomous run.
Impact: spec Status stays DRAFT until the operator approves; spec-validate runs on the draft.

## 2026-08-31 validation round folded, Status flipped to VALIDATED without operator sign-off

Context: spec-validate (fresh-context 6-lens panel) returned NEEDS REVISION, 4 criticals + 9 warnings, Reviewer 6 (blocking design-record lens) passed.
Decision: all 13 findings folded into the spec (DEC-005/DEC-006 record them); Status flipped to VALIDATED in the same session.
Why: autonomous run; every critical was advisory-lens and had a concrete fix; the operator reviews the whole chain at the PR.
Open question for the operator: the run-record path rename to `<date>-<preset>-<slug>` changes the directory grammar SPEC-226-era records used; old dirs stay valid (no migration), but confirm you accept two grammars coexisting under docs/verification/gauntlet/.

## 2026-08-31 TASK-004: strip-list widening verified NOT applicable

Context: the spec permitted one `tests/gauntlet/cleanroom/run.sh` hunk to widen the answer-key strip list with `commands/gauntlet.md` + `docs/guides/gauntlet.md`.
Decision: no widening; zero `tests/gauntlet` edits shipped.
Why: `tier1.sh:21` asserts both files EXIST in the room; they are part of the kit-user artifact under convergence, so stripping them breaks Tier 1. The answer-key risk is closed at the content level instead (preset table cites SPEC numbers only; the guide's checker description predates this change and is operator-facing doc the probe legitimately reads).
Consumers checked: `tier1.sh` (existence check only), `tests/gauntlet/README.md:6` (pointer), `cleanroom/run.sh` + `run-remote.sh` + `deploy/*` (no text reads of the command file). Suite delta vs master: 819 vs 818 tests, same 10 pre-existing failures (devops-triage/greenlight doc-count rows, unrelated), the new gauntlet QL-VERDICT pin passes.
