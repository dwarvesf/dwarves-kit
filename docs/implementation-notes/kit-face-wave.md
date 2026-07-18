# Implementation notes: kit-face wave (cross-cutting)

Delta-log for decisions that span the whole kit-face mega-goal (roadmap:
ops-toolkit `_meta/megagoals/kit-face/`), not any single spec. Per-spec deltas live in
their own `docs/implementation-notes/SPEC-NNN-*.md`.

## 2026-07-03 execution architecture (lead session anchored in ops-toolkit)

- **Context:** the `/goal` loop driving this wave runs in a session whose cwd is
  `~/workspace/<owner>/ops-toolkit` (where the mega-goal ROADMAP lives), NOT
  `dwarves-kit`. ops-toolkit is ALSO kit-adopted.
- **Decision:** the lead authors the kit artifacts (specs, command/agent edits, tests,
  proofs) directly in `dwarves-kit` via absolute paths, runs `dwarves-kit`'s own test
  scripts, dispatches the kit's verifier AGENTS (`kit:task-verifier`,
  `kit:integration-verifier`, `kit:recheck-verifier`) with cwd pinned to `dwarves-kit`,
  and records the gate-ledger entries the ship-gate requires.
- **Why:** invoking the `/kit:*` slash-commands from an ops-toolkit-rooted session would
  operate on the WRONG repo and could scaffold specs into ops-toolkit. Authoring directly
  + running the real tests + dispatching cwd-pinned verifier agents fulfils the V-model
  intent (real gates ran, real proofs) without the cross-repo contamination risk.
- **Impact:** the phase discipline and proofs are honored; only the invocation surface
  differs from a native in-repo `/kit:execute`.

## 2026-07-03 branch topology (in-place, not worktrees)

- **Decision:** feature branches `feat/kit-face-NN-<slug>` are created in-place in the
  `dwarves-kit` main checkout (07 stacked on 06's branch; the rest off `master`), per the
  mega-goal's explicit stacked-PR + retarget flow.
- **Why:** the goal's stacked/auto-bottom-up/retarget merge posture is an explicit operator
  instruction (overrides the default "branch into a worktree" rule); the lead is sequential
  (one sub-goal at a time), so there is no parallel-writer index.lock collision the worktree
  rule guards against. `dwarves-kit` is a separate repo from the lead's session cwd, so no
  collision with ops-toolkit either.
