# SPEC-042: Proof of done (execution-backed verify + negative control)

Status: SHIPPED
Lane: normal
Backlog: (none; maintainer "proof of done" framing, 2026-06-06)
Branch: feat/verify-by-execution (built, then SDD-documented)

## Problem

The kit's "Verify before proceeding" principle ran the test suite but the result
evaporated into a prose "Tests: passing" line nobody could re-run. Worse, a green run
alone does not prove the check exercises the change , a check that passes no matter what
proves nothing. "Done" was a claim, not an artifact a skeptic could re-run.

## Solution

"Done" becomes a **proof of done**: a recorded artifact with three parts , (1) the check
run for real with command + exit + output excerpt captured, (2) a **negative control**
showing the same check goes RED when the work is reverted, (3) reproducible by re-running
the logged command. The log lives at `docs/verification/<spec-slug>.md`; the convention
is `docs/verification/README.md`. The verify agents/commands capture the run, emit a
`[NO EXECUTABLE CHECK: reason]` marker instead of a fake pass when nothing runs, and
produce the negative control for load-bearing changes. `task-verifier`'s tool allowlist
was widened to run a bash/make project suite (not only npm/go/pytest/cargo).

## Scope

In:
- `agents/task-verifier.md` (Verification record block, no-check marker, negative-control flag, bash-suite tools).
- `commands/execute.md`, `commands/verify.md` (write the log; produce the negative control on load-bearing changes).
- `commands/review.md` (reads test state from the log; static-judgment boundary).
- `docs/verification/README.md` (the convention + the proof-of-done definition).
- `docs/PHILOSOPHY.md` (the execution-backed-verify bend).
- The pinning meta-tests in `tests/test-meta.sh`.

Out:
- No new command, no new agent. No blocking ship-gate hook (deferred enforcement escalation).

## Task Breakdown

### Phase 1: Proof of done

- [x] TASK-001: Execution-backed verification + the verification log + negative control.
  Acceptance criteria:
  - The full meta-test suite passes: `bash tests/test-meta.sh` exits 0.
  - The proof-of-done convention exists and is named: `docs/verification/README.md`
    contains both "Proof of done" and "negative control".
  - The verify agents/commands carry the convention: `agents/task-verifier.md` has a
    `Verification record` block and a `[NO EXECUTABLE CHECK:` marker; `commands/execute.md`
    and `commands/verify.md` reference `docs/verification/` and a `NEGATIVE CONTROL` entry.
  - These invariants are pinned in `tests/test-meta.sh` (they fail if the implementation
    is reverted , the negative control).

## Verification

Run: `bash tests/test-meta.sh` (expect exit 0, all pins pass).

Proof of done for this spec is recorded at `docs/verification/proof-of-done.md`: a GREEN
entry from a real run, a NEGATIVE CONTROL entry showing the pins go RED when the
implementation is reverted to `master`, and reproducibility (re-run the logged command).
