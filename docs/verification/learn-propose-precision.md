# Validation: `learn propose` staging precision (ID-294)

**What this is.** A precision measurement of `learn propose`'s `## [staged]` output,
using the 2026-07-18 manual triage of the staging file as ground truth. Read-only
analysis; no code change.

## Ground truth

Of 69 staged candidates, the manual triage dispositioned them as:

| Disposition | Count | Meaning |
|---|---|---|
| Promote (true positive) | 16 | a genuinely new, promotable board row |
| Duplicate | 28 | already tracked on some board / megagoal TODO when staged |
| Already done | 19 | the work was complete by triage time |
| Stale | 4 | premise no longer holds, or wrong target |
| Learning | 2 | correctly routed to a non-board sink (debt paydown / notes) |

Raw promote-precision = 16/69 = **23%**.

## The FP split that matters: extractor-fault vs decay

A single 23% number hides two very different failure modes. Separating them is the
whole point, because they call for different fixes.

**Extractor-fault FPs (the candidate was already-tracked or mis-homed AT staging time
, a precision failure the extractor could have avoided):**

- **All 28 duplicates.** The dedup evidence in the triage is decisive: the duplicate
  cluster is dominated by rows already tracked ELSEWHERE , ~20 against one megagoal's
  `TODO.md` (CL-001 / nft-migration), the ICY items folding into a parked gate, the EKS
  items mapping 1:1 to an executing megagoal's sub-goals, an existing follow-up note.
  `learn propose`'s dedup is anchored to the kit's OWN board + staging file; it does not
  see the cross-repo cockpit boards or the megagoal ROADMAP/TODO files, so work tracked
  in those surfaces re-enters staging as "new."
- **At least one mis-homed stale (#35):** it targeted a `dotfiles` rustfmt hook that does
  not exist; the real hook is in dwarves-kit. Wrong home = an extractor fault a
  file-location check would catch.

That is ~29/69 = **~42%** of the batch: false positives the extractor produced, not the
clock.

**Decay FPs (the candidate was VALID when staged, but shipped before triage , a latency
failure, not a precision failure):**

- **Most of the 19 already-done.** The candidates were staged around 2026-07-02 and
  triaged 2026-07-18 , a ~16-day gap. The triage evidence shows items that closed IN that
  window (e.g. "all 6 pending PRs merged"). These were real, promotable candidates when
  staged; the extractor was right, the triage was just late.

**Learning (2):** #45/#46 route to a non-board sink and are correctly-classified, not
false positives in the board sense (though #46 also duplicates an existing row).

## Reading

- The precision loss is **not hallucination.** `learn propose`'s cite-the-number and
  refute disciplines held , no candidate was flagged for a fabricated figure. The FPs are
  duplicates-of-real-work and stale-by-latency, not invented work.
- The dominant, fixable fault is **dedup scope.** 28/69 = 41% of staged candidates
  duplicated rows tracked on a surface the deduper never reads (cross-repo cockpit boards,
  megagoal TODO/ROADMAP). Closing that anchor gap alone would roughly double
  promote-precision (23% -> ~40%+), because it removes the single largest FP class.
- The second fault is **triage latency, not extractor precision.** The 19 already-done
  were largely valid-at-staging; they are lost to a 16-day drain window, not to a bad
  proposal. This is reclaimed by tighter aging or a verify-still-open check at promote,
  not by changing what the extractor proposes.

## Verdict

`learn propose` is **not precise enough as-is** at 23% raw promote-precision, but the
data does **not** support distrusting the interpreter/grounding path. It supports two
targeted changes, in priority order:

1. **Widen the dedup anchor set** (biggest win). Extend `existing_keys()` to include the
   cross-repo cockpit boards (the `boards.txt` registry) and the megagoal ROADMAP/`TODO`
   files, so a candidate already tracked in any of those never re-stages. Data: 41% of
   the batch was this class.
2. **Add an aging / verify-at-promote check** to reclaim decay FPs. Either shorten the
   drain expiry window or, at `board promote`, re-check the candidate is still open. Data:
   ~27% of the batch was valid-when-staged but done-by-triage.
3. **Home-resolution check** (small): validate a candidate's target repo against where the
   cited file actually lives, catching mis-homed proposals like #35.

With (1) alone the precision story flips from "1 in 4 is real" to "~2 in 5 is real"; with
(2) the residual is mostly latency, which is an operator-cadence knob, not an extractor
defect. No change to the interpret/refute stages is indicated by this data.
