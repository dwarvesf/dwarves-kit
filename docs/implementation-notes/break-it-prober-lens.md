# Implementation notes: SPEC-246 break-it prober lens

Delta from the spec only. Nothing here restates what the spec says.

## 2026-09-07 10:20 Spec phase ran unattended; two lane beats degraded

**Context.** The think -> design -> spec -> spec-validate chain ran in an unattended worker under
bypassPermissions.

**Decision.** `/kit:design` settled every design call itself and recorded the rejected alternative
beside each one, instead of blocking on the per-section approval loop.

**Why.** Under bypassPermissions `AskUserQuestion` auto-resolves, so the approval loop would have
produced fake consent. The lane's own text names this case and asks the runner to say so plainly.

**Alternatives.** Stop and wait for the operator. Rejected: the run is unattended and the design
calls are all reversible by editing one section.

**Impact.** Every design decision is overturnable by reading one table row, but none of them
carries operator assent. The three that most deserve a look are in the spec's `## Open questions`.

## 2026-09-07 10:25 The agent name collides with a guardrail test

**Context.** `tests/test-meta.sh` derives the review-agent roster from the live `agents/` dir and
requires each read-only agent to end in `-reviewer` / `-verifier` / `-team`, or to be one of two
allowlisted named nouns.

**Decision.** Keep the board row's name, `break-it`, and add a `break-it)` arm to
`is_on_review_axis()`.

**Why.** The lens reads the whole branch, not one artifact class, which is the same reason
`advisor` and `agent-effectiveness` already sit in that allowlist.

**Alternatives.** Name it `probe-reviewer`, which passes the axis test untouched. Rejected because
the `-reviewer` suffix asserts a per-artifact lens, which this is not.

**Impact.** The spec widens a guardrail test's accept set. AGENTS.md zone 4 makes that an operator
decision, so it is a DEC row and an open question rather than a settled call.

## 2026-09-07 10:30 The rung order is stated, not enforced

**Context.** `mutation-smoke.sh` is invoked from `commands/verify.md` Step 6b. The battery, where
the probe rung lands, never calls it.

**Decision.** Battery prints the three-rung ladder and names mutation-smoke as the next rung. No
code enforces the order.

**Why.** The enforcing version (Step 6b skips when the rid carries no break-it verdict) converts an
advisory gate into a conditional block, which ADR-0024 reserves for the operator.

**Open question.** Whether to take that step. Recorded as open question 1 in the spec.

## 2026-09-07 10:50 Spec-validate found two CRITICALs, both fixed before the flip

**Context.** Reviewers 1-5 ran as two independent fresh-context panels rather than inline, because
the same session wrote the spec.

**Decision.** Fold the `is_on_review_axis()` arm into TASK-001, and hold the read-only claim with a
prompt-level command-safety rule instead of narrowing the tool roster.

**Why.** Reviewer 3 proved the original phase split leaves `tests/test-meta.sh` red between two
tasks, so TASK-002's own acceptance criterion could not pass as sequenced. Reviewer 1 rated the
wildcard `Bash(npm test *)` grants a CRITICAL for a probe-class agent.

**Alternatives.** Narrow the roster to argument-free invocations. Not taken: the board row asks for
the `code-reviewer` roster, and a repo whose suite needs a flag would break. Recorded as open
question 4 instead of settled.

**Impact.** DEC-006 through DEC-009 record every validate-driven change. Two open questions are new
(the roster, and whether manual review is enough for the probe-yield measurement).

## 2026-09-07 Build phase: the five open questions were settled by the lead

**Context.** The spec flipped to VALIDATED with five open questions. The build phase received
answers for all five and did not re-ask.

**Decision.** (1) The probe/mutation ladder stays advisory, stated in `commands/battery.md` and
`docs/WORKFLOW.md`, never enforced. (2) "Probing succeeds" reads as `NO-PROBE`, so the mutation
rung is the next rung after a clean probe; DEC-005 stands. (3) The name stays `break-it` and the
`is_on_review_axis()` arm lands as TASK-001 wrote it. (4) The `code-reviewer` tool roster is
unchanged, held by the prompt-level command-safety rule; DEC-007 stands. (5) Probe-yield
measurement is manual for v1, no counter.

**Impact.** Open questions 1 through 5 are answered. The spec text keeps them for the record.

## 2026-09-07 TASK-001's own acceptance criterion needs TASK-005's docs rows

**Context.** TASK-001 AC3 asks for `bash tests/test-meta.sh` green with the agent present.
Adding `agents/break-it.md` fails four `test-meta.sh` checks at once: the MANUAL cross-ref, the
README agents-row count, the `docs/architecture.md` inventory row count, and the SPEC-219
`docs/FEATURES.md` freshness pin.

**Decision.** Land the docs rows in the same pass as the agent, and verify TASK-001 AC3 at the
end of the build rather than at the end of TASK-001.

**Why.** DEC-006 already found this class once, for the naming-axis arm. It found only one arm of
it: every derived-count pin in `test-meta.sh` is red the moment a new agent file exists, not just
the naming axis.

**Alternatives.** Reorder the spec so TASK-005 precedes TASK-001. Rejected: the docs rows cannot
be written before the agent they describe exists.

**Impact.** Two docs surfaces the spec never named are also touched: `docs/architecture.md`'s
V-phase inventory table and the generated `docs/FEATURES.md`. Both are mechanical consequences
of adding an agent file, not scope growth.

## 2026-09-07 The naming-axis negative control runs on the extracted function, not a full test-meta run

**Context.** TASK-001 AC4 asks that deleting the `break-it)` arm makes `bash tests/test-meta.sh`
fail. A full `test-meta.sh` run exceeds two minutes, so a test that runs it twice per assertion
would dominate the suite.

**Decision.** `tests/test-break-it.sh` extracts `is_on_review_axis()` from the live
`tests/test-meta.sh` with awk, evaluates it as shipped and again with the arm stripped, and
asserts the two disagree on the name `break-it`.

**Why.** The extracted function is the SAME code the roster scan calls, so the control proves the
arm is load-bearing without paying for two full runs. A vacuity guard asserts the strip actually
removed a line.

**Alternatives.** Run the full suite twice. Rejected on cost. The manual negative control in the
spec's `## Verification` still exercises the whole path by hand.

**Impact.** AC4 is proven by an equivalent, faster control. The assertion text names it a
negative control so a reader is not misled about what ran.

## 2026-09-07 The tight fixture takes its implementation path from an env seam

**Context.** The negative control has to run the tight suite against a guard-stripped
implementation without editing the committed fixture mid-run.

**Decision.** `tests/fixtures/break-it/tight/test.sh` reads `BREAK_IT_IMPL`, defaulting to its own
`impl.sh`. The test strips the `GUARD-LINE`-tagged line into a temp file and points the seam at it.

**Why.** A test that edits a committed file and restores it leaves the repo dirty when it dies
mid-run. The seam keeps the control read-only over the working tree.

**Impact.** The spec's manual negative control (edit the file, re-run, restore) still works
unchanged, because the default path is the committed `impl.sh`.
