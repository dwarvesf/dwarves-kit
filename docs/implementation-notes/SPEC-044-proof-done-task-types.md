# Implementation notes: SPEC-044 proof-of-done task-type contracts

Running log of decisions/changes not pinned in the spec.

## 2026-06-08 11:00 Spec number collision (SPEC-008 -> SPEC-044)

- Context: drafted the spec as SPEC-008 because an `ls docs/specs/ | head` truncated the list and I assumed max was 007.
- Discovery: `tests/test-meta.sh` references SPEC-008 (solution-design-depth) and SPEC-024/026/029/030 as existing; the real max committed spec is SPEC-043, and `SPEC-042-proof-of-done.md` already exists (the framework this extends).
- Decision/Change: `git mv` SPEC-008-proof-done-task-types.md -> SPEC-044-proof-done-task-types.md; sed-renumbered every internal `SPEC-008` ref in the spec + both `.claude/goals/*` goal files to SPEC-044. Dup-number check is clean.
- Why: the kit's numbering rule = max+1 of committed specs, claimed at commit time; the dup-number meta-test would have failed.
- Impact: the active `/goal` Stop-hook text (set before the rename) still literally says "SPEC-008"; treat it as SPEC-044 for the rest of this loop. Goal files + spec + proof artifact path are all SPEC-044.

## 2026-06-08 11:05 Grounding on SPEC-042

- SPEC-042 (SHIPPED) established proof-of-done = 3-part recorded artifact (green + negative control + reproducible), the `docs/verification/<slug>.md` log, and `docs/verification/README.md`. It explicitly deferred the blocking ship-gate; that enforcement (`lib/proof-ledger.sh` + `hooks/ship-gate.sh`, ADR-0025) landed afterward and is live.
- SPEC-044 adds the task-TYPE axis (artifact shape + owning skill) composed onto the existing proof-CLASS (rigor). It does not rewrite SPEC-042's semantics.

## 2026-06-08 11:05 Cross-repo session caveat

- This loop is being driven from an ops-toolkit session, not a dwarves-kit session. The kit's own `/kit:spec-validate` / `/kit:execute` / `/kit:ship` commands resolve against the session's project (ops-toolkit), so they cannot be invoked against dwarves-kit from here. Substituting the equivalent discipline manually: implement the pieces, run `bash tests/test-meta.sh` + the classifier/contract runs as the verification, and record the proof of done in `docs/verification/SPEC-044.md`. The `/kit:*` ceremony steps should be re-run in a dwarves-kit session for the true dogfood + the ship gate; flagged to the operator.
