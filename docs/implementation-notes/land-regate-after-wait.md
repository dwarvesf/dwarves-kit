# Implementation notes -- land-regate-after-wait

Deltas from SPEC-365. Nothing here repeats what the spec already states.

## 2026-09-29 Spec-time decisions
- The post-wait block moves into `_ci_regate`. It started with two callers and gained the carry as a third in round 1. The block is an enforcement rule, so the extraction lands first (Task A) with no behavior change, and the existing merge ci-wait cases pin it before anything else calls it.
- `land` settles its re-gate read with the plain form `_pr_detail_settled url n`. The pushed-oid form needs the prior head, and `land` never reads an adopted PR's old head. The head wait in the sync covers the stale-head window instead (see below).
- The existing land ci cases (ci-gated, T6, ci-armed, ci-stale, ci-noset) need `headRefOid` on the sync read and full detail on the re-gate read. This changes fixtures, not assertions, except that T6's merge index moves from 4 to 5 and ci-gated's "waited out" floor rises to 4.

## 2026-09-29 Round 1 fold (NEEDS REVISION, 7/7 parallel)
- The env handoff (`CI_CARRY_OID`, `CI_CARRY_KEYS`, grace 0, load-time reset) is dropped for the carry's own `_ci_regate` call, per the lead. That removes Reviewer 1's critical and the head bind that no stub case could test. The carry refusal follows the `SKIP land` convention (return 1, no `FAILURES`, `apply` exit 0).
- The sync dates a label that is already on from the issue events API. Both times come from GitHub's clock, so SPEC-360's reason for rejecting a time cut (local skew) does not apply.
- Deviation from the lead's wording: the head wait before the sync lives inside `_ci_label_sync`, behind an optional pinned oid, not as a separate read in `cmd_land` ahead of the call. A separate read would run on every repo. There it would add a refusal to `land` on repos without the label (the stub's default `{}` fixture has no head, so dozens of land cases would refuse), and it would shift every label-gated land fixture index by one. Inside the sync it runs only after the label probe says the repo gates. It reuses the sync's own PR read, so on the happy path it costs no extra read, and the snapshot is still taken on the pushed head. The distinct return 3 keeps its message apart from "the ci label could not be set".
- Round 1 surfaced a cost the spec now names as C6. With the sync dating the label, autoland on the `NONEW` path with a `CLEAN` state holds the grace window twice: once in the carry's wait and once in the inner merge's. T13 serves no events, so its count cannot see the second hold. The lead should decide whether that cost is acceptable, or whether the inner merge should skip its hold when the carry has just re-gated the same head.
- E3 serves events and then exits 1, the way a failed later page of `--paginate` does. That pins the sync to honor gh's exit code, not just parse whatever printed (NC7).

## 2026-09-29 Process
- This worker ran the spec steps the lead named (write, Spec ran, Spec end, commit) and stopped at `VALIDATE PENDING`. The full-lane design-time pass (`/kit:devs-team` plus `kit:advisor` over-suggest) did not run here. That call belongs to the lead.
