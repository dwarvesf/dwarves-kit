# Spec: wrap step 0 stops main-checkout writes only, so merges and tidy still land
Generated: 2026-10-02
Status: IMPLEMENTED, pending merge (branch `fix/wrap-step0-scope`); validate round 2 criticals folded, override logged
Lane: full (kit machinery: `lib/wrap/`, the `wrap` command contract)
Type: spec-feature
Depth: blind-spot (failure: a model-executed step 0 stop leaves a merge that writes the main working tree, or names a draft with --pr and merges it unreviewed)
File: `docs/specs/SPEC-383-wrap-step0-scope.md`
References: `docs/specs/SPEC-310-wrap-follow-through.md` (its Design record narrowed step 0 once, for isolated-worktree builds; this spec narrows it a second time); `docs/specs/SPEC-359-wrap-pull-only.md` (the `PULL_ONLY` gate this flag mirrors); `commands/wrap.md` (step 0, 3, 5, 7b, 10); `lib/wrap/wrap-apply.sh` (`_apply_repo`, `cmd_apply`); `lib/wrap/wrap-common.sh` (apply globals); `lib/wrap/wrap-merge.sh` (`_union_remerge`, `_branch_worktree`); `lib/wrap/wrap-land.sh` (`_land_tidy`); `lib/wrap/wrap.sh` (header usage); `bin/wrap`; `docs/consumer-contract.md`; `tests/test-wrap-apply.sh`; `tests/test-wrap-deploy.sh`

## Problem

`/kit:wrap` step 0 reads two foreign-activity signals: a reflog entry newer than the session start, or a held `index.lock`. On a shared checkout (ops-toolkit), other sessions' `pull --ff-only` wraps write the reflog all day, so the signal is true nearly every time. Today it stops every write to the main checkout, and the stop list names the merge (step 3) and all of step 5.

Observed live: two green own PRs stayed OPEN, the session's own squash-merged worktrees and branches stayed behind, and the operator had to ask why wrap did not wrap.

The stop exists to protect the main checkout's working tree, index, and HEAD (the 7b build bullet already says so). Most of what step 3 and step 5 do writes none of those:

| Action | What it writes | Writes the main checkout? |
|---|---|---|
| step 3 `wrap merge --apply`, clean PR | server-side `gh pr merge`, verified by fetch | no |
| step 3 `wrap merge` re-merge of a CONFLICTING PR | the worktree that holds the head branch, or a scratch detached worktree | no, except when the main checkout itself holds the head branch; `merge --no-pull` skips that PR |
| step 3 `wrap merge` squash fallback | a local `<branch>-squash` ref and objects, then a push | no (refs and objects only) |
| step 3 `wrap land` | pushes, merges, then `_land_ff_pull` pulls the main checkout | YES: HEAD, index, working tree |
| step 5 `apply --own <wt>` | the session's own worktree dirs and local branch refs | no |
| step 5 origin merged-branch sweep | origin only | no |
| step 5 stray-line carry | a scratch detached worktree, then a push | no (it never touches the working copy), but it publishes a foreign session's dirty lines, so `--no-pull` skips it |
| step 5 pull and stray-commits move | `pull --ff-only`, `reset --keep` | YES |

Stays stopped because it writes the main checkout: `land`, the pull (and the `pull_past_dirty` stash and pop), the stray-commits move of the default branch, the step 1 board flip, the step 2 commit, the step 6 activity line, a seam write into the checkout.

Gap in the verb: `bin/wrap apply` has no way to tidy without pulling. Even `--own` still runs the pull section and the stray-commits move, so the doc cannot tell a stopped session to run it.

## Solution

### Approaches considered

1. **Narrow the stop in the doc and add `apply --no-pull`.** The doc says exactly which writes stop. The verb gains one flag that gates the two main-checkout writes `apply` owns.
2. **Narrow the stop in the doc only.** A stopped session would still run `apply --own`, which pulls and may move the default branch under another session's feet. Rejected: it moves the unsafe write into the "allowed" path.
3. **Make `--own` imply no pull.** A silent behavior change for every caller of `--own`: step 10's landing and shared-repo wraps rely on `--own` pulling today. Rejected.
4. **Make the verb detect the foreign signal itself.** `_write_guard` already checks `index.lock` inside the verb, but the reflog signal lives in the command's judgment (session start time is not a verb input). Moving it into `apply` needs a session-start argument and a second source of truth for "foreign". Rejected for now; the command passes the flag when its check says stop.

### Chosen approach + why

Approach 1. The flag is explicit, so an existing call keeps its meaning, and the doc names the one command a stopped session runs.

## Design

Design-bearing: yes (a narrower safety rule in a command contract, plus one verb flag). No new component, no schema.

### Design record

**Rule.** Foreign activity stops every write to the MAIN CHECKOUT's working tree, index, and HEAD for the rest of the pass. A step is stopped only when it writes one of those. It stays stopped: `bin/wrap land` (its closing fast-forward pull), the pull with its `pull_past_dirty` stash and pop, the stray-commits move of the default branch, the step 1 board flip into the checkout, the step 2 commit, the step 6 activity line, and a seam write into the checkout.

**What keeps running under a stop:**

- Step 3 still merges, as `bin/wrap merge --apply --no-pull <repo>`: server-side, verified by fetch. `merge --no-pull` SKIPs any PR whose head branch the main checkout holds, whatever its state, printing `SKIP #<n>: head <branch> is checked out in the main checkout (--no-pull)`. That branch is by definition the live foreign session's own work: a re-merge of it (merge 1 makes PR 2 CONFLICTING through a CHANGELOG or LAB_LOG append, then `_union_remerge` picks the main checkout via `_branch_worktree`) writes the main checkout's HEAD and tree, and merging it at all lands mid-iteration work. Such a PR stays `OPEN`. A PR held by a linked worktree or no worktree is judged as usual. The lead never names a draft with `--pr`: `--pr` on a draft marks it ready and merges it.
- A branch in a hand-made worktree normally lands through `bin/wrap land`. Under a stop `land` does not run. The worktree and branch go under `Left alone`, with `bin/wrap land <wt>` as the retry once the writer clears.
- Step 5 first removes the session's own `EnterWorktree` worktree (`ExitWorktree remove`, then `git branch -D`): it writes no main-checkout state, so it runs under a stop. Then the tidy runs as `bin/wrap apply --apply --own <wt>... --no-pull <repo>`, dry run first. It removes the other own worktrees and branches and runs the origin merged-branch sweep. The tidy under a stop is `--own` only: without `--own`, `--no-pull` skips the worktree sweep and the all-branches sweep, printing `SKIP worktree sweep: --no-pull needs --own` and `SKIP branch sweep: --no-pull needs --own`. `<wt>` may be the path the first step already removed: `apply` prints `SKIP <path>: not a registered worktree`, skips the all-branches sweep as `--own` always does, and still runs the origin sweep and the carry. A session that never had a worktree skips the tidy under a stop, and `Left alone` says so.
- Step 7b and step 10 builds are unchanged from SPEC-310, except step 10's landing: its step 3 no longer stops at `OPEN` and its step 5 passes `--no-pull` when stopped.

**Limits the doc names, not hides.**

- A held `index.lock` (the second signal) still makes `apply` skip every removal: `_write_guard` guards each worktree removal and branch delete on that lock. So the tidy runs past the reflog signal only; under a persisting lock it prints `SKIP ...: index.lock held by another writer` and removes nothing. That fails safe.
- The stray-line carry does not run under a stop. It reads the shared checkout's dirty `merge=union` lines, which may include another live session's in-flight work, and publishing them would act on a checkout a foreign session is writing; the operator's overlay also sets `wrap.autoland_carry = true`, which would merge them. So `--no-pull` pushes nothing for stray lines: it prints `SKIP stray lines: --no-pull (N lines in <file> stay local)` per file and makes no `wrap/stray-*` branch. The next unstopped wrap carries them. The scan that counts the lines uses `git diff-index --name-only -z HEAD`, which does not refresh (write) the index the way `git diff` does.
- A skipped pull appears in the step 9 report as a `Left alone` row reading `PULL BLOCKED`, with the reason `step 0 stop`. `Left alone` is still derived from step 5's closing `bin/wrap scan` (its `behind=` count shows the checkout stayed behind); the `SKIP pull: --no-pull` line from `apply` supplies the reason, so the two agree.

**The verb.** `apply --no-pull` skips two sections and prints exactly one line for each, whatever the fetch result or checked-out branch: under the `-- stray commits:` header `SKIP stray commits: --no-pull`, and under the `-- pull:` header `SKIP pull: --no-pull`. The pull section includes the off-default `fetch origin <default>:<default>`, so a checkout on a feature branch skips it too. The worktree and branch tidy, the origin sweep, and the stray-line carry run as without the flag. `--no-pull` refuses `--pull-only` (exit 64, naming `--no-pull`), the same way `--pull-only` refuses its conflicting flags, before any fetch or write. The entry `fetch --prune` still runs: it writes remote-tracking refs only, the same stated exception SPEC-310 recorded for `wrap start`. `merge --no-pull` is the same promise for the merge verb: it skips every PR whose head the main checkout holds (the Rule above). Without `--own`, `apply --no-pull` skips the worktree and all-branches sweeps by name; the origin sweep runs either way.

**Re-checks.** The step 0 check still runs before steps 3, 5, and 6. A repo that goes foreign between checks drops out only of the stopped writes. Step 10's landing keeps its `wrap.merge_own_prs` false stop at `OPEN`; only the foreign-activity stop no longer ends it, and its step 5 passes `--no-pull` under a stop.

**Refinement of SPEC-310.** SPEC-310 kept the merge (step 3) and the tidy and pull (step 5) in the stop list and left a build's PR `OPEN`. Its reason, "its merge is a step 3 write", is wrong for `merge`: it writes no checkout state. This spec removes that line and the stop for `merge` and the own-worktree tidy, and keeps `land` and the pull stopped.

### Picture

```
foreign activity in <repo> (reflog newer than session start, or held index.lock)
        |
        v
   STOPPED (main-checkout writes only)                 STILL RUNS
   ------------------------------------                ----------------------------------------
   step 1  board flip into the checkout                step 3  wrap merge --apply --no-pull
   step 2  commit                                              (a PR whose head the main checkout
   step 3  wrap land (ff pull of main)                          holds is skipped, stays OPEN)
   step 5  pull, pull_past_dirty stash/pop             step 5  apply --apply --own <wt>... --no-pull
   step 5  stray-commits move of default                        - own worktrees + branches removed
   step 5  stray-line carry (push of other                        (not under a held index.lock)
           sessions' lines)                                     - origin merged-branch sweep
   step 6  activity line                                        (no --own: worktree and branch
   seam write into the checkout                                  sweeps skipped by name)
                                                       step 7b / 10 builds (SPEC-310)

 apply --no-pull
   fetch --prune -> worktrees -> branches (skipped under --own) -> origin sweep
        -> stray lines:   SKIP stray lines: --no-pull (N lines in <file> stay local)
        -> stray commits: SKIP stray commits: --no-pull   (always printed)
        -> pull:          SKIP pull: --no-pull            (always printed)
```

### Extensibility & boundaries

One flag on two verbs, one global (`NO_PULL`), a handful of gated sections, one doc rewrite. No daemon, no config knob: whether to pass `--no-pull` follows the step 0 signal, which the command already evaluates.

## After state

On a shared checkout where other sessions write the reflog, `/kit:wrap` still merges the session's green own PRs through `wrap merge` and removes the session's own merged worktrees and branches. It reports the pull it skipped as `PULL BLOCKED` under `Left alone`. A hand-made worktree waits for `bin/wrap land`, and a PR stays `OPEN` only when its re-merge would write the main checkout or it is a draft. The stray-line carry pushes its branch and never merges it during a stop.

## Task Breakdown

| Task | Files | Depends on |
|---|---|---|
| T1: `apply --no-pull`: flag, global, section gates, `--pull-only` refusal, usage strings (header, `_usage` sed window, no-repo usage, `bin/wrap`) | `lib/wrap/wrap-apply.sh`, `lib/wrap/wrap-common.sh`, `lib/wrap/wrap.sh`, `bin/wrap` | none |
| T2: step 0 stop rewrite and every dependent sentence (re-check bullet, step 3 opening and `land` bullet, step 5 opening and `--pull-only` bullet, step 7b build bullet, step 10 landing 3 and 5) | `commands/wrap.md` | T1 |
| T3: tests: apply cases, deploy-doc assertions | `tests/test-wrap-apply.sh`, `tests/test-wrap-deploy.sh` | T1, T2 |
| T4: flag surface docs, changelog, proof of done, implementation notes | `docs/consumer-contract.md`, `docs/CHANGELOG.md`, `docs/verification/wrap-step0-scope.md`, `docs/implementation-notes/wrap-step0-scope.md` | T3 |

## Acceptance Criteria (global)

- AC1: `apply --apply --no-pull` on a checkout that is behind origin leaves HEAD and the working tree byte-identical (same HEAD sha, same file content) and prints `SKIP pull: --no-pull`.
- AC2: `apply --apply --no-pull` on a default branch that is ahead of origin carries no stray commits (no `wrap/stray-commits-*` branch, HEAD unchanged) and prints `SKIP stray commits: --no-pull`.
- AC3: `apply --apply --own <wt> --no-pull` removes a proven-merged own worktree and deletes its branch, on a checkout behind origin whose HEAD stays unchanged.
- AC4: `apply --no-pull --pull-only` exits 64 in either flag order and the stderr names `--no-pull`; nothing is written.
- AC5: on a checkout on a feature branch, `apply --apply --no-pull` does not move the local default ref (the off-default `fetch origin <default>:<default>` is skipped) and prints `SKIP pull: --no-pull`; without the flag the same call moves it.
- AC6: `apply --apply` without `--no-pull` still pulls (existing cases stay green).
- AC7: `commands/wrap.md` step 0 keeps the literal `STOP every write to that repo's MAIN CHECKOUT`, lists the stopped writes (board flip, commit, `land`, pull with stash and pop, stray-commits move, activity line, seam write), says step 3 still merges as `bin/wrap merge --apply --no-pull <repo>` and that a PR whose head the main checkout holds is skipped whatever its state, says never to name a draft with `--pr`, says `land` does not run under a stop, says the stopped tidy is `--own` only and is skipped when the session never had a worktree, says step 5 runs `bin/wrap apply --apply --own <wt>... --no-pull <repo>` (dry run first), says stray lines are not pushed under a stop, names the index.lock limit, and no longer says a build's PR "stays `OPEN`, because its merge is a step 3 write" or that a clean PR the main checkout holds still merges.
- AC8: the dependent sentences agree: the re-check bullet, step 3's opening, step 5's opening, the `--pull-only` bullet (its refused-flag list names `--no-pull` for the reverse), the step 5 stray-lines bullet, step 10 landing steps 3, 4 and 5 (the `merge_own_prs` false stop kept, `--no-pull` added when stopped); `commands/wrap.md` carries no text that says a stop covers `wrap merge` or the own-worktree tidy.
- AC9: under `--no-pull` the stray-line carry pushes nothing, even with `wrap.autoland_carry` true: `apply --apply --no-pull` with a dirty `merge=union` file prints `SKIP stray lines: --no-pull (N lines in <file> stay local)`, makes no `wrap/stray-*` branch, opens and merges no PR, and leaves HEAD, the index file and the file's bytes unchanged; the scan uses `git diff-index`, not `git diff`.
- AC11: `merge --no-pull` skips a PR whose head branch the main checkout holds, CONFLICTING or clean, with and without `--pr`, printing `SKIP #<n>: head <branch> is checked out in the main checkout (--no-pull)`, and runs no re-merge and no `pr merge`; without `--no-pull` the same PR is eligible; a PR held by a linked worktree is not skipped.
- AC12: `apply --no-pull` without `--own` skips the worktree sweep and the all-branches sweep by name and deletes no proven-merged local branch or worktree, even under `--worktrees`, while the origin sweep still runs; with `--own` the origin sweep runs too.
- AC10: `tests/test-wrap-apply.sh`, `tests/test-wrap-carry.sh`, `tests/test-wrap-merge.sh`, `tests/test-wrap-deploy.sh`, `tests/test-wrap-pull.sh`, `tests/test-wrap-cli.sh` pass, and `bin/wrap --help` still prints its last header line.

## Test plan

| Case | AC | Kind |
|---|---|---|
| clone behind origin, `apply --apply --no-pull`: HEAD sha and a tracked file unchanged, SKIP pull line | AC1 | unit (real git) |
| clone ahead of origin on default, `apply --apply --no-pull`: no `wrap/stray-commits-*` branch, HEAD unchanged, SKIP stray commits line | AC2 | unit (real git) |
| own merged worktree, `apply --apply --own <wt> --no-pull` on a behind checkout: worktree dir and branch gone, HEAD unchanged | AC3 | unit (real git) |
| `apply --no-pull --pull-only` and `--pull-only --no-pull`: exit 64, stderr names `--no-pull` | AC4 | unit |
| feature-branch checkout with origin default advanced: `--no-pull` leaves the local default ref; plain apply moves it | AC5 | unit (real git) |
| dirty union file, `wrap.autoland_carry=true`: `--no-pull` prints the SKIP line, pushes no `wrap/stray-*` branch, opens and merges no PR; dirty bytes, HEAD and index file unchanged | AC9 | unit (real git) |
| main checkout holds the PR head: CONFLICTING, clean, and `--pr` variants skipped under `merge --no-pull`; control without the flag is eligible; a linked-worktree holder is not skipped | AC11 | unit (real git) |
| `apply --no-pull` without `--own`: both sweeps skipped by name, a merged branch and worktree survive, origin sweep still runs; with `--own` the origin sweep runs | AC12 | unit (real git) |
| existing pull and `--own` cases | AC6 | regression |
| doc literals: kept stop literal, stopped-write list, `land` stopped, `--pr <n>` and the re-merge skip, step 5 command, absence of the old sentence; step 10 landing literals | AC7, AC8 | doc contract |
| `bin/wrap --help` last header line present | AC10 | unit |
| negative controls NC1 to NC8 below | AC1, AC2, AC4, AC9, AC11, AC12 | negative control |

## Verification

```
bash tests/test-wrap-apply.sh
bash tests/test-wrap-deploy.sh
bash tests/test-wrap-pull.sh
bash tests/test-wrap-cli.sh
```

Negative controls, each after the change is committed, `T="bash tests/test-wrap-apply.sh"`:

- NC1 the pull still runs under `--no-pull`: mutate the `if [ "$NO_PULL" = 1 ]` pull gate in `_apply_repo` so it never fires. The AC1 case goes red.
- NC2 the stray-commits move still runs under `--no-pull`: mutate the stray-commits gate. The AC2 case goes red.
- NC3 the `--pull-only` conflict is dropped: delete the refusal. The AC4 case goes red.

- NC4 the carry still pushes under `--no-pull`: mutate the carry skip in `_carry_stray`. The AC9 case goes red.
- NC5 `merge --no-pull` still re-merges a main-held PR: mutate the loop skip in `cmd_merge`. The AC11 case goes red.
- NC6 `merge --no-pull --pr` still marks and merges a main-held PR: mutate the `--pr` skip. The AC11 `--pr` case goes red.
- NC7 the unscoped branch sweep runs under `--no-pull`: mutate the branch-sweep skip in `_apply_repo`. The AC12 case goes red.
- NC8 the carry scan refreshes the index again: mutate `diff-index` back to `diff HEAD`. The AC9 index-file case goes red.

Each runs through `bash lib/gate/negctl.sh "$PWD" "$T" "<sed mutation>"`. The exact `sed` lines are fixed in the proof file against the committed code, and each carries an exact-once match guard.

Proof of done: `docs/verification/wrap-step0-scope.md`. The command prose (the stop, the `land` hold, the `--pr` draft rule) is model-executed; the proof names it unproven until a real `/kit:wrap` run meets a foreign signal.

## Grounding

- **Live signal** (sampled in a scratch repo, 2026-10-02): a clone, then `git pull --ff-only` after origin advanced. `git reflog -2 --format='%gd %ct %gs'` printed `HEAD@{0} 1790937151 pull -q --ff-only: Fast-forward` and `HEAD@{1} 1790937151 clone: from <path>`. So a foreign `pull --ff-only` writes a HEAD reflog entry with a unix commit time, which is the "reflog newer than session start" signal, with no other trace. The incident itself (two own PRs left OPEN on a shared ops-toolkit checkout) comes from the operator's report and is not reproduced here.
- **`apply` section order** (read from `lib/wrap/wrap-apply.sh` `_apply_repo`): worktrees, branches, archive, origin sweep, stray lines, stray commits, pull. The flag removes the last two, the order of the rest is unchanged.
- **`land` writes the main checkout** (read, `lib/wrap/wrap-land.sh` `_land_tidy` calls `_land_ff_pull`, which runs `git pull --ff-only` and carries union files). `lib/wrap` has no reflog check; only `_write_guard` reads `index.lock`.
- **Re-merge location** (read, `lib/wrap/wrap-merge.sh`): `_union_remerge` calls `_branch_worktree`, which returns the main checkout when it holds the head branch. The dry run prints `note: #<n> conflicts; --apply would try one re-merge of <def> into <head>`.
- **Dry trace of NC1:** mutation = make the pull gate never fire. The AC1 test runs `apply --apply --no-pull` on a clone behind origin, then asserts HEAD equals the pre-run sha. With the mutation the pull fast-forwards, HEAD moves, and the assertion fails.
- **Dry trace of NC3:** mutation = delete the `--no-pull` and `--pull-only` conflict refusal. The AC4 case runs both flag orders and asserts exit 64 plus the flag name on stderr. With the refusal gone the call exits 0 and the assertion fails.
- **Dry trace of NC4:** mutation = drop the `NO_PULL` skip in `_carry_stray`. The AC9 case sets `autoland_carry=true` through the root config, builds a dirty union file, runs `apply --apply --no-pull`, and asserts no `wrap/stray-*` branch on origin and no `pr merge` in the stub. With the mutation the carry pushes a branch and autolands.
- **Dry trace of NC5:** mutation = remove the loop skip. The AC11 case holds `feat/union` in the main checkout with a CONFLICTING PR and asserts the branch tip and HEAD are unchanged and no re-merge line. With the mutation `_union_remerge` runs in the main checkout and the tip moves.
- **Dry trace of NC2:** mutation = make the stray-commits gate never fire. The AC2 test builds a default branch ahead of origin, runs `apply --apply --no-pull`, and asserts no `wrap/stray-commits-*` branch exists. With the mutation the carry creates one and the assertion fails.

## Failure modes

| Failure | Effect | Handling |
|---|---|---|
| a CONFLICTING PR's head branch is checked out in the main checkout and a foreign writer is active | a re-merge would write that working tree | the doc protocol: dry run, skip that PR, it stays `OPEN`; a verb gate is out of scope |
| the lead runs `merge --apply` without `--no-pull` under a stop | the re-merge may run in the main checkout | the doc names the stopped form; the existing dirty and `index.lock` guards in `_union_remerge` still narrow it |
| a stopped session runs `wrap land` | an ff pull of the main checkout under a foreign writer | the doc says `land` does not run under a stop; the worktree goes to `Left alone` |
| `--no-pull` passed with `--pull-only` | a no-op that looks like success | exit 64 naming the flag |
| a stopped repo never pulls | the checkout stays behind | `Left alone` reports `PULL BLOCKED`; the next unstopped wrap pulls |
| the stop signal is a held `index.lock` | `apply` skips every removal | fails safe; the doc names the limit, the next wrap tidies |
| `apply --no-pull` without `--own` on a shared repo | the all-branches sweep deletes other sessions' proven-merged local branches | the doc pairs `--no-pull` with `--own` under a stop; with no own worktree the tidy is skipped; each delete keeps its merge proof |
| two stopped wraps race the origin sweep or the carry | one gets `FAILED delete` or a skipped carry branch | each push is leased; the loser reports `FAILED`, exit 2, nothing is lost |
| the carry ships another live session's dirty union lines | a duplicate row on a pushed branch | recoverable branch, dedupe by id; `--no-pull` suppresses autoland so nothing merges |
| `--pr <n>` names a draft | `gh pr ready` plus a merge of a full-lane draft | the doc says never name a draft with `--pr`; drafts stay with the operator |
| `apply --no-pull` runs without `--own` | the all-branches and worktree sweeps would reach other sessions | the verb skips both by name; the origin sweep still runs |

## Edge Cases

- Default branch not resolved: `apply` skips the repo as before; `--no-pull` changes nothing there.
- Checkout on a feature branch: the `--no-pull` pull line prints and the `fetch origin <default>:<default>` is skipped with it.
- Fetch failed: with `--no-pull` the stray-commits section prints only `SKIP stray commits: --no-pull`, replacing the fetch-failed line; stray lines keep their fetch-failed line.
- The session's own worktree is already removed by step 5's first action: pass its path as `--own`; `apply` reports it as not registered and still runs the origin sweep. A session that never had a worktree skips the tidy under a stop.

## Out of Scope

- Changing what the step 0 signal measures (reflog and lock).
- Making the verb detect the signal and pass `--no-pull` itself (Approach 4).
- A `wrap.apply_no_pull` knob.
- A no-pull mode for `wrap land`.

## Decision Log

- Flag, not a new verb: `apply` already owns the tidy, and `PULL_ONLY` set the precedent for a gate global.
- `--own` does not imply `--no-pull`: step 10 and shared-repo wraps rely on `--own` pulling.
- The fetch stays: remote-tracking refs only, the same exception SPEC-310 stated for `wrap start`.
- The main-checkout re-merge is gated at the verb: `merge --no-pull` skips any PR whose head the main checkout holds, whatever its state (code review: a doc protocol could be skipped, and that branch is a live session's work).
- `land` stays stopped rather than getting a no-pull path: it writes the checkout by design, and a worktree can wait for the next wrap.
- The stray-line carry does not run under a stop: it would publish a live session's dirty lines, and the operator's own overlay turns autoland on (code review reversed the earlier keep-without-autoland call).
- The depth rises to `blind-spot` because the command prose and the draft rule are model-executed and unprovable here; the proof file says so.
- The `_usage` sed window widens by one line, the same fix SPEC-359 used.

## Open questions

(none)

## Review disposition

Validate round 1 ran seven reviewers (R6 on Opus). Verdict NEEDS REVISION, 3 critical, R6 design-bearing pass.

| Finding | Disposition |
|---|---|
| `wrap land` writes the main checkout (`_land_ff_pull`) but step 3 was released whole (R1, R2, R4, R5) | folded: `land` stays stopped; table, Rule, Picture, AC7, failure row |
| re-merge exception prose-only, wrong scope, no mechanism (R2, R3, R4, R5, R6) | folded: narrowed to a CONFLICTING PR held by the main checkout; dry-run plus `--pr <n>` protocol; the verb gate stays out of scope and is named accepted residue |
| Grounding live signal unsampled under `standard` depth (R4) | folded: sampled the reflog entry a `pull --ff-only` writes |
| stray-line carry publishes other sessions' lines (R1, R2, R3, R4, R5, R6) | folded: kept deliberately, decision and reasons in Design and Decision Log |
| held `index.lock` defeats the tidy; After state overclaims (R2, R3, R5, R6) | folded: limit named in the record, After state, failure row |
| `PULL BLOCKED` has no producer under `--no-pull` (R3, R4, R5, R6) | folded: the model derives the `Left alone` row from the `SKIP pull` line; the doc says so |
| step 10 contradiction ("unchanged" vs AC7) (R3, R4) | folded: Design names step 10's landing 3 and 5 as changed |
| stray-commits line condition and Picture drift (R3, R4, R5) | folded: the line always prints under `--no-pull`; Edge Cases and Picture agree |
| failure row on `--no-pull` without `--own` wrong (R2, R3) | folded: it is the all-branches sweep; no own worktree means the tidy is skipped |
| NC1 does not cover AC2; exact sed deferred; feature-branch path untested (R2, R3, R4) | folded: NC2, NC3, AC5 and its case; sed fixed in the proof file with match guards |
| `--help` window, consumer-contract, `--pull-only` bullet not in tasks (R3, R4, R5, R2) | folded: T1, T2, T4, AC9 |
| `--no-pull` name understates the stray-commits push it also skips (R5) | rejected: the push is moot without the reset, and the skip is named in the verb's lines |
| squash fallback missing from the table (R6) | folded: row added |
| a self-detecting verb dismissed thinly (R5) | folded: Approach 4 with the real reason |
| concurrent-wrap race on origin sweep and carry (R2) | folded: failure row |

Validate round 2 ran seven reviewers (R6 on Opus). Verdict NEEDS REVISION, 3 critical, R6 design-bearing pass. This is the full-lane re-validation; the criticals are folded and the round-ceiling rule leaves the decision to the operator.

| Finding | Disposition |
|---|---|
| carry autolands a foreign session's lines under a stop, `autoland_carry` is true in the operator overlay (R3, R4, R5) | folded: `--no-pull` suppresses the autoland leg; AC9, NC4, test case |
| `--pr <n>` readies and merges a draft (R6) | folded: `--pr` only for `eligible #<n>`, never a draft; failure row |
| `standard` depth with an unprovable failure mode (R4) | folded: `Depth: blind-spot (failure: ...)` |
| dry-run note rarely prints; `--pr` is not the re-merge guard (R1, R2, R3, R6) | folded: the lead compares the PR head with `branch --show-current` before naming it; per-PR dry run |
| the `EnterWorktree` removal and the "tidy skipped" rule (R2, R3, R4, R5, R6) | folded: it runs under a stop; `--own` may name the removed path |
| `PULL BLOCKED` derivation conflicts with `Left alone` from the closing scan (R3, R4, R5) | folded: scan supplies the state, the SKIP line the reason |
| step 10 `merge_own_prs` false stop (R5) | folded: Design names it kept |
| index.lock prose overstated (R1) | noted: the build words it as local removals |
| NC3 dry trace, the carry invariant case, AC7 granularity (R4, R5) | folded: NC3 trace, AC9; AC7 literals split by the builder into separate assertions |
| verb-level gate for the main-checkout re-merge (R2) | noted: accepted residue, out of scope |

## Code review fold

Review ran opus review-team lenses on the built branch. Verdict APPROVE WITH FIXES, all folded as new commits.

| # | Sev | Finding | Fix |
|---|---|---|---|
| 1, 2 | HIGH, MED | under a stop a PR whose head the main checkout holds can still be re-merged into it (merge 1 makes PR 2 CONFLICTING, `_union_remerge` picks the main checkout), and that branch is a live session's work, so merging it at all lands mid-iteration work | `wrap merge --no-pull`: skips any PR whose head the main checkout holds, whatever its state, with `SKIP #<n>: head <branch> is checked out in the main checkout (--no-pull)`; step 3 under a stop is `merge --apply --no-pull`; the prose-only head-compare protocol is dropped |
| 3 | MED | the stray-line carry publishes a live session's dirty lines, and autoland would merge them | under `--no-pull` the carry pushes nothing: `SKIP stray lines: --no-pull (N lines in <file> stay local)`; the earlier `_autoland_on` guard is removed as dead code |
| 4 | LOW-MED | `apply --no-pull` without `--own` still ran the all-branches sweep | both local sweeps (worktrees and branches) skip by name without `--own`; step 5 says the stopped tidy is `--own` only and skipped when the session had no worktree |
| 5 | LOW | `git diff HEAD` in the main checkout refreshes (writes) the index | `git diff-index --name-only -z HEAD` in the stray-line scan; the other porcelain calls that run in the main checkout under `--no-pull` (stray-commits and pull helpers) are skipped sections, and the worktree `status` calls skip the main checkout |
| 6 | LOW | no `--no-pull` variant of the origin-sweep fixture | added, with and without `--own` |
