# Implementation notes -- land-regate-after-wait

Deltas from SPEC-365. Nothing here repeats what the spec already states.

## Build notes: part 1

### Task A
- `_ci_regate` sits between `_ci_checks_wait` and `_autoland_carry`, keeping the ci-gate cluster together. Call sites resolve it at call time, so placement carries no constraint.
- The three CLEAN-clause texts are one `if/elif/else` on `CI_WAIT_END` then `CI_NEW_SCOPE`, not a `case`: the unscoped `NONEW` text and the scoped `NONEW` text share the `NONEW` prefix check, and the nesting keeps each text on its own line for the negative-control `sed` passes.
- The verdict's rc is decided inside the `verdict != OK` block, so the reason prints once regardless of the return code.
- `reason`/`rrc` are new `cmd_merge` locals beside `rc`; the old `new_head`, `verdict` and `ms` uses in that block are gone and the earlier `local verdict` declaration still serves the eligibility loop.
- T16's fixtured `not json` wait reads double as the unreadable-last-read shape the spec names; the re-gate read at fixture index 5 is what the CLEAN clause then sees.

### Task B1
- The probe's three-way read is ordered: exit code first, then the empty-or-whitespace test on the captured stdout (gh's real no-match answer), then `jq -e 'type == "array"'`, then the exact-`ci` match. Capturing stdout before any jq run is what lets a non-zero exit refuse while an empty answer still passes.
- The head wait loops on "not an object OR wrong head" and resolves the two end states after the loop: a non-object last read takes the existing `could not read the labels and checks` refusal, a wrong head takes the rc 3 line. With no pin the loop body reads once and breaks, so `cmd_merge` and the carry keep their single read.
- `moved` is parsed and stored but read nowhere yet; the label-on arm learns the dating rules in a later task.
- `cmd_land` runs `git ls-remote` before its push on every repo, gated or not: it sits outside the label check, so the ungated path pays one remote read for the `moved` answer.
- T15, L10 and L7 went red on the old code; T17, T17b and L11 are guards that pass on both sides of the change (the empty-output path and the `[]` path both mean "no gate" before and after).

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

## 2026-09-29 Round 2 fold (NEEDS REVISION, 7/7 parallel)
- The C6 question in the round-1 entry is closed: the lead accepted the double hold per carry with no flag (DEC-D). T13 now serves the `ci` event and counts 26 reads; T13d pins four holds.
- Two reviewer conflicts resolved fail-closed. A failed events read refuses instead of snapshotting every key (DEC-F). The `completedAt` start fallback is cut, because with no-start entries in the snapshot it could only turn an entry NEW (DEC-I).
- Calls this worker made beyond the lead's list: the `actions/` URL rule applies to the DATED cut only, which keeps SPEC-360's T12 (DEC-J); the carry gets a catch-all `case` arm rather than a pinned oid (DEC-K); the non-CLEAN message keeps its text under the wider clause (DEC-L); "test the settle defaults" is read as the head wait at a non-zero `KIT_WRAP_SETTLE_SECS` (DEC-O); NC11 mutates the empty-`T` arm to return `[]`, because dropping it lets the head-age arm re-add anyway.
- The widest behavior change is C7: a failed `gh label list` now refuses `land`, `merge` and the carry on every repo, including repos with no `ci` label. That follows the lead's fail-closed rule for R1(b).
- T13b and T13c keep round 1's count of 6, which assumes carry 2 makes no read of #42 once carry 1 is skipped. The build confirms or corrects it.

## 2026-09-29 Round 4 fold (APPROVED, 0 criticals, 7/7; Status VALIDATED)
- Kept to wording, test additions and rule clarifications, per the lead. No settle was added for the late `synchronize` workflow; it stays a named residual (DEC-AE).
- One text change reaches behavior: the `NONEW` refusal now has a scoped variant, `no Actions run of this repo reported after the ci label went on`, picked from `CI_NEW_SCOPE` (DEC-AF). T3b, L4 and T13b take the absent-label path, so their asserts keep today's text; E1, L6, E4 and T13c take the scoped one. NC19's red list grew by those three text asserts (L6, E4, T13c), which the round-3 trace missed once the text split.
- T20 is the new two-carry case for the entry clear. Its count (24, and 26 under NC26) depends on carry 1 taking the DATED path, so it sits in D2, not in D0 beside the code it pins.
- D0 puts the slug check and the scope at the top of the label-on branch. So today's `[]` fallthrough runs scoped from D0 on, and every existing label-on case (ci-stale, ci-armed, autoland ci-gated, T4, the T13 family) moves to Actions-shaped fixtures in D0 to keep its asserts. T4 keeps its 4-read asserts until D1 rewrites them.
- Skipped: the optional StatusContext case on the DATED path (R2 to R5). E1's `forged` entry already is that case, pinned by NC20.
- Verified live, read-only: a Prow StatusContext has no `detailsUrl` and no `workflowName` key; `gh api --hostname github.com` wins over an exported `GH_HOST`; `workflowName` first shipped in gh v2.14.0; the activity API dates pushes.

## 2026-09-30 Round 4 post-fold check
- Applied five lead decisions, wording only. D0 now puts `CA_OLD` on every T13, T13b and T13e fixture read (read 1 included), with `url` from read 2, and says to fix the fixture, never the count.
- `commands/wrap.md` anchors moved after a rebase: the `land` paragraph is line 118 (was 104) and the step-4 sentence is line 337 (was 323). Task E also names the pinned step-10 assert at tests/test-wrap.sh:4794. All three verified by grep.
- NC19 now names its target: the slug-derived `CI_NEW_SCOPE=` set at the top of the label-on branch, not the entry clear (NC26).
- C12, the gh older than v2.14.0 row and the Out-of-scope autoland bullet no longer claim a grace hold then the CLEAN rule or fail-closed. They match Boundaries and DEC-AF: a snapshot of `[]` skips the CLEAN clause and `_pr_gate` decides.
- T20's `GH_STUB_PR_42_15` is stated as the same record as the carry-2 read, `headRefOid: %CARRY_TIP%` included.
- DEC-AD and DEC-AI still carry the older "grace hold, then the CLEAN rule" phrasing as decision history; left unchanged per the lead's scope.

## 2026-09-29 Process
- This worker ran the spec steps the lead named (write, Spec ran, Spec end, commit) and stopped at `VALIDATE PENDING`. The full-lane design-time pass (`/kit:devs-team` plus `kit:advisor` over-suggest) did not run here. That call belongs to the lead.
