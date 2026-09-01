# Implementation notes, SPEC-019 greenlight CI lane

Delta from the spec only. Scope: TASK-1 (Phase A, the CI-green core) only. TASK-2 through TASK-5 are not touched.

## 2026-08-27 Invocation is `/kit:greenlight`, not the dead user-prefix form

Context: the spec's own title and body use the dead user-prefix greenlight form throughout (it predates the
kit's namespace migration).

Decision: `commands/greenlight.md` refers to itself as `/kit:greenlight` (and points to
`/kit:ship`, `/kit:review`, `/kit:review-team`), never the user prefix.

Why: `tests/test-meta.sh`'s dead-prefix invocation-form guard (SPEC-029/SPEC-030)
scans every tracked `commands/*.md`; the user-prefix literal in the new file would fail
that check immediately. The kit's live invocation form is `/kit:<cmd>` (plugin) or bare
`/<cmd>` (bash install).

Impact: none beyond the file itself; every other command in the repo already follows this
convention, the spec text is simply stale on this one point.

Open questions: none, this is a mechanical correction.

## 2026-08-27 Max-iterations cap set to 10, not spec-pinned

Context: the spec requires "a max-iterations cap" (DEC-010) as the hard bound the per-commit
flaky-retry-budget reset cannot escape, but does not pin a number.

Decision: default cap of 10 loop iterations per invocation, overridable via
`$ARGUMENTS` (e.g. `42 --max-iterations 5`).

Why: needs *a* bounded default to be runnable; 10 is a reasonable middle ground between
"too tight to ride out a couple of legitimate re-runs" and "effectively unbounded". Kept
overridable rather than hardcoded so a caller with a slower CI matrix isn't stuck.

Impact: none on other tasks; TASK-4's test can assert the cap exists without asserting the
exact number.

Open questions: whether 10 is the right steady-state default is worth revisiting once the
command has real dogfood mileage on the kit's own PRs.

## 2026-08-27 Local verify is a separate step, not a read of fix-agent's self-reported test line

Context: `agents/fix-agent.md` already runs the test suite as its own Step 3 and reports a
`Tests: [passing/failing]` line. DEC-008 could plausibly be satisfied by just trusting that
line.

Decision: Step 4 of the command runs the project's test suite again, directly (same runner
detection as `/kit:ship` Step 2), independent of fix-agent's internal run, before treating a
fix as push-eligible.

Why: DEC-008's own rationale explicitly says local verify "mirrors the kit's
worker->verifier discipline at PR altitude" (execute.md's Step 2d re-runs task-verifier as a
distinct step after fix-agent, rather than trusting fix-agent's self-report). An independent
re-run also protects against fix-agent's report being wrong or a bot-suggested change slipping
through.

Impact: one extra local test-suite run per fix attempt versus the cheaper alternative; bounded
by the same iteration cap.

Open questions: none.

## 2026-08-27 `done`'s "no pending reviews" clause is FYI-only in Phase A

Context: SPEC-019's terminal-states table defines `done` as "CI green, no pending reviews",
and edge case 2 frames "PR already green" as including "no pending reviews". Acting on review
comments (FIX/DISAGREE/DEFER) is explicitly Phase B (TASK-2, DEC-009), not built here.

Decision: Step 8 reports `reviewDecision` alongside the `done` verdict as an informational
line, but does not gate the terminal state on it -- a PR with all-green CI and a pending
review still reports `done` (CI-green), with the review state named in the summary.

Why: gating `done` on review state would require greenlight to either act on reviews (out of
scope, Phase B) or silently swallow the distinction; naming it in the summary keeps the report
honest without expanding TASK-1's scope into TASK-2's territory.

Impact: `/kit:greenlight`'s `done` means "CI is green", not "fully mergeable"; the summary
line is what closes that gap for the human reading it.

Open questions: whether TASK-2 should instead introduce a `done_pending_review` terminal state
rather than folding review-state into `done`'s summary; left for TASK-2 to decide.
