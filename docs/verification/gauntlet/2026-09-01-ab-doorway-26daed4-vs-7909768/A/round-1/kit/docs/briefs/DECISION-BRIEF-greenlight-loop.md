# Decision Brief: greenlight loop (autonomous PR-to-merge-ready)

Date: 2026-07-25 · Source: az-skills absorption (greenlight-pr mechanism, re-implemented, source
repo has NO license so no file is ever copied). Status: DRAFT (feeds ID-401's spec). Consuming
row: ID-401. Record: `docs/research/2026-07-25-skills-repos-onboarding-absorption.md` §2.

## Verified current state

/kit:ship ends at "PR opened". Nothing drives an OPEN PR through CI failures, bot review
comments, and re-review to merge-ready; that middle is human babysitting today, which is exactly
the attention N5 says the operator should not spend.

## The design

A bounded loop over an open PR, one tick = read state, act once, snapshot:

- **Snapshot state machine**: a single JSON snapshot per tick is the sole state source (repo+PR
  keyed, survives interruption/crash; resume = re-read snapshot + live PR state, idempotent).
- **CI failures**: fix-forward with a **per-SHA retry budget** (default 3); a force-push resets
  the budget correctly (budget keys on SHA, not run).
- **Bot/review comments**: triage each to FIX (apply), DISAGREE (reply with reasoning, never
  silently ignore), DEFER (file a board row, reply with the pointer). Reply style per the
  existing responding-to-review contract (no pleasantries).
- **Named terminal states**, no others: `done` (merge-ready), `stop_pr_closed`,
  `stop_exhausted_retries`, `stop_waiting_review_pending` (a human reviewer is the blocker;
  waiting is a terminal, not a spin). Terminal states land in the gate ledger (existing readers).
- Composes with ID-398's close/escalate/continue vocabulary (a triage verdict that needs an
  architecture/risk call = escalate to the human, per AGENTS.md zone 4).

## Boundaries

Never merges (merge-READY is the exit; the human or the existing auto-merge path owns the merge
click). Never bypasses the ship-gate. Never force-pushes. Bounded ticks (cap), no daemon; runs
in-session or as a queue goal.

## North-star conformance (§6)

N5 verbatim (the hands-off middle extended past PR-open); N6 (terminal states + retries emit to
the ledger). Propose-never-dispose holds: DISAGREE replies argue, they do not dismiss; DEFER
files rows for a human.

## Exit criteria

1. A PR with a planted failing test reaches `done` within budget with the fix committed, or
   `stop_exhausted_retries` with the ledger trail (negative control: a nonsense failure must NOT
   reach `done`).
2. A planted bot comment of each triage class produces the right action (FIX commit / DISAGREE
   reply / DEFER row+reply).
3. Kill the loop mid-tick; restart resumes from the snapshot without repeating a completed action.
