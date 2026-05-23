# Retro: V-model lens + lead-owned convergence (SPEC-031 / ID-034)
Date: 2026-05-22
Sprint: single session, 2026-05-22 (research -> spike -> spec -> execute -> review -> ship)

## Metrics
- Tasks planned: 7, completed: 7, deferred: 0, amendments: 1 (AMEND-001)
- Commits: 15 in PR #11 (10 build+review+ship)
- Files changed: 12 (+500 / -35)
- Key commits: bce00da (ADR-0018), cef3dfd/75e0703 (8-phases reword), 3f3b04d (lens), 124b9bc (matrix), 46416a9 (inventory), 8df8289 (convergence), 517dd68 (guards), af75b96 (guard hardening)
- PR: https://github.com/dwarvesf/dwarves-kit/pull/11
- Completeness log: clean

## What worked
- **Spike before spec.** SPEC-033 + ADR-0020 ran the dispatch-primitive bakeoff BEFORE finalizing SPEC-032, locking the primitive with a real run (proved the `claude agents` agent view is monitor-only, no CLI create) and answering the maintainer's actual question. Two cheap background workers de-risked the bigger spec instead of building `/kit:dispatch` on an assumption.
- **Layered verification each caught a distinct defect the prior gate missed.** spec-validate (partial AC fix + regex widening) -> execute / AMEND-001 (the self-defeating AC) -> review (the self-disabling guard). Three gates, three separate catches. The pipeline is not redundant.
- **Evidence over assertion.** Checking the live doc-impact map REFUTED a suspected hands-off-subset critical; checking the real `claude` CLI help REFUTED the researched `claude --bg`. Precision came from running things against reality, not reasoning about them.

## What hurt
- **spec-validate passed a self-defeating acceptance criterion.** SPEC-031's original "no `8 phases` anywhere" grep could never be empty, the spec itself + ADR-0018 must quote the phrase. The adversarial review reasoned about the AC but never RAN it; `/kit:execute` caught it mid-build, costing an amendment cycle (AMEND-001 scoped the check to operating surfaces). Root cause: spec-validate does not dry-run the spec's own verification commands against the repo.
- **The new guards shipped self-disabling.** TASK-007's loops over `sed`/`grep`-extracted lists would vacuously pass (green) on an empty extraction; plus a dead `grep -F "^..."` branch. task-verifier confirmed happy-path falsifiability but did not probe the "extraction breaks" case. Caught only at `/kit:review`, fixed in af75b96. Root cause: no rule that a loop over an extracted list must assert the list is non-empty.
- **Doc-impact drift on ADR cross-refs.** ADR-0020 has its README cross-ref but not the `docs/architecture.md` one; ADR-0017 has neither. Both slipped because they were committed outside SPEC-031's task structure (the spike + pre-session work), where the doc-impact map's "new ADR -> README + architecture.md" companion check was not enforced.
- **Minor friction:** the markdown formatter reflowed long spec paragraphs, repeatedly invalidating `Edit` old_strings (one done-tag edit failed and was retried); the fish `>` noclobber redirect produced one false test "FAIL" label on a passing suite.

## Action items (DEFERRED, maintainer to revisit, not promoted this cycle)
- [ ] AI-1: `/kit:spec-validate` should DRY-RUN the spec's `## Verification` block + AC-proof commands against HEAD and report results, not just reason about them. (Would have caught the self-defeating AC at validate.) Meatiest; candidate for its own spec.
- [ ] AI-2: Test-authoring rule, a loop over a `sed`/`grep`-extracted list MUST assert the list is non-empty (>= expected count) before iterating. Candidate for a CLAUDE.md quality rule + worker/test-verifier guidance. Cheap, high-value.
- [ ] AI-3: Spec-template guidance, absence-check ACs ("no string X anywhere") must scope to live operating surfaces and exclude the specs/decisions/research archive that legitimately quotes X.
- [ ] AI-4: Backfill the ADR-0020 (+ ADR-0017) `docs/architecture.md` cross-ref the doc-impact map prescribes.

## Kit feedback
- The `ouroboros:welcome` skill-suggestion false-fired on EVERY turn of this session (a skill-suggestion hook proposing an unrelated welcome flow). Pure noise across a ~15-command session; worth scoping or muting the suggestion trigger.
- Formatter-vs-`Edit` friction on long docs: the auto-formatter reflows wrapped paragraphs after each edit, which invalidates subsequent `old_string` matches in the same region. Mitigated by re-reading before each edit, but it slows multi-edit doc work.
