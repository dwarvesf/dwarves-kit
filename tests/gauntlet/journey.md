# The contributor journey (persona A: kit user)

The feature list `/kit:test-plan` consumes to derive the scenario matrix
(SPEC-227 P1). Each section is one journey feature with 2-4 checkable
acceptance criteria, stated in the kit's own terms (commands, files, verdicts
that actually exist per `docs/MANUAL.md` and `docs/guides/spine.md`). This is
the spec; `scenarios.md` is its derived coverage matrix.

## Install

A developer with no prior kit contact gets it running.

1. Either install path works from the kit's own docs alone: the plugin path
   (`/kit:<name>` invocations) or the bash path (`bash install.sh`, bare
   `/<name>` invocations) , the developer picks one and it works without
   guessing.
2. `bash lib/onboard-detect.sh` (or `/kit:onboard` reading it) reports a mode
   (`plugin` / `bash` / `both` / `none`) the developer can act on.
3. After install, at least one `/kit:*` (or bare `/*`) command is invocable in
   a fresh Claude Code session.

## Adopt

A target repo gets the operate-contract injected.

1. `bash lib/adopt.sh --check <repo>` reports "not adopted" before, and
   "adopted: <repo>" after running `bash lib/adopt.sh <repo>` (or `/kit:adopt`).
2. Adoption leaves `AGENTS.md`, `WORKFLOW.md` (pointer), a `CLAUDE.md` managed
   block (`<!-- kit:adopt -->` ... `<!-- /kit:adopt -->`), and the proof marker
   `docs/verification/README.md` in the target repo.
3. Re-running adopt on an already-adopted repo is idempotent (no duplicate
   blocks, `.kit.toml` untouched if already present).

## Tiny lane

A small, well-scoped fix ships without full SDD ceremony.

1. A fix under the tiny-lane size (per `docs/guides/lanes.md`) can go straight
   to a branch + commit + `PR.md` without a `docs/specs/SPEC-NNN` file.
2. The commit subject is conventional (`fix|docs|feat|chore|refactor|test`,
   optional scope, no SPEC-/TASK- marker) , `commit-format` enforces this on
   every `git commit -m`.
3. `PR.md` carries a title and a body (the PR-shaped submission the gauntlet
   checkers look for).

## Full lane

A feature-shaped ask goes through the whole spine end to end.

1. The spine's shape order holds: `/kit:assign` -> `/kit:spec` ->
   `/kit:spec-validate` (Status: VALIDATED) -> `/kit:execute` -> `/kit:review`
   (or `/kit:review-team`) -> `/kit:docs` -> `/kit:ship`.
2. A spec file exists at `docs/specs/SPEC-NNN-<slug>.md` with acceptance
   criteria and a `## Verification` section BEFORE implementation commits
   begin (spec precedes code, not the reverse).
3. `/kit:execute` dispatches a worker + `task-verifier` per task; tests exist
   for the shipped behavior and pass via the spec's own verification command.
4. `/kit:review`'s verdict (`SHIP` / `FIX-REQUIRED` / `DO NOT SHIP`) is
   recorded in the spec's `## Review` section (or reported inline with no
   spec), and `/kit:ship` will not proceed past a DO NOT SHIP verdict.

## Debug

Something is broken; the bug lane finds the root cause before fixing it.

1. `/kit:debug` writes an evidence ledger `.claude/debug/<slug>.md` whose
   `## Root cause` section is filled in BEFORE any fix commit , the
   `anti-rationalization` hook blocks a "done" claim while that section is
   blank.
2. The four phases run in order (root cause -> pattern -> hypothesis -> fix);
   the fix is a failing test made to pass, not a guess.
3. After a confirmed fix, `/kit:review` runs on the diff (the debug loop's own
   documented next step).

## Gates / proof

A behavioral change satisfies the ship gate before it can push or merge.

1. `ship-gate` (PreToolUse on push/PR-create) blocks a behavioral change with
   no matching entry in `docs/verification/` and no gate-ledger record for the
   lane's phases.
2. `/kit:verify` re-runs the test levels (task/integration/acceptance/system
   verifiers) read-only and prints a PASS/FAIL verdict without rebuilding or
   auto-fixing.
3. Passing looks like either a `docs/verification/<name>.md` proof-of-done
   with a negative control, OR a documented override
   (`lib/gate/proof-ledger.sh override '<slug>' "<reason>"`) , both are valid,
   silence is not.

## Drift amend

The ask changes mid-build; the spec amends instead of silently widening.

1. A mid-flight "also do Y" is NOT handled by silently editing the spec or
   restarting the lane , it reaches a task checkpoint first (finish + verify +
   commit the in-flight task).
2. The amendment is add-only: new `- [ ]` tasks appended, the delta recorded
   in an `## Amendments` entry; already-completed `- [x]` tasks are left
   untouched.
3. Spec `Status` stays `VALIDATED` (only the delta is re-validated, not the
   whole spec); `/kit:next` (not a fresh `/kit:execute`) resumes and runs only
   the newly appended tasks.

## Resume

A session dies mid-work; a fresh session picks up from disk, not from memory.

1. State lives on disk between steps (`docs/specs/SPEC-*.md` task checkmarks,
   `.claude/session-state/last-state.md`), never only in the dead session's
   context.
2. A fresh session run from `/kit:start` orients from that disk state (spec
   status, task checklist, git branch/dirty count) and does not restart
   already-completed work.
3. If `last-state.md` is missing or corrupt, the most recent snapshot under
   `.claude/session-state/archive/` is the documented fallback.

## Review response

Review found something; the response is a fix, not a verdict negotiation.

1. `/kit:review` or `/kit:review-team` records a verdict (`SHIP` /
   `FIX-REQUIRED` / `DO NOT SHIP`) in the spec's `## Review` section (or inline
   if no spec exists).
2. On `FIX-REQUIRED`/`DO NOT SHIP`, `responding-to-review` triages the
   findings on their technical merit (pushes back on a wrong finding,
   implements a real one) , it does not perform agreement to move on.
3. `/kit:ship` is blocked while the recorded verdict reads DO NOT SHIP; the
   loop back through fix -> re-review is the only documented path to green.
