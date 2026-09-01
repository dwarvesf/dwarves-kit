# Retro: spec-bound artifact placement + the UI-design loop

Date: 2026-05-21
Sprint: single session (SPEC-018, SPEC-023, SPEC-020), interleaved with a parallel session's cycle (SPEC-004/016/017/021/022)
Cycle trigger: a question, "what's wrong with persona/swarm theater?", that walked into building the honest version of it.

## Metrics
- Specs: 3 built (SPEC-018 test-plan-in-spec, SPEC-023 critique placement alignment, SPEC-020 ui-design loop); 1 drafted then dropped (SPEC-015, a near-duplicate of spec-validate, caught before building).
- Commits (this session): 5 distinct (`6374590` count fix, `3ae656e` WORKFLOW concurrency, `75518db` SPEC-023, `e9e6caf` em-dash sweep, `5b8f69a` SPEC-020); SPEC-018 folded into a parallel checkpoint commit.
- Research: 1 deep prior-art scan (`docs/research/2026-05-21-ui-design-loop-deep-scan.md`, 3 parallel agents).
- Tests: 218 meta / 92 hooks green at ship. Kit now 14 hooks + 20 commands + 11 agents.
- Each of the 3 specs was dogfooded through `/user:spec-validate` (5 parallel lenses) before build.

## What worked
- **Dogfooding `/user:spec-validate` caught a real defect in my work on every spec, five times total.** Specific: SPEC-018's `execute` wiring was lexical, not behavioral (a relabeled phantom the drift-guard would have protected); SPEC-023's draft misread SPEC-020's writer model and prescribed a contradictory "single writer" rule; SPEC-020 dropped `frontend-design`'s Constraints input AND proposed a numeric stop that visual-team's output cannot satisfy (3 of 5 lenses converged on the latter). The guardrails-over-guidance thesis paid for itself on the kit, by the kit.
- **research -> spec -> dogfood -> fold -> build, in that order.** The prior-art scan turned "build ui-design" into "build the right ui-design": the #1 finding was that the brief fed the critic, not the generator, which would have mis-fed `frontend-design` on the one input it reads first.
- **A context scan before speccing caught SPEC-015 as a near-duplicate of `/user:spec-validate`,** so it was dropped instead of built. The cheapest spec is the one you don't write.
- **The absorption bars held under a fat external skill.** `ui-ux-pro-max-skill` (renderer, 54 fonts, 76 CSVs, Node+Python tooling, 8 bundled skills) was absorbed down to ~4 prose patterns; the rest was rejected cleanly by bash-over-binaries + no-vendor-sprawl. `/user:ui-design` is now a worked example of absorbing a heavy skill down to only its in-lane shapes.

## What hurt
- **Count drift recurred the entire session** (15 -> 18 -> 19 -> 20). `CLAUDE.md` was stale at multiple points; the parallel session's `REVIEW.md` flagged it (issue 1) and explicitly recommended a count-consistency test (issue 4) that still does not exist; I hand-bumped 6 count surfaces. This is the session's recurring papercut and it is preventable.
- **I over-added on nearly every fold,** then the dogfood caught it: a numeric stop (SPEC-020), ceremony-wiring (SPEC-018), a single-writer rule (SPEC-023). Pattern: I imported an external pattern (e.g. claudekit's numeric stop) without checking it against the consuming interface (visual-team emits per-lens scores + a categorical verdict, no combined score).
- **Concurrent sessions corrupted release hygiene.** My SPEC-018 work landed inside a parallel "chore: checkpoint" commit instead of a clean `feat`; files were co-edited (some edits needed a re-read mid-flight); and the version state ended up broken (1.6.0 cut in CHANGELOG + VERSION + plugin.json but never tagged, latest tag v1.5.1, with `[Unreleased]` piled on top).
- **The `/user:ship` review gate passed on a stale, narrow `REVIEW.md`** (scoped to SPEC-016/017 only). The newer specs were validated via `/user:spec-validate`, not a `/user:review-team` code review of the diff, and the gate did not notice the scope mismatch.

## Action items
- [ ] Build a count-consistency meta-test: assert the "N hooks / N commands / N agents" strings across `plugin.json`, `marketplace.json`, README, MANUAL, `CLAUDE.md` all equal the live `ls | wc -l`. Permanently kills the count-drift class (REVIEW.md issue 4). -- owner: Han -- next cycle
- [ ] Resolve the release-version state: decide fold-into-1.6.0 vs cut-1.7.0, then bump VERSION/plugin.json/CHANGELOG and tag, so all version surfaces + git tags agree. -- owner: Han -- at PR #3 merge
- [ ] Make `/user:ship`'s review gate check `REVIEW.md` scope/freshness against the current diff (or warn when the diff has moved past the review's range), so a stale narrow review cannot satisfy the gate. -- owner: Han -- ship.md tweak, next cycle
- [ ] Personal discipline (and a candidate spec-validate reminder): when folding an external pattern, verify it against the consuming interface before writing it into the spec. -- owner: Han -- ongoing

## Kit feedback
- `/user:ship` trusts a `REVIEW.md` verdict without checking that the review covers the diff being shipped. Real gap; the gate is only as good as the review's scope, and nothing enforces that scope matches.
- Count drift is caught only reactively (by `/user:absorb` drift audit, the doc-impact map, or a human review). A proactive count-consistency meta-test would close the class; the kit values exactly this kind of guardrail.
- The kit has no story for two sessions on one branch. The version-state corruption came from that, not from any single command. Probably out of the kit's scope (git workflow), but worth naming: parallel-session work wants a discipline the kit does not provide.
- Positive: the spec-validate dogfood is the kit's strongest feature in practice. It caught five real defects this cycle. Whatever else changes, do not weaken it.
