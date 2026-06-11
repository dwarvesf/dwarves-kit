# Test design and conduct standard

The bar every work-item's tests meet, any profile (eval / tool-build / feature). Written from
one stance: a test you cannot watch fail is not a test, and a plan that does not drive the
tests is decoration. This standard exists because the opposite keeps happening, a plan that
under-covers, a green that never could have gone red, the same numbers hand-copied into three
docs until they disagree. Design against those, not around them.

## 1. The design drives the tests (write it before the code)

The `test-design.md` is authored before the change and is the **single home for coverage**:

- **Every acceptance criterion maps to at least one test, and every test maps back to an AC.**
  A traceability matrix (AC -> test -> expected negative control) lives here and nowhere else.
  If an AC has no test, the feature is not designed, it is hoped.
- **Every real path the change adds is exercised by a test of the real flow,** not a proxy that
  happens to pass. Name the path; name the test that walks it.
- **Enumerate the unhappy cases up front:** the boundary, the empty input, the absent marker,
  the revert. Bugs live at the edges; a design that only lists the happy path is half a design.
- **State the hypothesis and what would falsify it** before writing the assertion. If you
  cannot say what result would prove you wrong, you are not testing, you are confirming.
- **Grow the design as the feature grows.** A plan written for the first task and never updated
  is stale by the second. When scope expands, the matrix expands in the same change.

## 2. The test ladder (cheap and fast at the bottom, real and slow at the top)

Climb deliberately; do not skip rungs and do not stop early:

1. **Smoke** , does it run at all.
2. **Unit** , the logic in isolation; synthetic fixtures are allowed here, for speed.
3. **Integration** , the parts wired together.
4. **Live (real state)** , the real flow on the real artifact at least once, recorded. Synthetic
   fixtures prove the logic; they are regression speed, never the sole proof. A feature that has
   only ever run against `/tmp` mocks has not been shown to work.
5. **Adversarial** , a reviewer who is trying to break it, not bless it.

## 3. Conduct (how a run earns the word "pass")

- **Run the real primary flow,** the path the change adds, not a tangential green test.
- **Every load-bearing claim carries a negative control:** revert the work (or feed the input
  that should fail), watch it go RED, restore. A check that stays green when the work is removed
  proves nothing. This is non-negotiable for behavioral and stateful changes.
- **Capture, do not narrate:** the exact pasteable command, the real exit code, an output
  excerpt. "Tests pass" is a claim; the captured run is the evidence.
- **The no-check path is explicit and never upgraded.** When nothing is runnable, record
  `[NO EXECUTABLE CHECK: reason]`. A false PASS is worse than an honest gap.

## 4. Adversarial review (a distinct pair of eyes, bounded)

- **Producer is not reviewer.** The critique comes from someone (or some agent) other than the
  author, prompted to refute, not to agree.
- **Bounded loop:** produce -> critique -> revise, stop on zero findings or a hard round cap.
  Emit a machine-readable verdict and require the **finding count to strictly fall** across
  rounds. A loop where findings hold steady is a finding, not a pass.
- **Executor:** `/kit:test-plan-review-team` (SPEC-052) runs this section on a spec's `## Test plan`
  , 5 lenses in parallel, the bounded revise loop, a `## Test plan critique` verdict. It sits between
  `/kit:test-plan` (writes the plan) and `/kit:execute` (runs it). Report-only.

## 5. One source, three roles (this is how the artifacts divide)

Drift comes from copying. Keep each fact in exactly one place:

| Artifact | Role | Rule |
|---|---|---|
| `test-design.md` | the PLAN + the coverage matrix | the only home for AC -> test -> control |
| `runs/<ts>.md` | the RECORD of each execution | immutable, one per run, the single source of results |
| a consolidated report | an INDEX (verdict + pointers) | optional; points at runs, never re-copies their command/exit/output. For the eval profile the generated-numbers report IS the run artifact, so there is no separate copy to drift. |

If a report restates what a run already says, delete the restatement and link the run.

## 5b. Dialects: one spine, six bodies (per work type)

The six rules above are the spine for EVERY profile. How a test is DESIGNED differs by the
work's type (`lib/task-type-classify.sh`); design in the dialect that fits, not one-size BDD:

| Type | Test-design dialect |
|---|---|
| spec-feature | BDD-style scenario/coverage matrix over the acceptance criteria (the `## Test plan` /kit:test-plan writes: happy / boundary / failure-injection / security / regression, each with a proof command) |
| eval | metrics defined up front + HAND-VERIFIED seed data + falsifiability controls (a negative control that must go RED, a reproducibility re-run); the TEST-REPORT carries the numbers |
| research | claim-verification matrix: every load-bearing claim names its source AND an adversarial check (a refutation attempt, a second independent source, or a live probe); unverifiable claims are marked, not asserted |
| review | the report IS the proof: a verdict + findings each citing file:line (re-findable on the artifact), severity + Route per finding; a finding that cannot be located at its citation is killed, an empty-findings review states what was probed |
| migration | inventory coverage (every affected item enumerated) + conform/drift classification + a rollback REHEARSAL (not a rollback paragraph); cleanup sweeps use this dialect (convention migration) |
| data-tool | recorded live run of the real commands + a negative control (dead credential, fake field) proving the green is falsifiable; ledger immutable under `runs/` |
| doc | doc-verifier match: each claim in the doc greps against the live code/artifact it describes; a stale claim is a RED, not a style note |
| incident | evidence ledger: every hypothesis explicitly ruled in/out before the fix; the done check is the fired signal now silent + a regression guard on the root cause |
| reconcile | inventory coverage: every item enumerated with a verdict; negative control = a deliberately seeded drifted item must be caught by the sweep |
| operate | run ledger: an append-only per-execution record (command/exit/outcome) + a liveness/monitoring line proving the next deviation will alert |
| planning | inventory coverage over inputs: every source (board, PRs, calendar) swept; every decision in the digest traces to an input; the enqueued rows ARE the checkable output |
| learning | self-check matrix: concepts -> exercises -> pass bar; a score below the bar is a RED that loops back to practice, not a style note |

The dialect changes the SHAPE of the design, never the bar: every dialect still owes the
traceability of §1, the falsifiability of §3, and the recorded immutable runs of §5.
`/kit:test-plan` picks the dialect from the task's type; the registry
(`docs/verification/task-types.md`) maps type -> artifact -> owning skill.

## 6. Sign-off checklist (the gate before you call it done)

A work-item's tests are done only when every line is true:

- [ ] Every AC has at least one test, and every test traces to an AC (the matrix is complete).
- [ ] The real primary flow ran at least once on real state, recorded (not only synthetic).
- [ ] Every load-bearing claim has a negative control that was watched going RED.
- [ ] Each test is reproducible: a pasteable command, captured exit code, output excerpt.
- [ ] Edge / boundary / absent-input cases are enumerated and covered (or explicitly out of scope).
- [ ] A distinct reviewer critiqued it; findings fell to zero or hit the cap with residual noted.
- [ ] No fact is duplicated across docs; the report (if any) is an index, not a copy.
- [ ] Completeness sweep done: no AC without a test, no path unexercised, no claim unfalsified,
      no environment silently uncovered.

## Failure modes this prevents

- **The stale under-covering plan:** a `test-design` written for task one, never grown, while
  the real coverage hides in a report written after the fact.
- **Synthetic-only proof:** green unit fixtures standing in for a flow that never ran for real.
- **The green that cannot fail:** a pass with no negative control.
- **N-doc drift:** the same map or the same numbers hand-copied into design, report, and spec
  until they quietly disagree.
