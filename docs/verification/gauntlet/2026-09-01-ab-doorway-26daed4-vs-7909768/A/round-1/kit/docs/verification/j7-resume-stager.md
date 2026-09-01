# Proof of done: J7 resume-row stager (ID-498)

Date: 2026-09-01. Branch: fix/j7-resume-stager.

## Recorded run

- Command: a live J7 gauntlet round on the baked image (omp/NW probe), then `check-submission-user-J7.sh`
- Exit: rc=0; `J7-DONE rc=0 checker=GREEN marker=present`
- Checker output: 7/7 PASS
  - `PASS a spec file exists`
  - `PASS RESUME-MARKER is present in /work`
  - `PASS no duplicate-subject commits`
  - `PASS --repeat works (N=3)`
  - `PASS the repo's test command passes`
  - `PASS a non-default branch exists`
  - `PASS PR.md exists with title + body`
- Verdict: PASS
- Also: `bash tests/gauntlet/tier1.sh` GREEN; `shellcheck -S warning run.sh` clean.

## Negative control (measured red arm)

The pre-fix stager wrote no `/work/RESUME-MARKER` and staged no prior-session state, so the J7 round of the 2026-09-01 campaign came back RED on the single `RESUME-MARKER is present` check while every substantive check (spec, --repeat, npm test, branch, PR) already passed (`docs/verification/gauntlet/2026-09-01-onboarding-campaign/`). That RED is the red arm. Post-fix the same card + runner produce marker=present and 7/7 GREEN. Revert the two run.sh hunks (the J7 plant + the marker write) and the marker check RED's again.

## What the stager now stages (making the marker meaningful)

A killed-prior-session state on `/work/fixture-repo`: `docs/specs/SPEC-001-repeat.md` with TASK-001 checked and TASK-002..004 unchecked, `.claude/session-state/last-state.md` breadcrumb, the prior work committed on `feat/repeat` (the room is left checked out there), and `/work/RESUME-MARKER` written by the harness (never the probe, per card J7's rule). The resumed probe continued from the unchecked tasks, so `no duplicate-subject commits` has real teeth.

## Rollback

Two additive run.sh hunks; `git revert`-able; no state.
