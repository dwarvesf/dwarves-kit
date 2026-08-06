# Retro: SPEC-028 release-hygiene guard (ID-026)
Date: 2026-05-22
Sprint: single-session dogfood, assign -> spec (surface decision) -> spec-validate -> execute -> review -> docs -> ship. Normal lane (the surface choice was warn, not hook).

## Metrics
- Tasks planned: 3, completed: 3, deferred: 0.
- Commits: 9 (3 surface/test edits, 3 fix commits, spec-progress + docs + ship-bookkeeping). Atomic, conventional.
- Files changed: 7 (+84 / -7). No new command, no new hook, no new file except the spec (Approach A: warn-only convention on two existing surfaces).
- Verification: 3/3 task-verifier PASS (TASK-001 needed 1 fix retry); integration-checker FAIL:fixable then PASS (1 fix); doc-verifier PASS (16/16). meta 256/256 (+2), hooks 92/92.
- Completeness log: clean. Doc-impact: MANUAL (/ship + /kit-health) + CHANGELOG moved; no new command so no plugin/marketplace/README-table impact.

## Key commits
- `0958107` kit-health check; `0a27c62` ship warn; `2b9f2a1` meta-test pin; `abea75d` + `5ebdbec` + `b5ddf9f` the three DEC-005 alignment fixes (one per verification layer).

## What worked
- **Surface-decision-first kept the build minimal and set the lane correctly.** Deciding the detection surface in `/spec` (before writing the spec) determined the lane (warn surfaces -> normal, not full) and the research genuinely sharpened the design: a `tests/test-meta.sh` hard assertion was rejected because "VERSION untagged" is a legitimate release transient + CI shallow-clone fragile, and the real signal is the phantom cut (untagged version), not `[Unreleased]` accumulation (which the kit does deliberately). The spec was right-sized as a result.
- **The three verification layers each caught a DIFFERENT drift of the SAME invariant.** DEC-005 said the two inlined copies (ship.md + kit-health.md) must be byte-identical. task-verifier caught the outer-guard drift (`[ -d .git ]` vs `git rev-parse --git-dir`, breaks in worktrees); integration-checker caught the inner-guard drift (the empty-VERSION condition); `/user:review` caught the soft accumulation-signal drift (grep-heading-exists vs awk-non-empty). Three layers, three distinct drifts, on the guard's own two copies. This is the strongest evidence yet for the layered pipeline AND a live demonstration of why identical-by-contract duplication is dangerous.
- **The guard self-fired on its own ship.** At `/user:ship` Step 4a the new warn correctly detected the live phantom cut (`v1.6.0` untagged, `[Unreleased]` accumulating). End-to-end dogfood proof, in situ, warn-only (it reported, did not block).
- **Pinning the check shape in the spec (DEC-005) gave the verifiers something concrete to check.** Without the "identical shape" contract written down, the three drifts would have passed silently.

## What hurt
- **DEC-003's "inline until 3 uses" produced 2 copies that drifted 3 times in ONE cycle.** The kit's "no premature abstraction (extract at the third occurrence)" rule said keep the check inline at two surfaces. Those two copies then diverged three separate times, each needing a fix round. For logic that MUST be byte-identical across surfaces (identical-by-contract), "wait for the third use" is the wrong heuristic: the cost is paid in drift, not in a premature helper. Partial root cause is mine: my worker prompts were asymmetric (TASK-002 got the exact bash block, TASK-001 got a narrative "check shape"), which seeded the first drift.
- **The 3-deep branch stack deepened the very tangle this spec targets.** Building the release-hygiene guard added a third stacked branch (agents-md -> mid-flight -> release-hygiene) on top of the untagged `1.6.0`, making the release state messier, the exact thing the guard now warns about. The guard detects the mess; it does not clean it up.
- **The phantom cut is still unfixed.** `v1.6.0` remains untagged with three specs' worth of `[Unreleased]` above it across three local branches. The guard now nags about it on every ship, which is correct, but the cleanup (integrate the stack, decide the version, tag) is owed and only grows.

## Action items
- [ ] **Carve out "identical-by-contract" from the no-premature-abstraction rule.** When two copies of a snippet MUST stay byte-identical (a shared check across surfaces), single-source them (a shared snippet/helper) or pin the exact block, even at two uses; do not wait for the third. Evidence: 3 drifts in one cycle. -> propose BACKLOG (a CLAUDE.md code-quality nuance) + relates to the ID-016/ID-020/ID-026 guard-theme.
- [ ] **Worker-prompt discipline for identical-output tasks.** When two worker tasks must produce identical logic, give BOTH workers the exact same block (not one exact + one narrative). A one-line note in `commands/execute.md`'s worker-dispatch guidance. -> propose BACKLOG (tiny), relates to ID-028.
- [ ] **Resolve the release state the guard is now nagging about.** Integrate the 3-branch stack (agents-md / mid-flight / release-hygiene), decide the version, and tag, so `v1.6.0` (or its successor) stops being a phantom cut. Needs the maintainer's integration decision. -> propose BACKLOG (the real cleanup the guard points at).
- [ ] **ID-024 (context-switch / worktree-per-spec) is reinforced** by the 3-deep stack pain; bump its priority consideration. -> already queued (ID-024), note the reinforcement.

## Kit feedback
The layered verification design is strongly validated this cycle: three independent layers caught three distinct drifts of one invariant that any single layer would have missed (the per-task verifier could not see the cross-surface inner-guard drift; the integration-checker's scoped structural comparison did not flag the soft accumulation-signal drift; review caught that). The same cycle exposed a tension in the kit's own rules: "no premature abstraction (3x)" is wrong for identical-by-contract logic, where duplication drifts faster than it accumulates uses. The fix is not to drop the rule but to carve out the identical-by-contract case. Secondary: the kit cheerfully let a 3-deep branch stack form on an untagged version; the new guard now warns about the end state, but nothing discourages the stack from forming (ID-024 territory).
