# Verification log: wrap apply removes a proven-merged locked worktree

Goal: `.claude/goals/wrap-apply-locked-agent-worktree.md`. Lane normal, class behavioral. Branch
`feat/wrap-apply-locked-worktree`, base a861ba2 (origin/master at start), commits 0f94295 and
8afcc70. Change: `lib/wrap/wrap.sh` `_apply_worktrees` plus `_merge_proof`, `_wt_locked`,
`_wt_cleared`; tests `tests/test-wrap.sh`; doc `commands/wrap.md` step 5.

Visible surface: the `apply` report lines. The captures below are the real CLI text, pasted inline.

## The four outcomes

| Outcome | Gate | Report line |
|---|---|---|
| locked, clean, attached, branch proven merged | removed, branch deleted, postcondition checked | `[APPLY] remove worktree <path> [<branch>, locked] and delete <branch> (<proof>)` then `[APPLY] delete <branch> (<proof>, its locked worktree is gone)` |
| locked, dirty | skipped, unchanged reason | `SKIP <path>: dirty (another session's work stays)` |
| locked, clean, branch unproven | skipped, new reason | `SKIP <path>: <branch> is not proven merged into <default> (leave it)` |
| removal left the path behind | FAILED, branch kept | `FAILED remove worktree <path> [...]: <path> survived the removal, <branch> not deleted` |

Detached and checked-out worktrees keep their own reasons. Dry run prints `WOULD <the same verdict>`.

## Suite

Command: `bash tests/test-wrap.sh`
Exit: 0
Output (excerpt): `test-wrap: all 361 passed` (330 before this branch; 31 new assertions across the
locked-worktree matrix, the postcondition case, the two protected-branch guards, the moved tip, the
index.lock and failed-fetch paths at the worktree write site, and the report-line checks)
Verdict: PASS

Command: `bash tests/run-all.sh`
Exit: 0
Output (tail):

```
test-wrap                                      ok

run-all: FAILED -> test-config-registry test-kit-foldin-hooks
run-all: 139 suites run, 1 skipped for missing tooling
```

Verdict: PASS for this change. Both named suites are unrelated to it. `test-config-registry` fails
the same two `wrap.drain_staged` assertions on a pristine `origin/master` checkout (48/50 there), so
it pre-dates this branch. `test-kit-foldin-hooks` passes standalone on this branch (94/94) and failed
only inside the full run, which is the known run-all tree contention another branch is fixing.

## Real primary flow, end to end

A real clone of this repo, a real locked worktree on a branch that is a real ancestor of
`origin/master`, driven by the real `bin/wrap`.

Command: `bash bin/wrap apply --worktrees <clone>` then `bash bin/wrap apply --apply --worktrees <clone>`
Exit: 0 and 0

```
### DRY RUN
-- worktrees:
     WOULD remove worktree /private/var/folders/.../wrap-realflow.8V0ib8/agent-wt [landed, locked] and delete landed (ancestor of origin/master)
dry-run exit: 0
path still there after the dry run: yes

### APPLY
-- worktrees:
     [APPLY] remove worktree /private/var/folders/.../wrap-realflow.8V0ib8/agent-wt [landed, locked] and delete landed (ancestor of origin/master)
     [APPLY] delete landed (ancestor of origin/master, its locked worktree is gone)
Deleted branch landed (was 0853226).

### after
path: gone
branch landed: gone
```

Verdict: PASS. The dry run wrote nothing; the apply removed the locked worktree, deleted its branch,
and the postcondition passed.

## Real report on the live clone (read-only)

Command: `bash bin/wrap apply --worktrees <this repo's main checkout>`
Exit: 0
Output (excerpt):

```
     WOULD remove worktree .../.claude/worktrees/id-mint-history [fix/id-mint-history, unlocked] and delete fix/id-mint-history (squash-merged per gh)
     SKIP .../.claude/worktrees/wrap-full-to-board: feat/wrap-full-to-board is not proven merged into master (leave it)
     SKIP .../.claude/worktrees/wrap-locked-worktree: feat/wrap-apply-locked-worktree is not proven merged into master (leave it)
```

Verdict: PASS. Eleven proven worktrees read as `WOULD`; the two live unproven ones, including this
branch's own, are left alone. Dry run, so nothing was written.

## Which removal form this git needs

Command: a scratch repo with three locked worktrees, one removal form each (git 2.55.0)
Exit: `remove --force` 128, `remove -f -f` 0, `unlock` + `remove` 0
Output (excerpt): `fatal: cannot remove a locked working tree; use 'remove -f -f' to override or
unlock first` for the single force, path still present; both other forms cleared the path
Verdict: `-f -f` kept, one call instead of two, and the source comment now states the measured
behavior. The second measurement behind the postcondition: with the worktree's parent directory at
mode 500, `remove -f -f` exits 255, the directory survives, and `git worktree list` no longer names
it, so neither the exit code nor the list alone proves the removal.

## Review wave (lib/ escalation) and the fix batch (8afcc70)

Two read-only lenses on the diff, dispatched in parallel at Sonnet: security and test coverage.
Both scored 6/10 and both found real holes, each fixed in 8afcc70.

| Lens | Finding | Severity | Resolution |
|---|---|---|---|
| security | a secondary worktree may hold the default branch while the main checkout stands elsewhere; the default branch is its own ancestor, so the proof passed and `branch -D` would have deleted the local default branch | HIGH | the worktree pass now refuses the default plus `main` and `master` by name, as the branch pass does |
| security | the merge proof can cost a network round trip, which widened the window between the dirty check and a force that overrides dirty state | MED | the dirty state and the branch tip are re-read immediately before the force |
| coverage | nothing asserted that a failed postcondition holds back the branch delete | HIGH | `chk_no` on the step's own branch-delete line in the postcondition case |
| coverage | the `wtb == cur` guard, the index.lock guard and the failed-fetch skip at the worktree site, and the `unlocked` label had no test | MED / LOW | one case each, the two protected cases reached through `worktree add --force` |
| coverage | the `worktree list` half of the postcondition has no reachable fixture | HIGH | accepted as a gap, see the mutation table |

## Mutation results (each on the committed tree, restore `git checkout HEAD --`)

| Guard removed | Suite |
|---|---|
| the merge proof on the worktree gate | RED |
| the default/protected-branch guard | RED |
| the main-checkout-branch guard | RED |
| the failed-fetch guard | RED |
| the tip re-check before the force | RED |
| the index.lock pre-check at the worktree site | RED |
| the postcondition gate on the branch delete | RED |
| the lock label read from git (hardcode `locked`) | RED |
| the dirty re-check before the force | GREEN, gap |
| the `worktree list` half of `_wt_cleared` | GREEN, gap |

Both gaps are deliberate and named rather than papered over. The dirty re-check guards a race, so a
deterministic fixture cannot reach it while the first dirty check already covers the steady state.
The `worktree list` half has no constructible fixture on git 2.55: when a worktree directory vanishes
behind git's back, `remove -f -f` exits 0 and prunes the admin entry, so the path half fails first
every time. Both stay in the code as defence on a destructive path.

## NEGATIVE CONTROL (negctl, committed tree at 7e5a616)

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "bash <mutate.sh>"`, where the
mutation drops the merge proof from the worktree gate (`|| proof="unproven"` in place of the SKIP)
Exit: 0

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: bash .../mutate.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Verdict: RED-as-expected. Without the proof the unproven locked worktree is removed again and the
matrix cases fail.

## Reproducible

Re-run `bash tests/test-wrap.sh` on this branch for the matrix, the guards and the postcondition, and
`bash bin/wrap apply --worktrees <any repo>` for the report lines. The real-flow script is six
commands: clone this repo, `git branch landed origin/master~3`, `git worktree add` on it,
`git worktree lock`, then `apply --worktrees` dry and `--apply`.
