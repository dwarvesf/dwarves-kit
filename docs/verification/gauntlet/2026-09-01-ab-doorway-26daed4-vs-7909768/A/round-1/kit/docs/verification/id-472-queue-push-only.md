# ID-472: queue `--push-only`, PR-open moves to the authed client

## Claim

`queue.sh run ... --push-only` (env `QUEUE_PUSH_ONLY=1`) types a goal-line
clause telling the launched run to commit + push its branch and stop, never
running `gh pr create`. This is for a runner host with no GitHub credentials
(SSH push works, `gh` does not); opening the PR moves to the authed CLIENT
session. The flag overrides `--ready` (no PR at all is a stronger claim than
which kind of PR).

## Run table

Command: `bash tests/test-cheap-guards.sh`
Exit: 0
Verdict: PASS (23/23 passed)

| # | Action | Result |
|---|---|---|
| 1 | `bash tests/test-cheap-guards.sh` | 23/23 passed |
| 2 | Section E1: `--push-only` types a push-and-stop clause | present, no draft-PR clause |
| 3 | Section E2: `--push-only --ready` together | push-only still wins |
| 4 | Section E3 (negative control): no flag at all | draft-PR clause still types, unaffected |

## NEGATIVE CONTROL

Neutered the `QUEUE_PUSH_ONLY` branch in `_goal_line()` (`if [ 1 = 0 ]; then`)
and re-ran the suite: Section E1 fails RED (the typed line falls through to
the draft-PR clause instead of the push-and-stop clause), proving the test
actually exercises the new branch rather than passing vacuously. Restored via
`git checkout -- lib/queue/queue.sh` immediately after; the full suite is
back to 23/23.

Command: `bash tests/test-cheap-guards.sh` (push-only branch neutered)
Exit: 1
Verdict: FAIL as expected (RED), restored immediately after

## Review

The change is additive to `_goal_line()`'s existing draft/ready branch (a new
`elif`-preceding branch, same function, same call site) and one new CLI flag
in `cmd_run`'s existing case statement, following the same shape as the
already-shipped `--ready`/`QUEUE_PR_READY` pair (SPEC-224). No change to the
mux/launch/poll machinery; `--push-only` only changes what gets typed into
the session.
