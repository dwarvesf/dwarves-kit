# FEEDBACK, kit-adopt-enforce

Append-only meta-feedback for Han (skill / tooling / codebase friction hit during the run).
Date-stamp each entry: `<YYYY-MM-DD> · <category> · <observation>`. One paragraph max. No secrets.

## Skill friction

2026-06-09 · skill friction · plan-for-mega-goal scaffolds the roadmap in the cwd repo, but a cross-repo mega-goal whose sub-goals need their OWN repo's session breaks silently: the `/kit:*` slash commands bind to the session cwd, so a dwarves-kit sub-goal cannot be dogfooded via the slash-command UI from an ops-toolkit `/goal` session. Suggest: when sub-goals span repos, the skill should warn that each off-cwd repo's sub-goals must be run from a session in that repo (or that the lane will be driven via lib/ directly, not the slash commands), and detect the target repo's default branch (this one assumed `main`; dwarves-kit is `master`).

## Tooling gaps

2026-06-09 · tooling gap · `lib/gate-ledger.sh record <rid> review ran "<reason>"` silently failed to persist the entry the first time (the reason string contained parens + colons), so `check full` later reported review MISSING. It exits non-zero on a bad reason but the loop had redirected stderr to /dev/null. Suggest: gate-ledger `record` should reject/validate the reason robustly (or quote-safe it) and the caller should not swallow its exit code. A `record ... && echo ok` discipline catches it.

## Codebase issues

2026-06-09 · codebase · `hooks/ship-gate.sh` resolves the active spec by the BRANCH slug (`docs/specs/SPEC-*-${BRANCH#*/}.md`). When a branch name differs from its spec slug (this loop's `feat/kit-adopt-01-cmd` -> spec `SPEC-047-kit-adopt`, `feat/kit-adopt-02-gate` -> `SPEC-048-ship-gate-fail-closed`), the gate finds no spec and fails OPEN on the dev's own push. So the kit cannot fully self-enforce unless branch slug == spec slug. Candidate: also look up the most-recent VALIDATED spec, or warn when a branch has gate-ledger entries but no slug-matching spec. The feature is still correct (verified via matching-slug tests); only self-enforcement on mismatched dev branches is affected.

2026-06-09 · codebase · `lib/lane-classify.sh` classifies a change to the kit's OWN enforcement/contract machinery (the adopt command that wires the proof/lane classifiers + injects the operate-contract) as `normal`, not `full`. A human reads it as full ("when in doubt, heavier"). Candidate fix: a full-lane trigger for "modifies the kit's gate/lane/proof machinery or the operate-contract it injects". Surfaced as a dogfood signal on turn 1 of sub-goal 01; handled via a gate-ledger override.

## Pointer prompt churn

(times the pointer prompt had to be rewritten mid-loop, and why)
