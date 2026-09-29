# Spec: wrap waits for the runs a fresh ci label starts

Generated: 2026-09-29
Status: VALIDATED (round 4 APPROVED: 0 critical, 8 warnings, folded below; a review-team fix batch, security 7/10, architecture 8/10, test-coverage 8/10, 0 critical, is folded under `## Change` and marked "review fix"). Prior: round 3 (NEEDS REVISION, 2 critical, 8 warnings, with live gh evidence), round 2 (NEEDS REVISION, 1 critical, 9 warnings), round 1 (NEEDS REVISION, 2 critical, 8 warnings).
Lane: full (lib/ enforcement surface: the merge gate of `wrap merge --apply`, `wrap land` and the carry autoland)
Type: bug
File: `docs/specs/SPEC-360-wrap-ci-label-wait.md`
References: `lib/wrap/wrap.sh` (`_ci_label_sync`, `_ci_checks_wait`, `_pr_gate`, and the three callers in `_autoland_carry`, `cmd_merge`, `cmd_land`); `tests/test-wrap.sh` (the "ci label gate" sections for merge and land); `docs/implementation-notes/wrap-ci-label-wait.md` (deltas)

## Problem

Some repos run PR workflows only on `pull_request: types: [labeled]` with the label `ci`. `wrap` handles them in two steps. `_ci_label_sync` adds the label, and `_ci_checks_wait` waits for the runs the label starts. The wait grants its grace window (`KIT_WRAP_CI_GRACE_SECS`) only while the PR's `statusCheckRollup` is EMPTY.

A PR can carry completed check entries on its head before `ci` goes on. On dwarvesf/foundation-workers #971 they came from run 36370943441, a plain `pull_request` run from before foundation-workers #976 made `ci.yml` label-only. From now on such entries come from `labeled` events for other labels: the workflow fires, its jobs skip, and every entry reads SKIPPED. Either way, right after `ci` goes on the rollup holds only those old completed entries. None is pending. The runs `ci` starts register a few seconds later. The wait reads "0 pending" on its first read, ends at once, and the merge proceeds on an untested head.

Seen live on #971 (and #970). One `labeled` event fired at 10:21:52Z, and `wrap` printed `merged #971` 6 seconds later. A later `gh pr view 971 --json statusCheckRollup` showed the new `test` entry beside the old `test=SKIPPED`. Both late runs passed, so nothing broke. The gate still did not gate.

The real rollup of #971 shows the shape the fix keys on. Every CheckRun carries a `detailsUrl` that names its job, and that URL differs between the pre-label entry and the label-started one:

```
test     SKIPPED  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979093   (before the label)
test     SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362252589   (label-started)
preview  SUCCESS  2026-09-28T02:44  .../actions/runs/36370943441/job/108766979586   (before the label)
preview  SUCCESS  2026-09-29T10:21  .../actions/runs/36555102629/job/109362256467   (label-started)
```

A second gap sits in the re-gate after the wait. `_pr_gate` groups the rollup by check name and keeps the entry that sorts last on `completedAt // startedAt // createdAt // ""`. jq's `//` falls through only on null or false. gh 2.101, run against four public PRs with pending checks, reports every QUEUED and IN_PROGRESS CheckRun with `"completedAt":"0001-01-01T00:00:00Z"` and `"conclusion":""`, and QUEUED entries also carry a real `startedAt`. So a pending run keys on the zero time, sorts before the old completed `test=SKIPPED`, and the gate reads that stale SKIPPED as the verdict for `test`. The comment above `_pr_gate` says the sort falls back to `startedAt` for a still-running check; live, it never does. Any label-started run with no real completion time when the wait ends hits this. Self-hosted runner queues make a run that stays pending past `KIT_WRAP_CARRY_CHECKS_SECS` realistic.

## Picture

```
_ci_label_sync
  reads labels + rollup (already does)
  read is not a JSON object  --->  return 2: the caller refuses, the PR stays open
  adds `ci`             --->  CI_PRELABEL_KEYS = keys of that pre-edit rollup
  re-adds `ci`          --->  CI_PRELABEL_KEYS = '[]'   (the rollup is empty on this branch)
  label already fine    --->  CI_PRELABEL_KEYS = '[]'   (today's behavior)
        |
        v
_ci_checks_wait  (one read every 10s)
  read failed                         -> wait, bound KIT_WRAP_CARRY_CHECKS_SECS
  pending > 0                         -> wait, bound KIT_WRAP_CARRY_CHECKS_SECS
  pending = 0 and NEW empty           -> wait, bound KIT_WRAP_CI_GRACE_SECS
  pending = 0 and NEW non-empty       -> done
     (NEW = entries not SKIPPED whose key is not in CI_PRELABEL_KEYS;
      pending counts the whole rollup, pre-label entries included)
  CI_WAIT_END = the last read's state (NONEW when the grace hold ran out)
        |
        v
re-gate (cmd_merge only): _pr_gate on the same head
  draft / base / mergeable clauses first, unchanged
  latest-per-name pick: every pending entry sorts LAST; the rest key on the first REAL time
  -> a pending latest trips "SKIP checks are pending or failing"
  then: CI_WAIT_END = NONEW and CI_PRELABEL_KEYS non-empty -> OK needs mergeStateStatus CLEAN
```

## Change

1. `_ci_label_sync` sets the out-param `CI_PRELABEL_KEYS='[]'` on entry. When the repo gates on `ci` and its PR read is not a JSON object, it returns 2, so every caller refuses and the PR stays open (review fix: an unreadable read used to leave the snapshot empty and reopen the #971 race). When it adds the label, it first sets `CI_PRELABEL_KEYS` to a compact JSON array of the entry keys in the `statusCheckRollup` it already read. The remove-and-re-add branch sets nothing more: it runs only when the rollup is empty. No new `gh` call is made. The value is always valid JSON: an empty jq output falls back to `'[]'`.
2. One shell variable, `CI_JQ_DEFS`, holds the jq definitions the ci wait, the carry wait and `_pr_gate` share (review fix: one definition instead of a key variable plus two inline pending predicates):

   ```
   def real: select(. != null and . != "" and . != "0001-01-01T00:00:00Z");
   def pending: ((.status // "COMPLETED") != "COMPLETED") or ((.state // "") == "PENDING") or ((.state // "") == "EXPECTED");
   def ckey: (.name // .context // "") + "@" + ([.detailsUrl, .targetUrl, .startedAt, .createdAt] | map(real) | .[0] // "");
   ```

   A CheckRun's `detailsUrl` names one job, and the run keeps it from queued to completed. The name prefix keeps apart third-party checks that share one `detailsUrl` (Netlify posts several checks with the same URL). A StatusContext exposes `targetUrl` and `startedAt`, not `detailsUrl`. gh emits an absent URL as `""` and an absent time as the zero time, never null, so `real` drops all three; a plain `//` chain would stop at the `""`. The time fields come last because they move when a check changes state.

   `CI_PRELABEL_KEYS` enters jq only as `--argjson prelabel "$CI_PRELABEL_KEYS"`, never spliced into the program text. The add-branch assignment stays on one line, so the negative-control `sed` can replace it whole.
3. `_ci_checks_wait` computes, per read, the pending count over the whole rollup and NEW, the entries whose conclusion (or state) is not SKIPPED and whose key is not in `CI_PRELABEL_KEYS` (review fix: another label's `labeled` event adds SKIPPED runs that test nothing, and they no longer end the hold). Precedence, in order: a failed read waits on the carry bound; pending > 0 waits on the carry bound; pending = 0 with NEW empty waits on the grace bound; pending = 0 with NEW non-empty ends the wait. It leaves the last read's state in the out-param `CI_WAIT_END`.
4. `_pr_gate` changes only its latest-per-name sort key: `sort_by([(if pending then 1 else 0 end), rtime]) | last`, with `rtime` the first `real` time among `completedAt`, `startedAt`, `createdAt`. Every pending entry sorts after every completed entry of its name (review fix: keyed on time, a SKIPPED run from a later `labeled` event, completed at 10:22:05, beat an IN_PROGRESS `ci` run started at 10:21:55, and the gate returned OK on an untested head). A completed entry's key is its `completedAt`, as today. The comment above `_pr_gate` drops the false "falling back to startedAt for a still-running check" and names StatusContext's fields as `.context`, `.startedAt`, `.targetUrl`, `.state`. No clause is added or moved: the draft, base, mergeable and CONFLICTING verdicts come first exactly as today.
5. `cmd_merge`, after its re-gate returns OK: when `CI_WAIT_END` is `NONEW` and `CI_PRELABEL_KEYS` is not `[]`, the verdict rests on checks that predate the label, so it also needs `mergeStateStatus == CLEAN` (review fix), the rule an empty rollup already meets. Otherwise it refuses with `FAILED merge #<n>: no check reported after the ci label went on, and merge state <S> is not CLEAN; left open`.
6. Nothing else changes. The three callers keep their calls and signatures. `_autoland_carry` still lands through `cmd_merge --apply --pr`, which re-gates. The grace and carry bounds keep their names and defaults.

## Design

The flow is drawn once, under `## Picture`.

### Interfaces

| Surface | Before | After |
|---|---|---|
| `_ci_label_sync <url> <pr>` | returns 0/1/2 | same returns (2 also on an unreadable PR read); sets out-param `CI_PRELABEL_KEYS` (JSON array of strings, `[]` unless it added the label) |
| `CI_JQ_DEFS` | none | new shell variable: jq `def real`, `def pending`, `def ckey`, shared by the ci wait, the carry wait and `_pr_gate` |
| `_ci_checks_wait <url> <pr>` | reads nothing global | reads `CI_PRELABEL_KEYS` (default `[]`); sets out-param `CI_WAIT_END` |
| `_pr_gate <detail> <def>` | verdict strings | same strings; only the latest-per-name tie-break changes |
| `cmd_merge` refusals | existing lines | adds the non-CLEAN refusal after a NONEW hold |
| env knobs | `KIT_WRAP_CI_GRACE_SECS`, `KIT_WRAP_CARRY_CHECKS_SECS` | unchanged names and defaults |
| output lines | `labeled #N ci`, `re-labeled #N ci`, refusals | unchanged |

### Approaches considered

1. Diff the rollup against the pre-label snapshot (chosen). It needs no clock and no extra `gh` call, because the sync already holds the pre-label rollup. It keys on the job URL, which a run keeps from queued to completed.
2. Record the local time when the label goes on, and count an entry as new when its `startedAt` is at or after that time. Rejected. Local and GitHub clocks can skew by seconds, which is the whole width of the race. Approach 1 costs the same code.
3. Sleep a fixed interval after the label edit. Rejected: it guesses the registration delay and still races on a slow day.

For the re-gate:

1. Sort every pending entry last in the latest-per-name pick, and key the rest on the first real time (chosen, widened by review from "pending with no real time"). It fixes the stale-SKIPPED read in both directions, an older SKIPPED and a later one, and changes a verdict only where a group holds a pending entry.
2. Refuse on any pending entry before grouping (rejected). It is broader: a stale pending entry superseded by a newer completed one of the same name would refuse a PR that is fine today, on repos with no `ci` label too. It also needs a new clause placed after the draft, base and mergeable clauses to keep the CONFLICTING verdict intact, which is one more thing to get wrong.

### Residual race

- Two workflows on one event. When one label event starts two workflows, the wait can end once the first workflow's runs appear and finish, before the second registers. In the observed repos one workflow holds every job, and GitHub registers a run's jobs together. Today's EMPTY test has the same race.
- The read-to-edit window. A non-SKIPPED entry that registers between the sync's rollup read and the label edit is missing from the baseline, so it counts as NEW (a SKIPPED one from another label's event does not). If it completes before the `ci` runs register, the wait ends early. The window is one `gh pr edit` call wide.
- `needs:` chains. A job that `needs:` another registers its check run only after its dependency finishes. When the dependency completes green, the wait sees NEW non-empty and 0 pending, and ends before the dependent job registers. foundation-workers `ci.yml` avoids `needs:`, so its jobs register together.
- StatusContext keys shift. A commit status whose `targetUrl` is empty keys on `context@startedAt`, and a status moving from pending to success reports a new `startedAt`. A status that settles inside the registration window therefore counts as NEW, and the wait can end on it before the `ci` runs register. A status whose `targetUrl` changes on update shifts the same way.
- A delayed webhook looks like a paths-filtered workflow. When the `labeled` event reaches Actions after the grace window, the wait sees no new entry and ends. The re-gate then reads the pre-label rollup; in `cmd_merge` it passes only on `CLEAN` (Change 5). `KIT_WRAP_CI_GRACE_SECS` is the lever: raise it on a repo whose webhooks run slow.

## Failure modes

| Failure | Caller | Behavior |
|---|---|---|
| The sync's `gh pr view` read fails on a gating repo | all three | the sync returns 2; `cmd_merge` and `cmd_land` refuse, autoland leaves the PR open |
| A wait read fails | all three | counts as pending; carry bound, as today |
| No new entry ever appears (paths-filtered workflow) | `cmd_merge` | grace bound expires; the re-gate reads the pre-label rollup and passes only on `CLEAN` |
| No new entry ever appears | autoland | the carry's wait holds once; `cmd_merge --pr` then finds the label on, records no snapshot, and gates as usual (the CLEAN rule does not carry across) |
| No new entry ever appears | `cmd_land` | grace bound expires; land merges with no gate, as today |
| A new run stays queued past the carry bound | `cmd_merge`, autoland | the re-gate picks it as latest for its name and refuses |
| A new run stays queued past the carry bound | `cmd_land` | land merges with no gate (out of scope) |
| A new run completes red | `cmd_merge`, autoland | the re-gate picks it as latest (later `completedAt`) and refuses |
| A new run completes red | `cmd_land` | land merges with no gate (out of scope) |
| The label was already present, rollup non-empty | all three | no baseline; one wait read, as today |
| A stuck pending entry (an orphaned job on a runner that is gone), with or without a real time | every `_pr_gate` read, eligibility included, on repos with or without the `ci` label | the entry sorts last for its name, so that PR reads `SKIP checks are pending or failing` until the job completes or is cancelled, even after a newer run of that name completes. This is fail-closed and deliberate (review fix 1 accepted the cost for entries with a real start too). Today the same PR could pass on an older completed entry of that name. |
| A new check that only SKIPPED (another label's event) | all three | not NEW; the hold goes on |

## Acceptance criteria

- AC1: On a label-gated repo, `wrap merge --apply` on a PR whose rollup holds only completed pre-label entries does not merge while no new entry has appeared. It waits until a label-started entry appears and completes, then re-gates and merges on green.
- AC2: In the AC1 setup, a label-started run that completes red refuses the merge with `FAILED merge #<n>: checks are pending or failing once the ci label's checks ran`. No `pr merge` call is made. The rollup at the re-gate holds both the old `test=SKIPPED` and the new `test=FAILURE`.
- AC3: When no new entry ever appears (a paths-filtered workflow that starts nothing), the wait ends after `KIT_WRAP_CI_GRACE_SECS` and `cmd_merge` proceeds on the pre-label rollup only when the merge state is `CLEAN`, the same rule an empty rollup meets today. On any other state it refuses. (`cmd_land` has no gate; autoland's merge runs its own wait with the label already on, so the rule does not carry across.)
- AC4: When the label was already present with a non-empty rollup (no add, no re-add), the wait makes exactly one rollup read when nothing is pending, as today.
- AC5: When a label-started run is still queued at `KIT_WRAP_CARRY_CHECKS_SECS` with no real completion time (live shape: zero `completedAt`, empty `conclusion`, real `startedAt`), next to an old completed `test=SKIPPED`, on a `CLEAN` merge state, the re-gate refuses the merge and no `pr merge` call is made. The same holds when the queued entry has no real time at all.
- AC6: `wrap land` on a label-gated repo with pre-label entries also waits for a new entry before its `pr merge` call.
- AC7: A `CONFLICTING` PR whose rollup holds a pending entry with no real completion time still verdicts `SKIP not mergeable (CONFLICTING)`.
- AC8: `bash tests/test-wrap.sh` passes, including every existing ci-label case. `bash tests/test-meta.sh` passes.
- AC9: Negative controls with `lib/gate/negctl.sh`, each checked by the failing `chk` names in its output, not only the exit code: forcing the snapshot to `[]` turns T1, T2, T3 and T6 red (plus the review cases it reaches); restoring the old `_pr_gate` sort key turns T5 and T8 red; reverting review fix 1 turns the later-SKIPPED unit case red.
- AC10 (review): an unreadable sync read refuses; a SKIPPED-only new check does not end the hold; a NONEW hold on a non-CLEAN state refuses in `cmd_merge`; autoland holds once, not twice.

## Test plan

New cases go in `tests/test-wrap.sh`, next to the existing "merge --apply: the ci label gate" and "land: the ci label gate" sections. They use the existing `gh` stub. Read k of `pr view <n>` serves `GH_STUB_PR_<n>_<j>` for the highest set j <= k (j >= 2), else `GH_STUB_PR_<n>`. So the last fixture a case sets repeats for every later read, and T3 and T5 rely on that. The per-number read count lands in `$GH_STUB_CALLS.view-<n>`. `$TMPD/nosleep` stubs `sleep`. Each case uses a fresh PR number.

The pre-label rollup in every case is `test` SKIPPED with `detailsUrl` `.../job/1` and `preview` SUCCESS with `.../job/2`, both completed with real times. Label-started entries use `.../job/3` onward. Every pending fixture is live-shaped: `"completedAt":"0001-01-01T00:00:00Z","conclusion":""`, plus a real `startedAt` later than the old entries unless the row says otherwise. "Full detail" means the whole PR record the gate reads (`headRefOid`, `baseRefName`, `mergeable: MERGEABLE`, `mergeStateStatus`, `reviewDecision`, labels, rollup).

| Case | Setup (reads served) | Assert |
|---|---|---|
| T1 AC1 | 1 eligibility: full detail, old rollup, CLEAN. 2 sync: labels `[]`, old rollup. 3 wait: old rollup only. 4 wait: full detail (MERGEABLE, CLEAN), old plus `test` IN_PROGRESS job/3 with a `startedAt` later than the old entries. 5 wait: full detail (MERGEABLE, CLEAN), old plus `test` SUCCESS job/3. 6 re-gate: full detail, old plus new green, CLEAN | exit 0; `labeled #N ci`; `view-N` count is 6; merged, tree verified |
| T2 AC2 | as T1 reads 1-3; 4 wait: full detail, CLEAN, old rollup only; 5 wait: full detail, old plus `test` IN_PROGRESS job/3; 6 wait: full detail, old plus `test` FAILURE job/3 (`completedAt` later than the old SKIPPED); 7 re-gate: full detail, old plus new red, UNSTABLE | exit 2; the refusal line; no `pr merge N`; `view-N` count is 7 |
| T3 AC3 | as T1 reads 1-2, then read 3 onward the full detail with the old rollup only, repeating; `KIT_WRAP_CI_GRACE_SECS=20` | exit 0; the wait made 3 reads (0s, 10s, 20s) before the re-gate read; merged |
| T4 AC4 | read 1 eligibility full detail; read 2 labels `[ci]` with the old rollup; read 3 onward full detail (MERGEABLE, CLEAN), old rollup, repeating | no `pr edit N`; `view-N` count is 4 (eligibility, sync, one wait read, re-gate); merged |
| T5 AC5 | as T1 reads 1-2, then read 3 onward the full detail, CLEAN, with old plus `test` QUEUED job/3 (live shape, real `startedAt`), repeating; `KIT_WRAP_CARRY_CHECKS_SECS=10` | exit 2; the refusal line; no `pr merge N` |
| T6 AC6 | `wrap land`: read 1 labels `[]` plus the old rollup; read 2 old only; read 3 old plus new IN_PROGRESS (live shape); read 4 old plus new SUCCESS | exit 0; `pr merge` comes after the 4th `pr view`; merged |
| T7 AC7 | `wrap merge` dry run (no `--apply`), the way the existing CONFLICTING cases drive the gate: one open PR, detail `mergeable: CONFLICTING`, DIRTY, rollup the old entries plus a live-shaped QUEUED `test` | output holds `SKIP #N <title>: not mergeable (CONFLICTING)` |
| T8 AC5 | as T5, but the QUEUED `test` has `completedAt` and `startedAt` both `"0001-01-01T00:00:00Z"` (no real time at all; gh emits the zero time, never null) | exit 2; the refusal line; no `pr merge N` |
| T3b AC3 | as T3 on UNSTABLE | exit 2; the non-CLEAN refusal line; no `pr merge N` |
| T9 AC10 | read 2 (the sync's) is `not json` | exit 2; `the ci label could not be set`; no `pr edit N`; no `pr merge N` |
| T10 AC10 | read 3 adds a new `lint` SKIPPED job/4; read 4 adds `test` SUCCESS job/3 | exit 0; `view-N` count is 5 (the SKIPPED check did not end the hold) |
| T11 AC10 | read 2 snapshot holds `test` IN_PROGRESS job/1; later reads show job/1 COMPLETED SUCCESS with a new `startedAt`; grace 20 | exit 0; `view-N` count is 6 (the key held across the state change) |
| T12 AC10 | pre-label `netlify/deploy-preview` on URL U; read 3 adds `netlify/header-rules` and `netlify/redirect-rules`, both on U | exit 0; `view-N` count is 4 (the name keeps them NEW) |
| T13 AC10 | autoland, carry PR with the pre-label rollup and no new checks; reads after the first carry the label; grace 20 | exit 0; tree verified; `view-42` count is 18 (one hold) |
| unit AC5 | `gate_verdict` (dry `merge`): a later SKIPPED plus an IN_PROGRESS with a real start; an older SKIPPED plus a QUEUED with a real start; a stuck running entry plus a newer SUCCESS; a stuck no-real-time entry plus a newer SUCCESS | each verdicts `checks are pending or failing` |

The harness exports `KIT_WRAP_SETTLE_SECS=0`, so `_pr_detail_settled` makes exactly one read: the re-gate reads whatever fixture comes right after the wait's last read. The fixtures are laid out for that. In T1, an early-ended wait re-gates on read 4 (full detail, pending `test`) and refuses, so the case goes red. In T2, an early-ended wait re-gates on read 4 (full detail, CLEAN, old rollup only), returns OK and merges, so the case goes red. T4 pins that an operator whose label is already in place pays no extra wait. The existing cases pin the empty-rollup path, the re-label path, the label that will not set, and the autoland door.

## Negative control

After the feature commit, one run per control, each restored before the next:

1. Snapshot ignored: a rewrite of the add-branch `CI_PRELABEL_KEYS=` assignment to `CI_PRELABEL_KEYS='[]'`. Expected red: T1 (the re-gate reads the pending read 4 and refuses), T2 (the re-gate reads the CLEAN old rollup at read 4 and merges), T3 (the wait makes one read, not three), and T6 (land's `pr merge` comes after the 2nd `pr view`, not the 4th).
2. Gate key reverted: a rewrite that restores the old sort key `sort_by(.completedAt // .startedAt // .createdAt // "")`. Expected red: T5 and T8, because the zero or missing time sorts first, the stale SKIPPED wins, and the merge runs; the pending-last unit cases go red too.
3. Review fix 1 reverted: the sort key back to `[(if (pending and rtime == "") then 1 else 0 end), rtime]`. Expected red: the later-SKIPPED unit case, and the stuck-running-entry case whose pending entry has a real start.

Both run as `bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<mutation>"`. The record quotes the failing `chk` names from each run and checks them against the expected lists above. A suite exit code alone does not pass a control. The exact `sed` patterns are settled at build time against the final lines.

## Out of scope

- `cmd_land` does not re-gate after `_ci_checks_wait`. Its `pr merge` runs whatever state the label-started runs are in when the wait ends, so a red run still lands, and so does a run still queued past the carry bound. This predates the change. Adding a gate alters what `land` promises, so it is a separate change (lead decision).
- Label present, new push, then another label. The `ci` label is already on the PR, a new commit is pushed (a label-only workflow starts nothing on `synchronize`), and some other label is then added. Its `labeled` event puts all-SKIPPED entries on the new head. The rollup is non-empty, so the sync neither re-adds `ci` nor records a snapshot. Since the review fix, SKIPPED entries are not NEW, so the wait holds for the grace window; the all-SKIPPED rollup then still passes the gate. Named here, not fixed.
- The residual races under "Residual race".

## Verification

`bash tests/test-wrap.sh` green with T1 to T13 and the unit cases present, then the negative controls above. The proof of done goes where `bash lib/gate/proof-gate.sh contract "wrap ci label wait"` names it.

## Tasks

- [x] Task A (DONE, commit 935a5321, verified): `CI_ENTRY_KEY`, the baseline in `_ci_label_sync`, and the NEW-entry precedence in `_ci_checks_wait` (`lib/wrap/wrap.sh`), plus cases T1 to T4 and T6 in `tests/test-wrap.sh`.
- [x] Task B (DONE, commit 935a5321, verified): the first-real-time sort key in `_pr_gate` and the corrected comment above it (`lib/wrap/wrap.sh`), plus cases T5, T7 and T8.
- [x] Task C (DONE, commit bc476674, verified) (review batch): fail-closed sync read, SKIPPED not NEW, pending-last gate key, the NONEW CLEAN rule in `cmd_merge`, `CI_JQ_DEFS` with the `CI_PRELABEL_KEYS` rename (`lib/wrap/wrap.sh`), plus T3b, T9 to T13, the pending-last unit cases, and T6's exact read count.
