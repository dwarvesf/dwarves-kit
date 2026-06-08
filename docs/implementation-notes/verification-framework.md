# Implementation notes: verification-framework

Goal: unify the kit's proof-of-done into one scientific-method spine (hypothesis ->
test-design -> execution -> versioned runs), extend the gate to a per-slug directory
layout, wire a bounded quality loop onto the existing verifiers, and reconcile
ops-toolkit's two competing convention docs to pointers. Runs as a /goal loop.

## 2026-06-09 isolation: kit feature branch, not a native worktree
- Context: the /goal loop is running from the ops-toolkit session (cwd), but the canonical
  convention + gate code live in dwarves-kit (a sibling repo).
- Decision: ops-toolkit-side work runs in a native ops-toolkit worktree
  (`.claude/worktrees/verification-framework`); kit-side work runs on an in-place feature
  branch `feat/verification-framework` in dwarves-kit.
- Why: EnterWorktree targets the session's repo (ops-toolkit); it cannot create a native
  worktree for a sibling repo. The always-worktree policy's branch-create hook is warn-only.
  Safety was checked first: no `.git/index.lock` (no active writer), the only dirty file is
  a stale 2-line `docs/ABSORPTION.md` WIP from another branch which is left untouched and
  never staged.
- Alternatives considered: (a) run the whole goal from dwarves-kit , cleaner, but the loop
  is already pinned to the ops-toolkit session; (b) hand-`git worktree add` a kit worktree
  , rejected, the policy forbids manual worktree add.
- Impact: kit commits land on `feat/verification-framework`; the gate-deploy step must copy
  changed libs/docs into the install path `~/.claude/dwarves-kit` for ship-gate to see them.

## 2026-06-09 design: delta is smaller than the dialect-count suggests
- Context: read the kit's existing convention (docs/verification/README.md), proof-ledger.sh,
  /kit:verify, shared-evidence-discipline.md before designing.
- Finding: the kit already has the semantic core (green + negative control + reproducible,
  risk classes, diff-keyed gate, experiment named as sibling). The supporting kit docs
  (shared-evidence-discipline.md etc.) are verification LOGS, not competing conventions , so
  the only competing convention docs are in ops-toolkit (_meta/PROOF-OF-DONE.md +
  docs/verification/README.md).
- Decision: evolve the kit README in place as the single canonical doc; do not add a new doc.
- Gate change is additive: `_fresh_proof_files` already matches `docs/verification/.+\.md`,
  so files under `docs/verification/<slug>/runs/` are already picked up. The real fix is
  `check()` validating set-wise per `<slug>/` dir (green in one runs/ file + negative control
  in another satisfies), keeping the per-file path for back-compat with flat `<slug>.md` and
  `proof-of-done.md`.
- Migrating the experiment INTO `docs/verification/<slug>/` makes it gate-visible without
  teaching the gate about `experiments/.../TEST-REPORT.md`.
