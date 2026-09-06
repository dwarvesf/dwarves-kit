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
