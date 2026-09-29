# Implementation notes -- land-regate-after-wait

Deltas from SPEC-365. Nothing here repeats what the spec already states.

## 2026-09-29 Spec-time decisions
- The post-wait block moves into `_ci_regate` with two callers, not three. The kit's three-use rule yields here, because the block is an enforcement rule: a second hand copy in `cmd_land` would drift from `cmd_merge`. The extraction lands first (Task A) with no behavior change, so the existing merge ci-wait cases pin it before `land` calls it.
- The carry handoff carries the snapshot and spends the grace. It does not carry `CI_WAIT_END`. The inner wait still makes one fresh read, so a check that registered between the carry's last read and the inner merge counts.
- The handoff binds to the head. Without the bind, a head that moved and was re-labeled would inherit grace 0 on an empty rollup and merge on `CLEAN` untested. No stub case can drive a push between the carry's head check and the inner eligibility read, so NC4 (bind removed) cannot go red. It is not run, and review carries the bind.
- `land` settles its re-gate read with the plain form `_pr_detail_settled url n`. The pushed-oid form needs the prior head, and `land` never reads an adopted PR's old head. A stale-head read therefore fails closed as "head moved". Named in the spec's Failure modes.
- The existing land ci cases (ci-gated, T6, ci-armed, ci-stale) need full-detail fixtures on the read after the wait. This changes fixtures, not assertions, apart from T6's read index moving from 4 to 5. The re-gate read is the added fifth.

## 2026-09-29 Process
- This worker ran the spec steps the lead named (reserve, write, Spec ran, Spec end, commit) and stopped at `VALIDATE PENDING`. The full-lane design-time pass in `commands/spec.md` step 4 (`/kit:devs-team` plus `kit:advisor` over-suggest) did not run here. The lead owns that call before validation.
