# Proof of done: repo-tidy

Removes files nothing uses: the Raycast extension and the Warp workflows under `integrations/` (no caller, no test, no install path; the Raycast build also lacked its icon) and `docs/figures/v-model.svg` (the generated `docs/figures/v-model.png` replaces it). `docs/WORKFLOW.md`, `docs/README.md`, `docs/reference/project-structure.md` and `integrations/README.md` now describe what is left, and the integrations index lists the Hermes skills that moved there. One path the layout sweep rewrote by mistake is restored: forge's own `docs/architecture.md`.

## Green run

```
Command: bash lib/system-design/doc-figures check; bash tests/test-meta-docs-registry.sh; bash tests/test-board-hermes.sh; bash tests/test-meta.sh; bash tests/test-docs-wiring.sh
Exit: 0
Output:
doc-figures: ok (12 figures)
test-meta-docs-registry: Passed: 120 / 120
test-board-hermes: 79 passed, 0 failed
test-meta: Passed: 930 / 930
Verdict: PASS
```

`bash tests/test-docs-wiring.sh` exits 0. `bash lib/docdrift/refcheck.sh scan --repo .` reports 28 dead references before and after; every remaining one is a path in an adopter's repo (`.claude/goals/`, `.claude/settings.json`) or in the forge repo, not a missing file here.

## Rollback

Revert the squash commit; git history restores the removed files.

Verdict: PASS
