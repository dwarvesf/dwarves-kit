# Spec: wrap step 0 stops main-checkout writes only, so merges and tidy still land
Generated: 2026-10-02
Status: DRAFT
Lane: full (kit machinery: `lib/wrap/`, the `wrap` command contract)
Type: spec-feature
Depth: standard (the stop's reason is stated in the doc already; the one new verb flag reuses the existing `PULL_ONLY` gate shape)
File: `docs/specs/SPEC-383-wrap-step0-scope.md`
References: `docs/specs/SPEC-310-wrap-follow-through.md` (its Design record narrowed step 0 once, for isolated-worktree builds; this spec narrows it a second time); `docs/specs/SPEC-359-wrap-pull-only.md` (the `PULL_ONLY` gate this flag mirrors); `commands/wrap.md` (step 0, 3, 5, 7b, 10); `lib/wrap/wrap-apply.sh` (`_apply_repo`, `cmd_apply`); `lib/wrap/wrap-common.sh` (apply globals); `lib/wrap/wrap.sh` (header usage); `bin/wrap`; `tests/test-wrap-apply.sh`; `tests/test-wrap-deploy.sh`

## Problem

`/kit:wrap` step 0 reads two foreign-activity signals: a reflog entry newer than the session start, or a held `index.lock`. On a shared checkout (ops-toolkit), other sessions' `pull --ff-only` wraps write the reflog all day, so the signal is true nearly every time. Today it stops every write to the main checkout, and the stop list names the merge (step 3) and all of step 5.

Observed live: two green own PRs stayed OPEN, the session's own squash-merged worktrees and branches stayed behind, and the operator had to ask why wrap did not wrap.

The stop exists to protect the main checkout's working tree, index, and HEAD (the 7b build bullet already says so). The merge and the own-worktree tidy write none of those:

| Action | What it writes | Writes the main checkout? |
|---|---|---|
| step 3 `wrap merge --apply` | server-side `gh pr merge`, verified by fetch; a re-merge runs in the worktree holding the branch, or a scratch detached worktree | no, except a PR whose head branch IS checked out in the main checkout |
| step 5 `apply --own <wt>` | the session's own worktree dirs and local branch refs | no |
| step 5 origin merged-branch sweep | origin only | no |
| step 5 stray-line carry | a scratch detached worktree, then a push | no (it never touches the working copy) |

These DO write the main checkout and stay stopped: the pull (and the `pull_past_dirty` stash and pop), the stray-commits move of the default branch, the step 1 board flip, the step 2 commit, the step 6 activity line, a seam write into the checkout.

Gap in the verb: `bin/wrap apply` has no way to tidy without pulling. Even `--own` still runs the pull section and the stray-commits move, so the doc cannot tell a stopped session to run it.

## Solution

### Approaches considered

1. **Narrow the stop in the doc and add `apply --no-pull`.** The doc says exactly which writes stop. The verb gains one flag that gates the two main-checkout writes `apply` owns.
2. **Narrow the stop in the doc only.** A stopped session would still run `apply --own`, which pulls and may move the default branch under another session's feet. Rejected: it moves the unsafe write into the "allowed" path.
3. **Make `--own` imply no pull.** A silent behavior change for every caller of `--own`: step 10's landing and shared-repo wraps rely on `--own` pulling today. Rejected.

### Chosen approach + why

Approach 1. The flag is explicit, so an existing call keeps its meaning, and the doc names the one command a stopped session runs.

## Design

Design-bearing: yes (a narrower safety rule in a command contract, plus one verb flag). No new component, no schema.

### Design record

**Rule.** Foreign activity stops every write to the MAIN CHECKOUT's working tree, index, and HEAD for the rest of the pass. A step is stopped only when it writes one of those. It stays stopped: the step 1 board flip into the checkout, the step 2 commit, the pull with its `pull_past_dirty` stash and pop, the stray-commits move of the default branch, the step 6 activity line, and a seam write into the checkout.

**What keeps running under a stop:**

- Step 3 still merges. `wrap merge --apply` is a server-side merge verified by fetch. Its re-merge of a conflicting PR runs in the worktree that holds the branch or a scratch detached worktree. One exception: a PR whose head branch is checked out in the main checkout itself. Its re-merge would write that working tree, so it stays `OPEN` under a stop.
- Step 5 tidy runs as `bin/wrap apply --apply --own <wt>... --no-pull <repo>`, dry run first. It removes the session's own worktrees and branches, runs the origin merged-branch sweep, and carries stray lines through a scratch worktree.
- Step 7b and step 10 builds are unchanged from SPEC-310.

**The verb.** `apply --no-pull` skips two sections: the pull and the stray-commits move. Each prints one line: `SKIP pull: --no-pull` and `SKIP stray commits: --no-pull`. The worktree and branch tidy, the origin sweep, and the stray-line carry run as without the flag. It refuses `--pull-only` (exit 64, naming `--no-pull`), the same way `--pull-only` already refuses its conflicting flags. The entry fetch (`fetch --prune`) still runs: it writes remote-tracking refs only, the same stated exception SPEC-310 recorded for `wrap start`.

**Re-checks.** The step 0 check still runs before steps 3, 5, and 6. A repo that goes foreign between checks does not drop out of steps 3 and 5 any more. It drops out only of the stopped writes.

**Refinement of SPEC-310.** SPEC-310 kept the merge (step 3) and the tidy and pull (step 5) in the stop list and left a build's PR `OPEN`. That reason, "its merge is a step 3 write", is wrong: the merge writes no checkout state. This spec removes the line and the stop for those two steps.

### Picture

```
foreign activity in <repo> (reflog newer than session start, or held index.lock)
        |
        v
   STOPPED (main-checkout writes only)                 STILL RUNS
   ------------------------------------                ---------------------------------
   step 1  board flip into the checkout                step 3  wrap merge --apply
   step 2  commit                                              (PR head checked out in the
   step 5  pull, pull_past_dirty stash/pop                      main checkout: stays OPEN)
   step 5  stray-commits move of default               step 5  apply --apply --own <wt>... --no-pull
   step 6  activity line                                        - own worktrees + branches removed
   seam write into the checkout                                 - origin merged-branch sweep
                                                                - stray-line carry (scratch wt)
                                                       step 7b / 10 builds (SPEC-310)

 apply --no-pull
   fetch --prune -> worktrees -> branches -> origin sweep -> stray lines
        -> stray commits: SKIP stray commits: --no-pull
        -> pull:          SKIP pull: --no-pull
```

### Extensibility & boundaries

One flag, one global (`NO_PULL`), two gated sections, one doc rewrite. No daemon, no config knob: whether to pass `--no-pull` follows the step 0 signal, which the command already evaluates.

## After state

On a shared checkout where other sessions write the reflog, `/kit:wrap` still merges the session's green own PRs and removes the session's own merged worktrees and branches. It reports `PULL BLOCKED`-style residue for the pull it skipped, never leaves a PR open for a reason that protects nothing.

## Task Breakdown

| Task | Files | Depends on |
|---|---|---|
| T1: `apply --no-pull`: flag, global, section gates, `--pull-only` refusal, usage strings | `lib/wrap/wrap-apply.sh`, `lib/wrap/wrap-common.sh`, `lib/wrap/wrap.sh`, `bin/wrap` | none |
| T2: step 0 stop rewrite and dependent sentences | `commands/wrap.md` | T1 |
| T3: tests: apply cases, deploy-doc assertions | `tests/test-wrap-apply.sh`, `tests/test-wrap-deploy.sh` | T1, T2 |
| T4: changelog, proof of done, implementation notes | `docs/CHANGELOG.md`, `docs/verification/wrap-step0-scope.md`, `docs/implementation-notes/wrap-step0-scope.md` | T3 |

## Acceptance Criteria (global)

- AC1: `apply --no-pull` on a checkout that is behind origin leaves HEAD and the working tree byte-identical (same HEAD sha, same file content), under `--apply`, and prints `SKIP pull: --no-pull`.
- AC2: `apply --no-pull` on a default branch that is ahead of origin does not carry stray commits or move the default branch, and prints `SKIP stray commits: --no-pull`.
- AC3: `apply --apply --own <wt> --no-pull` still removes a proven-merged own worktree and deletes its branch.
- AC4: `apply --no-pull --pull-only` exits 64 and the stderr names `--no-pull`; the combination writes nothing.
- AC5: `apply --apply` without `--no-pull` still pulls (existing cases stay green).
- AC6: `commands/wrap.md` step 0 states the stop covers exactly the main-checkout writes (board flip, commit, pull and stash/pop, stray-commits move, activity line, seam write into the checkout), says step 3 still merges (except a PR whose head is checked out in the main checkout) and step 5 runs `bin/wrap apply --apply --own <wt>... --no-pull <repo>` (dry run first), and no longer says a build's PR "stays `OPEN`, because its merge is a step 3 write".
- AC7: every dependent sentence agrees: the re-check bullet, step 3's opening, step 5's opening, step 10 landing step 3 and step 5, with no remaining text that says a stop covers the merge or the own-worktree tidy.
- AC8: `tests/test-wrap-apply.sh`, `tests/test-wrap-deploy.sh`, `tests/test-wrap-cli.sh`, `tests/test-wrap-pull.sh` pass.

## Test plan

| Case | AC | Kind |
|---|---|---|
| clone behind origin, `apply --apply --no-pull`: HEAD sha and a tracked file unchanged, SKIP pull line | AC1 | unit (real git) |
| clone ahead of origin on default, `apply --apply --no-pull`: no `wrap/stray-commits-*` branch, HEAD unchanged, SKIP stray commits line | AC2 | unit (real git) |
| own merged worktree, `apply --apply --own <wt> --no-pull`: worktree dir and branch gone, HEAD unchanged on a behind checkout | AC3 | unit (real git) |
| `apply --no-pull --pull-only`: exit 64, stderr names `--no-pull`; reverse flag order too | AC4 | unit |
| existing pull and `--own` cases | AC5 | regression |
| doc literals: stop list, step 3 and 5 stopped paths, exception, absence of the old sentences | AC6, AC7 | doc contract |
| negative control NC1 below | AC1, AC2 | negative control |

## Verification

```
bash tests/test-wrap-apply.sh
bash tests/test-wrap-deploy.sh
bash tests/test-wrap-pull.sh
bash tests/test-wrap-cli.sh
```

Negative control, after the change is committed, `T="bash tests/test-wrap-apply.sh"`:

- NC1 the `--no-pull` branch still pulls: `bash lib/gate/negctl.sh "$PWD" "$T" "<mutation making the pull section ignore NO_PULL>"`. The new HEAD-unchanged case must go red. The exact `sed` is fixed in the proof file once the gate's line exists.

Proof of done: `docs/verification/wrap-step0-scope.md`.

## Grounding

- **Live signal:** the reflog check fires on `pull --ff-only` by any session. Sampled from the operator's report of the incident (two own PRs left OPEN on a shared ops-toolkit checkout); not re-run here, since reproducing it needs a second live session.
- **`apply` section order** (read from `lib/wrap/wrap-apply.sh` `_apply_repo`): worktrees, branches, archive, origin sweep, stray lines, stray commits, pull. The flag removes the last two, the order of the rest is unchanged.
- **Dry trace of NC1:** mutation = make `_apply_repo` ignore `NO_PULL` before the pull section. The AC1 test runs `apply --apply --no-pull` on a clone behind origin, then asserts HEAD equals the pre-run sha. With the mutation the pull fast-forwards, HEAD moves, and the assertion fails.

## Failure modes

| Failure | Effect | Handling |
|---|---|---|
| the PR's head branch is checked out in the main checkout and a foreign writer is active | a re-merge would write that working tree | the doc names this exception: that PR stays `OPEN` under a stop |
| `--no-pull` passed with `--pull-only` | a no-op that looks like success | exit 64 naming the flag |
| a stopped repo never pulls | the checkout stays behind | `Left alone` and `PULL BLOCKED` report it; the next unstopped wrap pulls |
| `--no-pull` without `--own` on a shared repo | sweeps every proven-merged worktree, including other sessions' | the doc pairs the two flags under a stop; `--worktrees` scope rules are unchanged |
| a foreign writer is mid-write while step 5 removes a branch | a ref race | removal is proven per worktree and branch by the existing merge proofs; none touches the working tree |

## Edge Cases

- Default branch not resolved: `apply` skips the repo as before; `--no-pull` changes nothing there.
- Checkout on a feature branch: the pull section's `fetch origin <default>:<default>` is part of the skipped section, so a stopped session also skips it.
- Fetch failed: the stray-commits and stray-lines lines read as before; the `--no-pull` line replaces only the pull and stray-commits output.

## Out of Scope

- Changing what the step 0 signal measures (reflog and lock).
- Auto-passing `--no-pull` from the verb when it sees the signal: the verb stays a tool, the command decides.
- A `wrap.apply_no_pull` knob.

## Decision Log

- Flag, not a new verb: `apply` already owns the tidy, and `PULL_ONLY` set the precedent for a gate global.
- `--own` does not imply `--no-pull`: step 10 and shared-repo wraps rely on `--own` pulling.
- The fetch stays: remote-tracking refs only, the same exception SPEC-310 stated for `wrap start`.
- The re-merge exception names the PR whose head is checked out in the main checkout, because that is the one merge path that writes it.

## Open questions

(none)
