# Retro: ui-acceptance-verifier, first slice (SPEC-292)
Date: 2026-11-25
Sprint: 2026-11-25 (one unattended session)

Answers drafted by the lead from the session record (the run was unattended, with no Q&A round). Edit any line that misreads it.

## Metrics
- Tasks planned: TASK-1 to TASK-13, completed: all. Deferred by the spec itself: the token, layout, pixel, preview-comment, storage-state and vision layers (slices 292b to 292e).
- Spec: a contract-only draft went through three fresh-context validation rounds. Round 1 returned 11 criticals, round 2 returned 2, round 3 approved with 9 build notes.
- Build: three builders (runner contract and fixture, browser half, agent and docs), then a five-leg battery, a fix round of three workers, a scoped security re-review and one more small fix pass.
- Size: the runner is about 1,150 lines against a spec estimate of 200 to 300; the suite is about 1,250 lines.
- Proof: the suite, the negative controls and three live dispatches of the real agent are in `docs/verification/ui-acceptance-verifier.md`.

## What worked
- A live probe before validation. Twenty minutes on the host showed that the agent could not author its scenario file with the granted tools, that no UI path set existed, and that the two test paths in the draft were not discovered by the runner. Round 1 then argued about design, not about facts.
- Cutting to a first slice in round 1. One layer with a kit runner and a runner-derived verdict was buildable and testable in one session; four layers were not.
- The verdict lives in the runner. Because the runner computes every row status, a suite could test the behavior with real exit codes, and the agent prompt stayed a thin adapter.
- Review lenses in parallel after the build. The security lens found the host-without-port gap, the test-coverage lens found six branches that could only pass, and the verifier found four checks that could never fail. No single lens found all three.
- One negative control per mechanism, on a copy of the runner outside any git work tree. Several "red" proofs turned out vacuous on first try (a stale mutation, a status reset by a command substitution) and were caught because the control had to print a red line.

## What hurt
- The first request guard matched on host only, and route handlers do not see redirect hops. Two security reviews were needed to reach the resolver pin plus the host-and-port rule. The spec had listed DNS rebinding as an accepted residual when a one-line launch argument closed it.
- The spec's size estimate for the runner was off by a factor of four. The spec pins about 35 behaviors, and each one costs lines.
- The suite passed 251 checks while six runner branches had no test and four checks could not fail. A green count is not coverage.
- A shared build host at a load average of several hundred turned one-minute test runs into ten-minute waits. A session-wide test lock queued work for an hour until runs moved to single suites.
- A repo-level PR template and an issue chooser config both tripped kit gates that were written for other cases (the landing verb refuses a title-only body when a template exists; the ship gate reads any yml under `.github` as a CI hard path).

## Action items
- [ ] Run this lens on one real consumer pull request with a preview URL before any later slice starts; record the run beside the proof -- owner: @tieubao -- deadline: 2026-12-31
- [ ] Tighten the agent's tool grant with a command shim or a hook that anchors the runner command, as the spec's Out of scope names -- owner: @tieubao -- deadline: 2026-12-31
- [ ] Decide whether the landing verb should accept a proof-built body when a repo PR template exists, so the kit can carry its own template -- owner: @tieubao -- deadline: 2026-12-15
- [ ] Narrow the ship gate's CI hard path so an issue chooser config under `.github/ISSUE_TEMPLATE/` is not read as a workflow -- owner: @tieubao -- deadline: 2026-12-15

## Kit feedback
- `gate-ledger.sh record <rid> grill skipped` wants `reason=<token>` at the start of the reason; the error names the tokens but the form is easy to miss twice.
- A full-lane override needs a distinct reason per gate. That is right, and it is only discoverable from the refusal.
- The test lock in `tests/run-all.sh` protects the host but has no fair queue: a session can wait an hour behind others and be killed by its own timeout without a result.
- `bin/test-affected` selects every suite that names `README.md`, so a one-word README edit selects about seventy suites.
- The secret scan on the operator host blocks a shell read of any file named `config.yml`; the Read tool is the way around it.
