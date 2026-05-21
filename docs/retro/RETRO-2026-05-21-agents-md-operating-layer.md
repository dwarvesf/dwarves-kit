# Retro: AGENTS.md operating-layer cycle
Date: 2026-05-21
Sprint: single-session cycle (spec-validate -> execute -> review-team -> docs -> ship)
Spec: SPEC-024 (v1.7.0, PR #7)

## Metrics
- Tasks planned: 10, completed: 10, deferred: 0 (2 LOW review findings -> backlog ID-018/019)
- Commits: 16 (build 15 + ship-state 1), atomic, all passed the commit-format hook
- Files changed: 18 (+453 / -57)
- Tests: test-meta 216 -> 241 (+25 asserts), test-hooks 92; both exit 0 throughout
- Verification pipeline: 10/10 task-verifier PASS, 0 retries, 0 escalations; integration-checker PASS (10/10 wired, 6/6 chains)
- Completeness log: clean
- Key commits: 7c5015c (AGENTS.md), b7bb3ee (six-section projection), 6ec7880 (test asserts + install-merge guard), 3ba7022 (review fixes)

## What worked
- **Adversarial spec-validate paid for itself before any code.** It caught two real defects in the draft: (1) the phantom `install.sh` jq "fix" claimed done with no diff (DEC-004), and (2) an unsatisfiable TASK-001 AC (four AGENTS.md zones described, six demanded, "1:1 mapping" false by the spec's own diagram; DEC-005). Both would have produced a broken or dishonest build. Fixing the spec was cheap; fixing it post-execute would not have been.
- **The honest "test + fix-if-surfaced" reframe of DEC-004 resolved cleanly.** Because the spec stopped claiming a fix and made TASK-009 own "add the test, apply a fix only if it fails", execute proved no bug existed and shipped a regression guard instead of a false changelog line. Honesty in the spec produced an honest changelog.
- **Grep-based acceptance criteria made every task mechanically verifiable.** 10/10 PASS, 0 retries. Doc/config/bash tasks with `grep -q` ACs gave the task-verifier real teeth without a unit-test framework.
- **The doc-impact map did its job at /docs.** It surfaced two companions the build missed (MANUAL `/user:assign` Reads/Writes; CLAUDE downstream-template note); the doc-verifier then confirmed the fixes (9 claims, 0 contradictions).

## What hurt
- **The execute pipeline AND the integration-checker both rubber-stamped the WORKFLOW read-order restatement.** TASK-002 was "replace, don't duplicate", but its worker left a numbered 1-4 read-list AND a "do not restate" pointer (the exact anti-pattern). The task-verifier passed it (checked the pointer existed + AGENTS.md-first; never checked the old list was gone). The integration-checker's seam-2 "no duplication" check also passed it (saw the "do not restate" sentence and stopped). Only the independent /review-team architecture lens caught it. Root cause: presence checks ("the pointer exists") do not catch absence-invariant failures ("the duplicate is gone"). Negative invariants need explicit negative assertions.
- **Recurring shell/hook friction made every worker rediscover the same three workarounds.** fish `noclobber` aborted `>` redirects to existing temp files; the commit-format/commit-msg path mis-parsed heredoc `-m` messages as a 459-char subject; the safety-gate blocked `rm -f` of temp files. Each worker burned cycles relearning: use `>|`, `git commit -F`/Write-tool message files, and `mv` instead of `rm`. I started pre-warning these in later worker prompts, which helped.
- **The orchestrator edited an acceptance criterion mid-execute.** When DEC-004 resolved as no-bug, I changed TASK-010's CHANGELOG expectation from "fix" to "coverage" during the build. Necessary and later recorded as a spec amendment, but mutating the contract mid-flight (rather than at a checkpoint) is a process smell the architecture review flagged.
- **Retro-file naming is still three-way inconsistent** (this file's `RETRO-YYYY-MM-DD-<slug>.md`, a stray `RETRO-2026-05-21.md`, an old `v1.3-v1.5.md`; the retro skill body says `RETRO-[date].md`, WORKFLOW says `v<version>.md`). This is ID-017, still open.

## Action items
- [ ] Teach the task-verifier + integration-checker to check ABSENCE for replace/remove tasks (assert the replaced/removed content is gone, not just that the new pointer exists). The specific anti-drift test now exists; the general verifier gap does not. -- relates to ID-016 -- owner: Han -- next kit cycle
- [ ] Pre-warn the shell/hook gotchas in the `commands/execute.md` worker template (fish `noclobber` -> `>|`; no heredoc commit `-m` -> `git commit -F`/Write; no `rm` -> `mv`). One block, saves every future worker the rediscovery. -- new backlog item -- owner: Han -- next kit cycle
- [ ] Resolve ID-017 (retro-file naming): pick `RETRO-YYYY-MM-DD-<slug>.md`, reconcile the retro skill body + CLAUDE.md + WORKFLOW.md. -- already queued (ID-017) -- owner: Han
- [ ] ID-018 (install tip `cp -n`) and ID-019 (demo SPEC-001 `## After state`) -- already queued from review -- owner: Han

## Kit feedback
- **Investigate the commit-message heredoc mis-parse.** Workers reported the commit-format/commit-msg hook reading a multi-line heredoc `-m` body as a single 459-char subject and rejecting it. If real, the hook should read only the first line as the subject. Worth a look (possible new backlog item); not yet confirmed as a kit bug vs heredoc misuse.
- The commit-format hook correctly blocked spec-ID/phase-marker subjects (it caught my own "phase 1" subject). Working as intended.
- The verification pipeline's blind spot (presence-not-absence) is the highest-signal kit finding this cycle: a "replace" task that left both copies passed two independent verifiers.
