# SPEC-374: wrap land merges the default branch into a conflicting own PR instead of stopping

**Status:** DRAFT
Lane: full
Type: spec-feature
**Proof:** `docs/verification/land-merge-default.md`; `tests/test-wrap.sh`, the land-merge block.
References: `lib/wrap/wrap.sh` `cmd_rebase` and its `_rb_*` helpers (SPEC-329): the stop classifier, the CHANGELOG pure-addition resolver, the exact stage set and the marker scan this spec reuses. `_remerge_push` and `_union_dedupe_rows` (the `wrap merge` re-merge): the merge-not-rebase shape, the "already contains origin/<def>" guard, and the union-row dedupe.

## Problem

`wrap land <worktree>` pushes the branch, opens or adopts the PR, then calls `gh pr merge --squash --match-head-commit`. When `origin/<default>` moved on and the PR is CONFLICTING, GitHub refuses the merge and `land` exits 2 with `MERGE FAILED #<n>: exit 1`. The only verb that moves a branch past the default is `wrap rebase`, which rewrites history. The branch is already on origin, so the rebased branch needs a force-push, and the operator's rule forbids a force-push without confirmation.

In one session this happened four times. Each time the lead ran the same loop by hand in the worktree: `git merge --no-edit origin/<default>`, regenerate `docs/FEATURES.md` with the repo's own generator, rerun the tests, push normally, run `wrap land` again. The loop never needed a rebase, and it never needed a force.

`wrap merge --apply` already re-merges `origin/<default>` into a conflicting own PR (`_remerge_push`), but it aborts on any conflict git's union driver does not resolve, so a `docs/FEATURES.md` or `docs/CHANGELOG.md` conflict stops it too.

## Contract

Three helpers, each with one job, and two callers. Every helper returns 0 on success, 1 when it refused and left `<branch>` exactly at `<tip>` with no merge in progress, and 2 when it could not restore that state and a human must look (the line names the command to run).

### `_merge_default <wt> <branch> <def> <tip>`: merge, resolve, commit

- Preconditions, checked first, each a return 1 with one line and no write: the checkout's HEAD is `<tip>`; no tracked or untracked change (`status --porcelain`); no merge, rebase or cherry-pick in progress; `_write_guard` passes; `origin/<def>` is not already an ancestor of `<tip>`.
- It runs `git merge --no-ff --no-commit origin/<def>` through `_rb_git` (`GIT_EDITOR=true`, `-c rerere.enabled=false`). It never runs `git rebase` and never pushes.
- When paths are unmerged, it calls `_rb_stop` with an explicit operation argument `merge` (see T1). The rebase classes apply unchanged: `docs/FEATURES.md` with `<wt>/lib/registry/feature-registry.sh` present is regenerated; `docs/CHANGELOG.md` is kept both sides only when both sides purely added lines; anything else, including a union-declared path still unmerged (a delete or rename conflict), is refused. Every path is classified before any is resolved. A refusal prints `REFUSED <branch>: conflict in <path>, <path>`.
- Then, with or without a conflict, the generator runs once more when it exists, through `_rb_regen_stage` (extracted from `_rb_final_regen`, see T1): a before/after record of tracked paths whose worktree copy changed (`git diff --name-only -z`) and of new untracked paths (`git ls-files -o --exclude-standard -z`), the marker scan over that set, then `git add -- <set>`. Never `add -u`, never `add -A`. A generator exit other than 0 prints `GENERATOR FAILED <branch>`; a marker hit prints `MARKERS <branch>: <paths>`.
- Every refusal after the merge started restores first: each path the helper itself wrote that is not unmerged is restored from the index (`git checkout -q -- <paths>`), a new untracked path it created is removed, then `git merge --abort`. That order matters: git 2.55 refuses `merge --abort` while an auto-merged, staged path has a different worktree copy (Grounding). The helper then checks HEAD is `<tip>` and `MERGE_HEAD` is gone, prints `     aborted; <branch> is back at <sha7>`, and returns 1. When the abort fails or HEAD is elsewhere it prints `ABORT FAILED <branch>: run git merge --abort in <wt>` and returns 2.
- `git commit --no-edit` records one merge commit, parents `<tip>` then `origin/<def>`. A refused commit (a commit hook) restores as above and prints `FAILED <branch>: the merge commit was refused`.
- `_union_dedupe_rows <wt> <tip>` runs after the commit, unchanged. Its failure returns 1 with its existing line; the merge commit stays, unpushed, and the caller undoes it (below).
- Success sets `MERGED_OID` to the new HEAD, prints `     merged origin/<def> into <branch>: <n> conflict(s) resolved, head <sha7> (was <sha7>)`, returns 0.

### `_verify_or_undo <wt> <branch> <tip> <cmd>`: the caller's check

- Runs `bash -c "<cmd>"` with `<wt>` as cwd, output to the terminal. `<cmd>` is trusted operator input: it comes only from the `--verify` flag on the command line, never from PR content, repo config or a `.kit.toml`, and it runs with the operator's own environment, the same as the hand loop it replaces. The helper sets no timeout; a caller that needs one wraps its command (`--verify 'gtimeout 900 bash tests/test-wrap.sh'`). macOS ships no `timeout`, so a built-in bound would need a new dependency.
- Exit 0 prints `     verified in <wt>: <cmd>`, returns 0.
- Any other exit prints `     VERIFY FAILED <branch>: <cmd> exited <rc> in <wt> after merging origin/<def>` and calls `_undo_local <wt> <branch> <tip>`.

### `_undo_local <wt> <branch> <tip>`: drop commits no remote holds

- Runs `git reset -q --keep <tip>`. It is only ever called on commits this run created and never pushed, so no pushed history changes. Success prints `     <branch> is back at <sha7>; nothing was pushed` and returns 1. A refused `reset --keep` (a leftover change conflicts) prints `     the local merge commit <sha7> stays on <branch>, never pushed; run git reset --keep <tip> in <wt>` and returns 2.

### `_push_ff <wt> <branch> <tip>`: the one push

- `git -C <wt> push origin HEAD:refs/heads/<branch>`. No `--force`, no `--force-with-lease`, no `+` in the refspec. The pushed commit descends from `<tip>`, so origin accepts it only as a fast-forward.
- A rejected push prints `     PUSH REFUSED: <branch> on origin moved past <sha7> (git exit <rc>)`, calls `_undo_local`, and returns its code. The next `land` then starts from the pushed tip again.
- It is the only push the merge path makes, in both callers.

### `wrap land <worktree> [--title T] [--body-file F] [--with-ci] [--verify <cmd>]`

- New flag `--verify <cmd>` (also `--verify=<cmd>`). A missing value exits 64, the same as `--title`.
- Every existing refusal and step is unchanged up to and including the first `_gh_merge_retry <n> <url> <tip>`. A PR that merges on that first call costs nothing new: no extra read, no wait.
- When that merge call fails, `land` reads the PR once: it polls `_pr_detail` every 2s until `headRefOid` equals `<tip>` and `mergeable` is not `UNKNOWN`, bounded by `KIT_WRAP_SETTLE_SECS` (a new head-pinned mode of `_pr_detail_settled`; it does not wait while CONFLICTING, so a real conflict is seen at once). Then:
  - An empty or unreadable read: `     MERGE FAILED #<n>: exit <rc>; the PR state is unreadable, nothing merged` and exit 2.
  - A head still not `<tip>` at the bound: `     MERGE FAILED #<n>: GitHub still shows head <sha7>, not the pushed <sha7>` and exit 2.
  - `mergeable` other than `CONFLICTING`: today's `MERGE FAILED #<n>: exit <rc>` and exit 2.
  - `CONFLICTING`: `     #<n> is CONFLICTING: merging origin/<def> into <branch>` and one merge cycle below.
- The merge cycle runs at most once per `land` call:
  1. `git fetch origin <def>`. When `origin/<def>` is already an ancestor of `<tip>`: `     <branch> already contains origin/<def>; GitHub's conflict is the union-blind case, run wrap merge --apply --pr <n>` and exit 2, no write.
  2. `_merge_default`. Return 1 or 2: one line `     PR #<n> left open`, exit 2.
  3. With `--verify`: `_verify_or_undo`. Return 1 or 2: `     PR #<n> left open`, exit 2.
  4. `_push_ff`. Return 1 or 2: exit 2.
  5. An INT or TERM from the start of step 2 to the end of step 4 aborts a merge still in progress, or calls `_undo_local` for an unpushed merge commit, then exits 130. The trap is cleared after the push.
  6. Re-read with `_pr_detail_settled <url> <n> <MERGED_OID> <tip>` (the existing pinned form, which waits while GitHub still serves the prior head or its old CONFLICTING verdict), printing `     waiting for GitHub to see <sha7>` once. Every exit from here on adds `the merge commit <sha7> is on origin` to its line:
     - head still `<tip>`: `     GitHub has not caught up with <sha7>; run wrap merge --apply --pr <n>`, exit 2;
     - any other head but `MERGED_OID`: `     PR #<n> head is <sha7>, another writer pushed; left open`, exit 2;
     - still `CONFLICTING`: `     #<n> is still CONFLICTING; run wrap merge --apply --pr <n>` (its squash fallback owns that case), exit 2.
  7. `tip=MERGED_OID`. Under `--with-ci`, the `ci` label sync and checks wait run again for the new head. Then `_gh_merge_retry <n> <url> <tip>`, and every step after it runs as today with that tip: `_tree_verify`, the ship record, the origin branch delete leased to `<tip>`, the pull, the worktree removal, the branch delete. A second merge failure is today's `MERGE FAILED`, exit 2, with no second cycle.

### `wrap merge [--apply] [--pr N] [--with-ci] [--verify <cmd>] <repo>`

- New flag `--verify <cmd>`, same parse and 64 rule. It applies only to the one bounded re-merge; a PR that needs no re-merge runs no command.
- `_remerge_push` keeps its fetch, its "already contains origin/<def>" refusal (which routes to the squash fallback), its dedupe, and its `REMERGE_OID` contract. Its `git merge --no-edit origin/<def>` with abort-on-any-conflict becomes `_merge_default`, then `_verify_or_undo` when `--verify` was given, then `_push_ff`. On a non-zero return it prints its existing line `     merging origin/<def> into <branch> conflicts beyond the union-marked files, aborted` after the helper's own line, and returns 1. In the scratch-worktree case the scratch worktree is still removed afterwards. The verify command in a scratch worktree runs without ignored files (no `node_modules`, no `.env`); the `VERIFY FAILED` line names the worktree so that case reads as what it is.

### Unchanged

`wrap rebase`'s behavior and output are unchanged (T1 only adds the explicit operation argument and extracts `_rb_regen_stage`). `_squash_fallback`, `_pr_gate`, `_tree_verify`, the dependents gate, and every other `land` and `merge` refusal are unchanged. Exit codes keep their meaning: 64 usage, 1 preflight refusal, 2 PR or merge failure, 3 tree mismatch, plus 130 for an interrupted merge cycle. No verb force-pushes.

## Picture

```
  wrap land <wt> [--verify C]                      wrap merge --apply [--verify C]
          |                                                  |
   push, open/adopt PR #n                          _pr_gate: SKIP not mergeable (CONFLICTING)
          |                                                  |
   gh pr merge --match-head-commit <tip> --ok--> (today)    v
          | refused                                  _union_remerge -> _remerge_push
          v                                                  |
   read PR pinned to <tip>: mergeable?                       |
     | not CONFLICTING -> MERGE FAILED (today)               |
     | CONFLICTING                                           |
     v                                                       v
   +--------------------------------------------------------------+
   | _merge_default   merge --no-ff --no-commit origin/<def>       |
   |                  unmerged -> _rb_stop op=merge (FEATURES,      |
   |                  pure-add CHANGELOG; else REFUSED)             |
   |                  _rb_regen_stage (generator, marker scan)      |
   |                  commit --no-edit (2 parents), dedupe rows     |
   | _verify_or_undo  bash -c C  --red--> _undo_local (reset --keep)|
   | _push_ff         push HEAD:refs/heads/<branch>, never forced   |
   |                  --rejected--> _undo_local                     |
   +--------------------------------------------------------------+
          |                                                  |
   re-read pinned to the merged head                 re-gate (today)
          |
   [ci label again] -> gh pr merge --match-head-commit <merged> -> _tree_verify -> tidy
```

## Design

Design-bearing: it adds a write path (a merge commit and a push) to `land`, and changes `merge`'s re-merge from abort-on-conflict to resolve-or-refuse.

### Approaches considered + chosen

| Approach | Tradeoff | Verdict |
|---|---|---|
| A. `land` merges `origin/<def>` into the branch after GitHub refuses the merge and reports CONFLICTING, through helpers shared with `merge`'s re-merge | Adds a merge commit to the PR branch. The squash merge flattens it, so the default branch history is unchanged. The happy path pays nothing. | Chosen |
| B. `land` calls `wrap rebase`, then `push --force-with-lease` | Linear branch, but a force-push on every conflict. The operator's rule forbids it without confirmation, and wrap's own contract says it never forces. | Rejected |
| C. `land` precomputes a local `git merge-tree` before the push | No network read, but git applies `merge=union` locally and GitHub does not, so a union-only divergence reads clean locally and CONFLICTING on the PR. | Rejected |
| D. Read `mergeable` before the first merge call | One settle poll on every land (a fresh PR reads UNKNOWN for seconds, Grounding), for the rare conflict. | Rejected (design critique, performance) |
| E. `land` hands a CONFLICTING PR to `wrap merge --apply --pr <n>` | `merge` does not remove the worktree, delete the branch, pull, or record the ship gate; `land` would need a second tidy path. | Rejected; `merge` gets the same helpers instead |
| F. A `[wrap] verify_cmd` knob instead of a flag | A root-only knob is one command for every repo; the kit's suite and a consumer's differ. The knob is the upgrade path if callers repeat one command. | Flag chosen |

### State of one conflicting land

```
                           merged
   PR #n --> MERGE_1 -------------------------------------> TIDY (today)
               | refused
               v
            READ (head == tip, not UNKNOWN) --not CONFLICTING / unreadable--> exit 2
               | CONFLICTING
               v
            FETCH --already contains origin/def--> exit 2 (use wrap merge)
               |
               v
            MERGE_DEFAULT --refused / markers / gen fail--> restore, merge --abort --> exit 2
               |                                  (abort failed --> exit 2, ABORT FAILED)
               v
            VERIFY (optional) --red--> reset --keep <tip> --> exit 2
               |
               v
            PUSH_FF --rejected--> reset --keep <tip> --> exit 2
               |          (INT/TERM anywhere above --> abort or reset --> exit 130)
               v
            RE_READ --tip still / foreign head / still CONFLICTING--> exit 2 (commit on origin)
               |
               v
            [CI_AGAIN] --> MERGE_2 --refused--> exit 2 (no second cycle)
                              | merged
                              v
                            TIDY (tree verify with the merged head)
```

### ADR link(s)

No ADR. The lasting rule, "wrap never forces a push", already stands in `lib/wrap/wrap.sh`'s header and `commands/wrap.md` "What this command does NOT do". This spec keeps it.

### Boundaries & failure modes

The helpers write only in the checkout they are given, only on `<branch>`: a merge commit, a dedupe commit, or a `reset --keep` of those same unpushed commits. They never touch the main checkout, never switch a branch, never rewrite a pushed commit. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes: the PR JSON fields `mergeable` (`MERGEABLE`, `CONFLICTING`, `UNKNOWN`) and `headRefOid` from `gh pr view --json` (sampled below); `origin/<def>`; `<wt>/lib/registry/feature-registry.sh generate` when present; the repo's `.gitattributes` through git itself; the `--verify` string from the command line.
- Produces: at most one merge commit and one dedupe commit on `<branch>`, one fast-forward push of `<branch>`, the report lines named in the Contract.
- Invariants: every commit the helpers create has `<tip>` as an ancestor; nothing that reached origin is ever rewritten; no path with a conflict-marker line is ever staged; a return of 1 leaves `<branch>` at `<tip>` with no merge in progress and a clean worktree; a return of 2 always names the command to run.

### Data model changes

None.

### API changes

`bin/wrap land` and `bin/wrap merge` each gain `--verify <cmd>`. Exit 130 is new, for an interrupted merge cycle.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: shared parts of the rebase code | `lib/wrap/wrap.sh`: `_rb_abort` and `_rb_stop` take an explicit operation argument (`rebase` default, `merge`), which picks `rebase --abort` or the restore-then-`merge --abort` path and the in-progress check; `_rb_regen_stage <wt> <gen>` extracted from `_rb_final_regen`, which keeps its commit | every existing rebase test green, output byte-identical |
| T2: `_merge_default`, `_verify_or_undo`, `_undo_local`, `_push_ff` | `lib/wrap/wrap.sh` | the Contract's helper rules, each testable on its own |
| T3: `land` | `lib/wrap/wrap.sh` `cmd_land`: `--verify` parse, the refused-merge read, the one merge cycle, the trap, the re-read, the tip swap, CI again | the Contract's `land` rules |
| T4: `merge` | `lib/wrap/wrap.sh` `cmd_merge` `--verify` parse, `_remerge_push` through the helpers | FEATURES and pure-add CHANGELOG conflicts resolve; a real conflict still aborts with the old line |
| T5: tests | `tests/test-wrap.sh` | every Test plan row passes |
| T6: docs | `lib/wrap/wrap.sh` header (verb lines, write-set paragraph), `bin/wrap` usage, `commands/wrap.md` (the `land` paragraph in step 3; step 10 names `wrap rebase` only for a branch never pushed), `docs/consumer-contract.md` `bin/wrap` row, `docs/CHANGELOG.md`, `docs/FEATURES.md` regenerated, `docs/implementation-notes/land-merge-default.md` | each flag and exit named once; `tests/test-meta.sh` green |

## Test plan

All cases reuse the land fixture (`build_land`: a bare origin, a clone, a worktree on `feat/land`) and the `gh` stub. Origin's main advances from a second clone after the branch commits. A conflicting case sets `GH_STUB_MERGE_FAILS=1` with a not-mergeable error so the first `pr merge` refuses, `GH_STUB_PR_42` to `{"mergeable":"CONFLICTING","headRefOid":"<old tip>", ...}` and `GH_STUB_PR_42_2` to `MERGEABLE` with `headRefOid` `%REMERGE_TIP%`. The generator is a stub `lib/registry/feature-registry.sh` that writes `docs/FEATURES.md` from a sorted file listing.

| Case | Setup | Expected |
|---|---|---|
| FEATURES conflict | both sides change `docs/FEATURES.md` and add a listed file | exit 0; one merge commit, parents (old tip, origin/main); FEATURES equals a fresh generate; the second `pr merge 42` carries `--match-head-commit <merge head>`; tree verified; old tip is an ancestor of the pushed head; no `rebase` entry in `git reflog` |
| Union-only divergence | both sides append to a `merge=union` file | exit 0; both lines kept once |
| CHANGELOG pure additions | both sides add a different bullet | exit 0; both bullets once, every base line kept |
| Clean merge still regenerates | origin adds a listed file, no textual conflict, the first merge refused as CONFLICTING | exit 0; FEATURES in the merge commit equals a fresh generate |
| Real conflict | both sides edit the same line of `base.txt` | exit 2; `REFUSED feat/land: conflict in base.txt`; HEAD equals old tip; no `MERGE_HEAD`; origin `feat/land` equals old tip; exactly one `pr merge` call |
| Mixed conflict | FEATURES and `base.txt` both unmerged | exit 2; names `base.txt` only; old tip restored |
| Markers left (negative control target) | stub generator is a no-op on a FEATURES conflict | exit 2; `MARKERS` names `docs/FEATURES.md`; old tip; no marker in any commit reachable from the branch or origin |
| Abort after a generator side effect | clean auto-merge of `README.md`; the stub generator rewrites `README.md`, then exits 3 | exit 2; `GENERATOR FAILED`; old tip; no `MERGE_HEAD`; worktree clean (the restore-then-abort order) |
| Generator fails | stub exits 3 on a FEATURES conflict | exit 2; `GENERATOR FAILED`; old tip |
| Untracked generator output | the stub also writes a new untracked file | the file is in the merge commit; worktree clean |
| Verify green | `--verify 'test -f docs/FEATURES.md'` | exit 0; `verified in` line before the push |
| Verify red | `--verify false` | exit 2; `VERIFY FAILED` names the worktree; HEAD equals old tip; origin branch equals old tip; one `pr merge` call |
| Push rejected | the `--verify` command itself pushes a new commit to origin `feat/land` from a second clone | exit 2; `PUSH REFUSED`; HEAD back at old tip; origin keeps the other clone's commit; no push call in the run carries `--force`, `--force-with-lease` or a `+` refspec |
| Interrupted | a `--verify` that sends TERM to the land process | exit 130; old tip; no `MERGE_HEAD` |
| Already contains origin/main | branch merged origin/main before land; the first merge refused as CONFLICTING | exit 2; names `wrap merge --apply --pr 42`; no new commit |
| Still CONFLICTING after push | every view after the push answers CONFLICTING at the merged head | exit 2; names `wrap merge --apply --pr 42` and the merge commit on origin; exactly one `pr merge` call |
| GitHub not caught up | every view after the push answers the old tip | exit 2; `has not caught up` |
| Foreign head after push | the re-read answers a third head | exit 2; `another writer pushed` |
| Unreadable PR after a refused merge | `pr view` prints nothing | exit 2; `unreadable`; no merge commit |
| Refused but not conflicting | the first merge refused, the read answers MERGEABLE | exit 2, today's `MERGE FAILED`; no merge commit |
| Happy path cost | not conflicting, first merge succeeds | exit 0, today's output; zero `pr view 42` calls before the merge |
| Adopted conflicting PR | an open own PR on the branch | the same merge cycle runs on the adopted PR |
| `--with-ci` conflicting | label-gated repo, conflicting | the label sync and checks wait run once before the first merge and again for the merged head |
| merge re-merge, FEATURES | `wrap merge --apply` on a CONFLICTING own PR with a FEATURES conflict | the re-merge pushes and the PR merges (today it aborts) |
| merge re-merge, real conflict | same-line conflict | the existing `conflicts beyond the union-marked files, aborted` line plus `REFUSED`; nothing pushed |
| merge --verify red | `wrap merge --apply --verify false` | nothing pushed; the PR stays open |
| Usage | `land --verify` and `merge --verify` with no value | exit 64 |
| Help | `wrap --help` and `bin/wrap` header | both name `--verify` |
| Every existing land, merge, rebase case | unchanged fixtures | still green, with no fixture weakened |

Negative control: `lib/gate/negctl.sh` mutates the `land` trigger so the CONFLICTING comparison never matches. The FEATURES conflict case must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<mutation script>"` reports PASS. `bash tests/test-meta.sh` exits 0. `RUN_ALL_TIMEOUT_SECS=1500 bash tests/run-all.sh --changed` exits 0.

## After state

- [ ] `wrap land` on a CONFLICTING own PR whose conflicts are all generated, union-declared or pure-add CHANGELOG merges `origin/<default>` into the branch, pushes without force, and lands it. (Today: `MERGE FAILED #<n>: exit 1`, exit 2.) Checkable by the FEATURES conflict case.
- [ ] A real content conflict makes `land` exit 2 naming the path, with the branch at its pushed tip, a clean worktree, and nothing pushed. Checkable by the Real conflict case.
- [ ] `wrap land --verify <cmd>` and `wrap merge --verify <cmd>` run the caller's command after the merge and push nothing on red. Checkable by the Verify red cases.
- [ ] `wrap merge --apply` resolves a FEATURES conflict in its re-merge instead of aborting. (Today: aborts.)
- [ ] A land that merges on its first call makes no extra `gh pr view` call. Checkable by the Happy path cost case.
- [ ] No `git push` added by this spec carries `--force`, `--force-with-lease` or a `+` refspec. Checkable by `git diff origin/master -- lib/wrap/wrap.sh | grep -E '^\+.*push' | grep -E 'force|:\+|origin \+'` printing nothing.

## Edge Cases

1. GitHub still computing mergeability when the first merge is refused: the head-pinned read waits while `UNKNOWN` or while the head is not yet `<tip>`, bounded; at the bound `land` exits 2 by name.
2. An adopted PR whose old head GitHub still serves right after `land`'s push: the first merge refuses on `--match-head-commit`; the read waits for the head to reach `<tip>` before trusting `mergeable`, so a stale CONFLICTING never triggers a merge.
3. A branch that already merged `origin/<def>` but GitHub still calls CONFLICTING: no second merge, exit 2 routing to `merge`'s squash fallback.
4. `docs/FEATURES.md` changed only on origin, with no conflict: `_rb_regen_stage` regenerates it inside the merge commit, the same as the hand loop.
5. Two branches flipped the same kanban row in a union-declared board: `_union_dedupe_rows` drops the duplicate in a follow-up commit, as `merge` does today; both commits are pushed together.
6. The verify command dirties the worktree: `reset --keep` keeps those changes when it can and `land` returns 2 naming them when it cannot. Nothing was pushed either way.
7. A consumer repo without `lib/registry/feature-registry.sh`: FEATURES is an ordinary file; a conflict on it is refused by name, and no generator pass runs.
8. A commit hook rejects the merge commit: restore, abort, named; the branch is back at its tip.
9. Ten stacked PRs landed one after another: each `land` runs at most one merge cycle; each merge moves the default and the next PR conflicts again, costing one cycle and one CI run each. `wrap merge --apply` and `wrap land` never loop.
10. The operator presses Ctrl-C during a long `--verify`: the trap resets the unpushed merge commit and exits 130.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Real content conflict | an unmerged path outside the handled classes | restore, `merge --abort`, `REFUSED` names every path, HEAD at the old tip, exit 2, PR left open |
| Generator rewrites an auto-merged staged file, then fails | `merge --abort` would refuse (Grounding) | restore the helper's own writes from the index first, then abort |
| Generator no-op or partial write | marker scan over the exact stage set | restore, abort, `MARKERS` |
| Generator exits non-zero | exit code | restore, abort, `GENERATOR FAILED` |
| Verify red | the command's exit code | `reset --keep <tip>` of the unpushed commit; nothing pushed |
| Verify hangs | none in wrap | the caller bounds its own command; Ctrl-C runs the trap |
| Push rejected (origin branch moved) | push exit code | `reset --keep <tip>`, `PUSH REFUSED`; never forced |
| GitHub lags after the push | head still the prior one at the bound | exit 2, `has not caught up`, commit named as on origin |
| GitHub still CONFLICTING after the push | re-read `mergeable` | exit 2, routed to `wrap merge --apply --pr <n>` |
| Foreign head after the push | re-read `headRefOid` | exit 2, `another writer pushed` |
| PR read fails (auth, rate limit) | empty JSON after a refused merge | exit 2, `unreadable`, no merge commit |
| Abort itself fails | exit code, HEAD, `MERGE_HEAD` | return 2, `ABORT FAILED ... run git merge --abort in <wt>` |
| rerere replays an old resolution | none needed | `-c rerere.enabled=false` on the merge |
| Squash merge pinned to a stale head | `--match-head-commit` gets the merged head | GitHub refuses a mismatch, as today |

## Out of Scope

- A refusal in `wrap rebase` for a branch already on origin. The rebase stays for a branch never pushed (`commands/wrap.md` step 10 before its first push); this spec only documents that.
- `land` running `merge`'s squash fallback itself. It names the command instead.
- A second generated file. The `ponytail:` note on `_RB_GENERATED` keeps the knob as the upgrade path.
- A `[wrap] verify_cmd` knob (Design, approach F), and a built-in verify timeout.
- Renaming the `_RB_*` and `_rb_*` names to neutral ones now that two verbs share them: churn with no behavior.

## Grounding

### Live sample: the PR `mergeable` field

Read-only, `dwarvesf/dwarves-kit`, 2026-09-30:

```
$ gh pr view 444 --json number,mergeable,mergeStateStatus,headRefOid,baseRefName
{"baseRefName":"master","headRefOid":"ba6200e4…a749bb9a","mergeStateStatus":"DIRTY","mergeable":"CONFLICTING","number":444}
```

The first `gh pr list --json mergeable` a few seconds earlier answered `"mergeable":"UNKNOWN"` for the same PR. That lag is why a pre-merge read would cost every land a settle wait, and why the read runs only after a refused merge.

### Live sample: today's `land` on a CONFLICTING PR

A scratch repo: a bare origin, a clone, a worktree on `feat/land` that edits `base.txt`, then origin's main edits the same line from a second clone. `gh` is stubbed to answer the way GitHub answers such a PR. Real git throughout.

```
== local merge-tree check:
base.txt
CONFLICT (content): Merge conflict in base.txt
merge-tree rc=1
== today's wrap land:
land feat/land -> main (.../repo/wt)
     pushed feat/land (4dc0eac)
     opened PR #42
X Pull request o/r#42 is not mergeable: the merge commit cannot be cleanly created.
     MERGE FAILED #42: exit 1
land rc=2
== worktree after:
4dc0eac feat: the landed change
feat/land
```

The branch is pushed, the PR is open, and `land` stops. The `gh pr merge` refusal text is the stub's copy of GitHub's message; it was not sampled from a real merge, because a real merge attempt is a write.

### Live sample: `merge --abort` after a generator side effect

git 2.55, scratch repo: `merge --no-ff --no-commit` auto-merges `f` (staged) and conflicts on `k`; then `f` is rewritten in the worktree, as a generator would.

```
-- mid-merge status:
M  f
UU k
-- abort with auto-merged f rewritten:
error: Entry 'f' not uptodate. Cannot merge.
fatal: Could not reset index file to revision 'HEAD'.
rc=128
-- restore f from the index, then abort:
rc=0
5b280b0 br
no merge in progress
```

This is why every refusal restores the helper's own writes from the index before `merge --abort`.

### Dry trace: the negative control

- Mutation: in `cmd_land`, the trigger comparison `[ "$m" = "CONFLICTING" ]` after the refused merge becomes `[ "$m" = "CONFLICTING-NEVER" ]`.
- Fixture reads: the FEATURES conflict case sets `GH_STUB_MERGE_FAILS=1` and `GH_STUB_PR_42` to a CONFLICTING JSON at the old tip.
- Code path under mutation: the first merge is refused, the read returns CONFLICTING, the trigger does not match, and `land` prints today's `MERGE FAILED #42` and exits 2.
- Red tests: `land-merge: FEATURES conflict exits 0` and `land-merge: HEAD is a merge of origin/main` (a two-parent commit whose second parent is origin/main) both fail.

### Dry trace: the markers case

- Mutation (the fixture itself): the stub generator exits 0 and writes nothing, so git's conflict markers stay in `docs/FEATURES.md`.
- Code path: `_rb_stop op=merge` classifies FEATURES as generated, runs the no-op generator, builds the stage set, `_rb_markers` finds the `<<<<<<<` and `>>>>>>>` lines, the helper restores and aborts.
- Red test if the scan were removed: `land-merge: no marker in any commit` finds `+<<<<<<<` in `git log -p`.

### Dry trace: verify red

- Fixture: `--verify false`, the FEATURES conflict fixture.
- Code path: the merge commit is made, `bash -c false` exits 1, `_undo_local` runs `reset --keep <tip>`, `land` exits 2 before `_push_ff`.
- Red test if the undo were skipped: `land-merge: verify red restores the old tip` fails on `rev-parse HEAD`.

### Dry trace: push rejected

- Fixture: a `--verify` command that commits to origin `feat/land` from a second clone.
- Code path: verify exits 0, `_push_ff` is rejected as a non-fast-forward, `_undo_local` resets to `<tip>`, exit 2.
- Red test if a `+` or `--force` crept into the push: `land-merge: push rejected keeps the other clone's commit` fails, because origin would hold the merge commit.

### Unsampled

GitHub's `mergeable` after a push of a merge commit that already contains the base is not sampled here. `_squash_fallback`'s comment records that GitHub has kept `CONFLICTING` in that state before; the Contract routes that case to `wrap merge --apply --pr <n>` and does not assume it clears.

## Design critique
Date: 2026-09-30
Design source: SPEC-374 `## Contract` and `## Design` (first draft, commit `bfe47629`)
Lenses run: simplicity, performance, boundaries/composability, data-model & correctness, operability/failure-modes, plus `kit:advisor` over-suggest; missing: none

### High findings
1. The pre-merge `mergeable` read put a settle poll on every land, up to 60s. -- found by: performance -- fix: folded; the read runs only after the first merge is refused.
2. `merge --abort` fails once a generator rewrites an auto-merged staged path. -- found by: correctness (reproduced, Grounding) -- fix: folded; restore the helper's own writes from the index before the abort.
3. A rejected push or an interrupted verify left a diverged, unpushed merge commit with no recovery. -- found by: correctness, operability, advisor -- fix: folded; `_undo_local` on a rejected push, an INT/TERM trap, exit 130.
4. The first read was not pinned to the pushed tip, so a stale CONFLICTING on an adopted PR could trigger a needless merge. -- found by: correctness -- fix: folded; the read waits for `headRefOid == <tip>`.
5. `_merge_default` mixed merge, verify and rollback, and T1 made `_rb_abort` sniff `MERGE_HEAD`. -- found by: boundaries -- fix: folded; four single-purpose helpers, an explicit operation argument, `_rb_regen_stage` extracted, distinct return codes 1 and 2.
6. `--verify` has no timeout. -- found by: performance, operability, advisor -- fix: partly folded; the helper documents that the caller bounds its command, because macOS ships no `timeout`; Ctrl-C runs the trap.
7. Cut `--verify` and the `merge` rewiring as speculative. -- found by: simplicity -- not folded: both are named in the operator's item.

### Medium findings
1. A failed PR read fell through silently. -- operability -- folded: `unreadable` exit 2.
2. The post-push re-read gave a misleading "foreign head" for GitHub lag. -- operability -- folded: separate `has not caught up` line, and every post-push exit names the merge commit on origin.
3. `--with-ci` needs a second CI cycle after the push. -- performance -- folded: the label sync and wait run again for the merged head.
4. Untracked generator output escaped the stage set. -- correctness -- folded: new untracked paths are recorded and staged after the scan.
5. `PUSH REFUSED` exited with git's code (1 or 128). -- correctness -- folded: exit 2, git's code in the line.
6. The verify command is a trust boundary. -- advisor -- folded: stated in the helper contract.
7. Scratch-worktree verify runs without ignored files. -- operability -- folded: stated, and the `VERIFY FAILED` line names the worktree.
8. Stacked landings: make "one cycle per call" explicit. -- advisor -- folded, Edge case 9.
9. Too many post-push guards. -- simplicity -- not folded: GitHub serves the old verdict for 10 to 20s after a push, so the pinned re-read is what lets the second merge succeed.

### Low findings
1. Rename the `_rb_*` names now they are shared. -- boundaries -- Out of Scope.
2. `_remerge_push` refetches `origin/<def>`. -- performance -- not folded: one fetch, and it keeps the helper's precondition honest.

### Scores
- Simplicity: 5/10
- Performance: 5/10
- Boundaries/composability: 5/10
- Data-model & correctness: 5/10
- Operability/failure-modes: 6/10

### Verdict: REVISE
Folded above; the revised Contract is what validation reads.

## Decision Log

- DEC-1: merge, never rebase, for a branch that is already on origin. A rebase needs a force-push; a merge commit is flattened by the squash merge anyway.
- DEC-2: the trigger is GitHub's refusal plus its `mergeable`, not a local `merge-tree`, because git applies `merge=union` and GitHub does not.
- DEC-3: the read runs after a refused merge, so a land that needs no merge pays nothing.
- DEC-4: one set of helpers for `land` and `merge`'s re-merge, built on the rebase's `_rb_*` classifier with an explicit operation argument, so the three verbs resolve conflicts by one rule set.
- DEC-5: `--verify` is a flag, not a knob, and wrap does not bound it.
- DEC-6: a red verify or a rejected push undoes the local merge commit with `reset --keep`. That commit never reached a remote, so no pushed history changes.

## Open questions

(none)
