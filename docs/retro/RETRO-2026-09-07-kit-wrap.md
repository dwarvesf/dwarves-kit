# Retro: `/kit:wrap` (SPEC-246, ID-644)

Full lane, one session. Two tasks, one lead task, one review wave that doubled as the battery, one CI fix.

## Metrics

- Tasks planned vs done: 3 of 3.
- Suites: `test-wrap.sh` 131 cases over five fixture repos and a recording `gh` stub; forwarders 41; meta 832; docs-wiring 25.
- Findings: spec gates 27 (8 design, 6 testability, 13 security, 5 of them blocking); post-build wave 17 (1 HIGH security, 3 HIGH coverage, 4 MEDIUM); CI 1 (portability).

## What worked

- Validation before build paid for itself: the security lens found five real bugs in the reference scripts the kit was about to port verbatim (a `develop` default deletable, `gh` answering from a fork parent, a child merged into a feature branch passing the squash proof, an unconstrained log path, swallowed write failures). All five became gates with tests before any code existed.
- Mutation testing as the acceptance bar for gates: "deleting this gate turns the suite RED" caught three gates that had tests in name only.
- One parallel wave serving both the review gate and the battery kept the wall clock flat without dropping an arm.

## What hurt

- Host-specific probes: the lock guard passed on macOS git and failed on ubuntu git because `git status` contends for `index.lock` on one build and not the other. The same class as the depth-1 checkout on the previous cycle: a green local suite is not a green CI suite.
- The spec's own `## Verification` line assumed a fixture-shaped repo (a grep that exits 1 on a real repo with zero open PRs).
- A reviewer briefed as read-only still ran `git checkout` in the shared worktree on the previous cycle; every brief now carries the sentence, and it held this cycle.

## Action items

- [ ] Any gate that reads host state (locks, mtimes, `stat`, `date`) gets a Linux run before the PR: `bash tests/run-workflow.sh` is not enough; push early and read the ubuntu leg.
- [ ] Spec `## Verification` commands run once on a real repo, not only on the fixture, before APPROVED.
- [ ] `wrap.activity_log` needs a per-operator home outside the kit checkout (a kit-root overlay file the consumer owns); until then the operator's activity line stays in the overlay skill.

## Kit feedback

- The ship-gate hook rejects the whole compound command, so a `git commit && git push` with a missing gate leaves nothing committed and no message about which half ran. Worth a one-line note in WORKFLOW.md under the gate section.
