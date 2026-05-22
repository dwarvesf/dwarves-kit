# Retro: SPEC-027 mid-flight spec amend (ID-023)
Date: 2026-05-22
Sprint: single-session dogfood, assign -> spec -> spec-validate -> execute -> review -> docs -> ship

## Metrics
- Tasks planned: 6, completed: 6, deferred: 0 (the 6 TASK rows; the 8 open `- [ ]` are After-state / global-AC observable checkboxes, not tasks).
- Commits: 10 (9 build + 1 ship bookkeeping), atomic, conventional, no spec IDs in subjects.
- Files changed: 11 (+177 / -14). No new command, no new hook (Approach A: convention).
- Verification: 6/6 task-verifier PASS, 0 retries, 0 escalations; integration-checker PASS; doc-verifier PASS (14/14 claims). meta 254/254 (+4), hooks 92/92.
- Completeness log: clean. Doc-impact: every applicable companion moved (MANUAL + test-meta; no new command, so no README-table / plugin / marketplace impact).

## Key commits
- `17e411a` vision transition row; `704092b` canonical WORKFLOW rule; `7c6eaae` execute reword; `e2a9b5c` meta-test pin; `1be1b54` the review-driven approval-gate fix (DEC-008).

## What worked
- **`/spec-validate` caught a real correctness defect before any build.** The draft claimed resume "via `/user:execute` (or `/user:next`)"; verifying against `commands/next.md` vs `commands/execute.md` showed only `/next` skips `[x]` done rows. Fixed as DEC-006 in the spec, so the build inherited the correct rule. The adversarial pass earned its keep on the kit's own spec, not just downstream ones.
- **`/review` caught a HIGH that all the verifiers passed.** task-verifier (x6) and integration-checker both PASSED the build, yet the independent review found the amend path had no operator-approval gate in the canonical rule or the autonomous orchestrator, while the PLAYBOOK card already promised one (a cross-surface inconsistency + an unguarded autonomous self-amend). This is the SPEC-024 retro's ID-020 finding recurring: review catches a class the verifiers structurally cannot (a missing guard is not a failed assertion).
- **Source-of-truth discipline held across 5 independent workers.** DEC-005 (canonical rule in WORKFLOW.md, every other surface points at it) survived 5 separate worker subagents writing 6 surfaces; the integration-checker confirmed zero four-copies drift. The "point, do not restate" instruction in each worker prompt was the load-bearing control.
- **Disjoint-file parallel dispatch in Phase 2 was clean and faster.** TASK-003/004/005 touched execute.md / spec.md / (PLAYBOOK+ORCHESTRATION) with no overlap; dispatched in parallel, no conflicts, each verified independently.

## What hurt
- **Release-hygiene tangle (recurring).** `VERSION`/`plugin.json` = 1.6.0 but latest tag = v1.5.1 (cut-but-untagged), `[Unreleased]` mixes unmerged PR #7 (SPEC-024) with this cycle, branch 42 commits ahead of `master`. The `/ship` gate had to stop and ask because the state was ambiguous. The SPEC-018 (placement-ui-design) retro flagged this exact failure mode; its recurrence clears the PHILOSOPHY section-5 bar for a guard.
- **The kit prescribes sequential worker dispatch.** `commands/execute.md` says "Execute them one at a time (sequential dispatch; parallel dispatch is a future upgrade)." Phase 2's three tasks were disjoint-file independent, so sequential was pure latency tax; the dogfood deviated to parallel. The instruction does not acknowledge the safe disjoint-file case.
- **The spec underspecified the human-approval gate.** SPEC-027's "Key invariants" listed four and omitted operator-approval; the PLAYBOOK worker reasonably added "you confirm the added scope," which is what created the cross-surface inconsistency review then caught. The autonomy-gate angle (does this let an autonomous loop make a scope/architecture decision unattended?) was not in any `/spec-validate` lens's focus for a docs/convention spec, so validate missed it and review had to.
- **Auto-format left punctuation artifacts.** The slop-cleaner / auto-format converted the spec's TASK-line ` — AC:` em dashes to `., AC:`, producing slightly clumsy "style., AC:" reads. Cosmetic, in the spec doc only, but the em-dash replacement does not always pick graceful punctuation.

## Action items
- [ ] **Release-hygiene guard (recurring, clears the PHILOSOPHY bar).** A `kit-health` line or a hook that flags `VERSION` cut-but-untagged AND `[Unreleased]` spanning more than one spec. Relates to the ID-016 guard-promotion theme. -> propose BACKLOG.
- [ ] **execute.md: acknowledge disjoint-file parallel dispatch.** Note that independent, non-overlapping-file tasks may be dispatched in parallel; sequential is the safe default only for shared-file or dependent tasks. -> propose BACKLOG (tiny) or a one-line execute.md edit.
- [ ] **spec-validate: an autonomy/approval-gate lens.** For any spec whose behavior runs inside an autonomous loop (`/execute`, `/goal`), a check: "does this let the loop make a scope / architecture / risk decision without a human gate?" Would have caught this cycle's HIGH at validate, not review. -> propose BACKLOG.
- [ ] **LOW: PLAYBOOK scenario-numbering reconcile** (already in TODOS.md): no Scenario 6 card; sections 8-11 use bare numbers on the scenario axis. -> propose BACKLOG (tiny).

## Kit feedback
The dogfood is positive evidence for the layered verification design: each layer caught a different bug class. `/spec-validate` caught a factual-correctness claim (the resume command); `/review` caught a missing guard + cross-surface inconsistency that the per-task and integration verifiers structurally cannot see; `doc-verifier` confirmed the docs matched the shipped code. The "review catches what verifiers miss" pattern recurred (ID-020 from the SPEC-024 retro), strengthening that backlog item. The one process smell the kit's own machinery did NOT prevent was release hygiene, which is now a two-cycle recurrence and the highest-signal kit finding here.
