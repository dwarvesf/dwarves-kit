# Implementation notes: SPEC-092 right-arm review parity (kit-hardening SG-04)

Delta from SPEC-092 / ADR-0028 / ADR-0029.

## 2026-07-02 recheck-verifier is a re-execution agent, never a summarizer of the prior verdict

Context: ADR-0029's 2026-07-02 Amendment pins `recheck-verifier`'s semantics as
re-execution, not a read-back of recorded evidence, because a read-back cannot catch
stale or fabricated evidence. The risk in drafting the agent was writing something that
reads AS IF it re-executes but is actually structured to just re-state the recorded
`Verification record` block in its own words.
Decision: the agent file states the rule three times in different forms (a bolded
one-line rule at the top of the body, a "What you do" section titled "Re-execute the
recorded command" as the first and only critical-weight check, and a Rules-section
restatement), and the output format's `Verification record` block is explicitly labelled
"fresh re-execution, not a read-back" so a lead skimming the verdict sees the distinction
even without reading the full prompt.
Why: the negative-control test (AC4, `tests/test-right-arm-parity.sh`) greps for both the
re-execution vocabulary AND the "not a read-back" vocabulary; a prompt that only had one
would still nominally "do the job" in prose but would not survive a skeptical reviewer
skimming the agent file for the pinned semantics.
Impact: any future edit to `agents/recheck-verifier.md` that removes the "not a
read-back" language breaks `tests/test-right-arm-parity.sh` (see AC3/AC4 there), which is
the intended fail-closed behavior for this agent's one load-bearing property.

## 2026-07-02 acceptance-verifier and system-verifier split on scope, not on tool shape

Context: both new right-arm dynamic verifiers use the identical scoped-Bash tool set
(`Read`, `Grep`, `Glob`, `Bash(npm test*)`, `Bash(go test*)`, `Bash(pytest*)`,
`Bash(bash tests/*)`, `Bash(git diff*)`) per the goal contract, so nothing in their
frontmatter distinguishes them -- the split is entirely in what each one is told to run.
Decision: `acceptance-verifier` is scoped to the ACTIVE SPEC's own `## Verification`
section (the acceptance gate the spec author designated); `system-verifier` is scoped to
the WHOLE PROJECT's suite, unscoped by any single spec, explicitly instructed not to
narrow its run to the files a spec touched.
Why: this mirrors the existing task-verifier (per-task) vs integration-verifier
(cross-task, whole-build) split -- same tool shape, different SCOPE of what "the
artifact" means for that phase. Keeps the four agents distinguishable by role even though
two of them are textually near-identical in frontmatter.
Impact: a future spec whose `## Verification` section is thin or absent is a finding for
`acceptance-verifier` to surface (not something for it to paper over by falling back to
running the whole suite, which would blur it into `system-verifier`'s job).

## 2026-07-02 brief-reviewer targets DECISION-BRIEF.md or the spec's Problem/Context, not a fixed single file

Context: `/kit:think`'s brief only lands as `docs/specs/DECISION-BRIEF.md` when the
verdict is BUILD (per `commands/think.md` Step 4); for a brownfield task that skips
`/kit:think`, the closest analogue to a "brief" is the spec's own `## Problem` /
`## Context` framing before the Decision section hardens.
Decision: `brief-reviewer`'s Input section names both possible targets (the file if
present, else the spec's Problem/Context section, or brief text pasted inline) rather
than hard-requiring `DECISION-BRIEF.md` to exist.
Why: the agent needed to be dispatchable in either lane (a full `/kit:think` pass, or a
spec written without one) without the goal contract or ADR mandating a `/kit:think`
prerequisite that does not exist today.
Impact: none on the acceptance criteria (AC1 only requires the agent file exist and
conform); this is a design note for whoever wires `brief-reviewer` into a command's
dispatch path later (out of scope for this sub-goal, which only builds the agent + fills
the roster/doc rows, per the goal's "In: the 4 new agent files... Out: ... a re-run of
the same verifier").

## 2026-07-02 Re-audit wiring is two dispatch points, not one shared step

Context: the goal calls for wiring the re-audit lens "where task-verifier runs after each
task (~line 183+) and where integration-verifier runs at Step 4" -- two separate places
in `commands/execute.md` with different cardinality (per-task vs once-per-build).
Decision: added `#### 2c-1. Fresh-context re-audit of a task-verifier PASS` immediately
after the existing PASS/FAIL:fixable/FAIL:escalate routing in 2c (line ~209), and a
`2b.` sub-step inside Step 4's numbered list immediately after the integration-verifier
routing (line ~331), rather than a single shared "recheck-verifier" section referenced
twice.
Why: keeping the two dispatch points inline at their trigger sites (right after the PASS
branch they re-audit) means a reader following the execution flow linearly sees the
re-audit exactly where the trust gap actually is, instead of jumping to a separate
section and back. Both sub-steps state the same advisory-not-a-hard-block rule (ADR-0024)
independently rather than via a forward/back reference, since each is scoped to a
different verification-log entry (`docs/verification/<spec-slug>.md` per-task line vs the
integration entry).
Impact: `tests/test-right-arm-parity.sh` AC5 greps `commands/execute.md` for
`recheck-verifier` + re-execute/fresh vocabulary without assuming a single fixed section
name, so this two-site wiring does not need special-casing in the test.

## 2026-07-02 Doc/roster sync included the stale total-count line in docs/architecture.md

Context: `docs/architecture.md`'s V-phase inventory carries a prose summary line ("Total:
25 commands + 11 agents = 36 entries..."). `tests/test-meta.sh` item (d) machine-checks
the table ROW count against the live file count, but not this prose line's arithmetic.
Decision: updated the prose line to 25 commands + 15 agents = 40 entries (10 build - 3
code - 9 test - 10 gate - 8 cross-phase) to match the 4 new rows, even though nothing
gates it.
Why: leaving it stale would be a direct, traceable consequence of this branch's own
edits (surgical-change discipline: the count changed because of rows this branch added),
and a future `doc-verifier` run would flag it as a contradiction anyway.
Impact: none on the SPEC-092 acceptance criteria; a small proactive fix riding the same
commit that touches the table it summarizes.
