# SPEC-077: START amend path + stack-merge self-reconcile (2 friction fixes)

Status: SHIPPED
Date: 2026-06-11
Lane: full (classified: full, kit-machinery)
Type: bug-fix / behavioral
Board: ID-072, ID-073

## Problem

1. **ID-072**: START lines are append-only with no sanctioned correction; an
   honest lane fix (wave-1 PR B, bug -> full) reads as a MULTI-START misfire
   forever. Audit bonus: the readers already disagree , `_rows` takes the LAST
   START (plain overwrite), `trace` takes the FIRST ("first wins") , so the
   report and the trace can show different lanes for the same run today.
2. **ID-073**: stack-merge's `next_link` reconciles only the merged PR's CHILD;
   the PR itself is never checked against its base. On a chain resume (after a
   blocked link), the resumed PR sits unreconciled and the squash-merge hits
   GraphQL conflicts. Both wave-1 and wave-2 merges required manual
   `merge -X ours` recovery.

## Decision

1. **`gate-ledger.sh start --amend ...`** writes a `START-AMEND` line (same
   fields). Read contract, unified everywhere: the LAST `START-AMEND` wins;
   else the FIRST plain `START`. Surfaces patched: lane-telemetry `_rows`
   (now explicitly amend-aware instead of accidentally-last-wins), `trace`
   (header notes `amended` instead of flagging MULTI-START when the extra
   START is a sanctioned amend; plain duplicate STARTs still flag),
   `_shipped_incomplete` lane read, ship-gate `RLANE`.
2. **stack-merge `_ensure_reconciled <branch> <base>`**: at the top of every
   link, if `origin/<base>` is not an ancestor of `origin/<branch>`, run the
   `-X ours` reconcile dance on the PR's own branch BEFORE merging , keyed to
   branch STATE, not to the retarget having just happened. After any reconcile,
   assert ancestry (`merge-base --is-ancestor`) and a pushed remote tip, or
   abort loudly; the silent no-commit failure class dies.

## Acceptance criteria

- AC1: `start --amend` writes START-AMEND; trace shows the amended lane with an
  `amended` note and NO MULTI-START flag; report `_rows` lane = amended lane.
- AC2: plain duplicate STARTs still flag MULTI-START (regression pin).
- AC3: a fixture repo where the PR branch is BEHIND its base: `_ensure_reconciled`
  merges, asserts ancestry, pushes; an already-reconciled branch is a no-op.
- AC4: reconcile failure (ancestry still false after merge) aborts non-zero with
  a named error, never silently continues.
- AC5: suites green; NC per fix.

## Test plan

Failing-first: amend fixtures (trace + report reads) RED pre-verb; ensure-
reconciled unit fixtures (local bare-remote pair, no gh needed) RED pre-helper.
NC: disable the amend branch -> amend pins RED; disable the ensure call ->
behind-base fixture RED.

## Verification

- Failing-first: 7 RED on the pre-fix tree -> implementation -> green; review
  added the AMEND-first ordering fixture (RED on the unfixed _rows) -> 398/398.
- Suites: hooks 398/398, meta 444/444, e2e 20/20.
- NC: amend branch disabled -> 3 RED; ensure-reconciled arm disabled -> 4 RED;
  both restored green.
- Live dogfood: wave-1's gate-ledger-fixes ledger amended post-merge (the
  original MULTI-START misfire this row was filed about), trace now reads
  amended/full with no misfire flag.

## Review

Date: 2026-06-11. Multi-lens (correctness 5/10, contract-consistency 6/10).
Fixed in-branch:

- Correctness HIGH: _rows violated the contract for AMEND-first ordering (a
  later plain START reopened the first-wins window) -> amend now closes the
  window; fixture added. MEDIUM: ensure_reconciled ff-syncs the local copy
  before merging (stale-local push rejection left an orphaned merge commit);
  restores the operator's original branch (the no-child last link stranded
  them on a remote-deleted branch). LOW: usage string says start --amend.
- Consistency HIGH: the operator had no written escape hatch -> assign.md now
  documents --amend at the START block. MEDIUM: the combined MULTI-START +
  amended header no longer claims first-wins and last-wins simultaneously;
  stack-merge file header updated to the 4-step flow.

Post-fix: hooks 398/398, meta 444/444, e2e 20/20. Verdict: SHIP.
