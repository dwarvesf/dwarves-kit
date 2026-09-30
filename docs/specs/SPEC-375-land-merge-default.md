# SPEC-375: wrap land merges the default branch into a conflicting own PR instead of stopping

**Status:** VALIDATED
Lane: full
Type: spec-feature
**Proof:** `docs/verification/land-merge-default.md`; `tests/test-wrap.sh`, the land-merge block.
References: `lib/wrap/wrap.sh` `cmd_rebase` and its `_rb_*` helpers (SPEC-329): the stop classifier, the CHANGELOG pure-addition resolver, the exact stage set and the marker scan this spec reuses. `_remerge_push` and `_union_dedupe_rows` (the `wrap merge` re-merge): the merge-not-rebase shape, the "already contains origin/<def>" guard, and the union-row dedupe.

## Problem

`wrap land <worktree>` pushes the branch, opens or adopts the PR, then calls `gh pr merge --squash --match-head-commit`. When `origin/<default>` moved on and the PR is CONFLICTING, GitHub refuses the merge and `land` exits 2 with `MERGE FAILED #<n>: exit 1`. The only verb that moves a branch past the default is `wrap rebase`, which rewrites history. The branch is already on origin, so the rebased branch needs a force-push, and the operator's rule forbids a force-push without confirmation.

In one session this happened four times. Each time the lead ran the same loop by hand in the worktree: `git merge --no-edit origin/<default>`, regenerate `docs/FEATURES.md` with the repo's own generator, rerun the tests, push normally, run `wrap land` again. The loop never needed a rebase, and it never needed a force.

`wrap merge --apply` already re-merges `origin/<default>` into a conflicting own PR (`_remerge_push`), but it aborts on any conflict git's union driver does not resolve, so a `docs/FEATURES.md` or `docs/CHANGELOG.md` conflict stops it too.

## Contract

One sequence, `_merge_verify_push`, owns the merge cycle for both callers, and its trap. It is built from small helpers, each with one job. Every helper returns 0 on success, 1 when it refused and left `<branch>` exactly at `<tip>` with no merge in progress and a clean worktree (`status --porcelain --untracked-files=all` empty), and 2 when it could not restore that state (its line names the paths or the command a human runs). `_merge_default` also returns 5 for a refused conflict after a clean restore, so `merge` can word that case without parsing output; 5 carries the same state guarantee as 1. A caller never turns a 2 into a 1.

### `_rb_resolve <wt> <gen> <unmerged path>...`: classify and resolve (extracted, T1)

- Extracted from `_rb_stop` without a behavior change: every path is classified first with the rebase rules (`docs/FEATURES.md` with a generator present is regenerated; `docs/CHANGELOG.md` is kept both sides only when both sides purely added lines; anything else, including a union-declared path still unmerged, is refused). On any refused path it prints the existing per-path text unchanged (`conflict in <path>, <path>`, a union-declared path keeping its ` (merge=union, delete/rename conflict)` suffix) to its caller and writes nothing (return 1). Else it writes the CHANGELOG union and runs the generator once if FEATURES was unmerged (a generator failure returns 3, having written the CHANGELOG only).
- `_rb_stop` calls it and keeps its own lines, abort and stage set, so `wrap rebase` output stays byte-identical. `_rb_abort` and `_rb_final_regen` are untouched.
- `_rb_markers` reads each path's `conflict-marker-size` with `git check-attr` (default 7) and matches exactly that many marker characters, `^(<{N}|>{N}|\|{N})( |$)`. For a path with no attribute the pattern is today's, so rebase output is unchanged; a merged-in size of 9 or 5 is still caught.

### `_merge_default <wt> <branch> <def> <tip> <gen>`: merge, resolve, commit

- Preconditions, each a return 1 with one line and no write: HEAD is `<tip>`; `status --porcelain --untracked-files=all` is empty (no tracked change, no untracked file, whatever `status.showUntrackedFiles` says); no merge, rebase or cherry-pick in progress; `_write_guard` passes; `origin/<def>` is not an ancestor of `<tip>`. Because the checkout starts fully clean, every change in it after the merge starts is the merge's or the helper's own. That is what makes the stage set and the restore set exact without a before/after record.
- It runs `git merge --no-ff --no-commit origin/<def>` through `_rb_git` (`GIT_EDITOR=true`, `-c rerere.enabled=false`). It never runs `git rebase` and never pushes.
- Unmerged paths go to `_rb_resolve`. Return 1 prints `REFUSED <branch>: conflict in <paths>`, runs `_merge_restore`, and returns 5 when that restore returned 1; return 3 prints `GENERATOR FAILED <branch>` and runs `_merge_restore`.
- Then the generator runs once more when `<gen>` is non-empty, so a merge with no conflict still carries a fresh `docs/FEATURES.md`. A failure prints `GENERATOR FAILED <branch>` and runs `_merge_restore`.
- The stage set: every unmerged path, plus `git diff --name-only -z` (tracked worktree copies that differ from the index), plus `git ls-files -o --exclude-standard -z` (new untracked paths, generator output included). It is marker-scanned with `_rb_markers`; a hit prints `MARKERS <branch>: <paths>` and runs `_merge_restore`. Then `git add -- <set>`, never `add -u`, never `add -A`.
- `git commit -q -m "chore(merge): merge origin/<def>"`, a conventional subject so a commit-msg hook in a consumer repo accepts it. Parents are `<tip>` then `origin/<def>`. A refused commit prints `FAILED <branch>: the merge commit was refused` and runs `_merge_restore`.
- `_union_dedupe_rows <wt> <tip>` runs after the commit, unchanged. When it fails, `_merge_default` owns the cleanup: it restores the staged dedupe paths from HEAD (`git restore --staged --worktree --source=HEAD -- <paths>`), then runs `_undo_local`, and returns that code.
- Success sets `MERGED_OID` to the new HEAD and prints `     merged origin/<def> into <branch>: <n> conflict(s) resolved, head <sha7> (was <sha7>)`, return 0.

### `_merge_restore <wt> <branch> <tip>`: undo a merge still in progress

- Reads the state, never a flag, so the trap can call it too. Every path the merge left changed that is not unmerged is restored from the index (`git checkout -q -- <paths>`), then each new untracked path is removed with `rm -f -- "<wt>/<path>"` (NUL-delimited, never `-r`, never `git clean`; the checkout started with no untracked file, so none of them predates the merge). Then `git merge --abort`. The order matters: git 2.55 refuses `merge --abort` while an auto-merged, staged path has a different worktree copy (Grounding).
- It checks HEAD is `<tip>`, `MERGE_HEAD` is gone and `status --porcelain --untracked-files=all` is empty, prints `     aborted; <branch> is back at <sha7>`, returns 1. Otherwise `ABORT FAILED <branch>: run git merge --abort in <wt>`, return 2.

### `_verify_or_undo <wt> <branch> <tip> <cmd>`: the caller's check

- Runs `bash -c "<cmd>"` with `<wt>` as cwd, output to the terminal. `<cmd>` is trusted operator input: it comes only from the `--verify` flag on the command line, never from PR content, repo config or a `.kit.toml`, and it runs with the operator's own environment, the same as the hand loop it replaces. The string is echoed as typed in the report lines, so a secret belongs in the environment, not in the flag; `bin/wrap` usage says so. The helper sets no timeout; a caller that needs one wraps its command (`--verify 'gtimeout 900 bash tests/test-wrap.sh'`). macOS ships no `timeout`.
- Exit 0 with HEAD still `MERGED_OID` and no tracked file changed prints `     verified in <wt>: <cmd>`, returns 0.
- Any other exit, an exit 0 that left a tracked file changed, or a HEAD that moved (a verify that commits; the pushed tree would not be the verified tree), prints `     VERIFY FAILED <branch>: <cmd> exited <rc> in <wt> after merging origin/<def>` (or `changed tracked files`) and runs `_undo_local`.

### `_undo_local <wt> <branch> <tip>`: drop commits no remote holds

- Runs `git reset -q --keep <tip>`. It only ever runs on commits this run made and origin does not hold. `reset --keep` keeps a change the verify command made to a file the merge did not touch, and any untracked file it left, so after the reset the helper checks `status --porcelain --untracked-files=all`: empty prints `     <branch> is back at <sha7>; nothing was pushed` and returns 1; anything left prints `     <branch> is back at <sha7>, nothing was pushed, but <wt> holds changes this run did not make: <paths>` and returns 2. A refused reset prints `     the local merge commit <sha7> stays on <branch>, not pushed; run git reset --keep <tip> in <wt>` and returns 2.

### `_push_ff <wt> <branch> <tip>`: the one push

- `git -C <wt> push origin HEAD:refs/heads/<branch>`. No `--force`, no `--force-with-lease`, no `+` in the refspec. The pushed commit descends from `<tip>`, so origin accepts it only as a fast-forward.
- A non-zero push is judged by what origin holds, never by the exit code alone: `git ls-remote origin refs/heads/<branch>`.
  - It shows `MERGED_OID`: the push landed (a dropped connection after the update); treated as success.
  - It shows `<tip>`: `     PUSH REFUSED: git push exited <rc>; origin still holds <sha7>`, then `_undo_local`.
  - It shows another commit: `     PUSH REFUSED: <branch> on origin moved to <sha7>`, then `_undo_local`.
  - The read fails, or answers nothing (the branch is gone on origin): `     PUSH FAILED: git push exited <rc> and origin could not be read; the merge commit <sha7> may be on origin, check before re-running`, return 2, no reset.

### `_merge_verify_push <wt> <branch> <def> <tip> <gen> [<cmd>]`: the sequence both callers run

1. `git fetch origin <def>`. A failure prints `     fetch origin <def> failed; nothing merged`, return 1.
2. When `origin/<def>` is already an ancestor of `<tip>`: return 4 with no write and no line (each caller words its own routing).
3. `_merge_default`, then `_verify_or_undo` when `<cmd>` is given, then `_push_ff`. The first non-zero return is the sequence's return.
4. A handler on INT, TERM and HUP is installed before step 3; the caller's prior handlers are saved with `trap -p` and restored after `_push_ff` returns. The handler's first line ignores the three signals, so a second Ctrl-C cannot re-enter it. It sets a flag and cleans up by state, never with a network call before the push started: `MERGE_HEAD` present runs `_merge_restore`; staged dedupe rows are restored from HEAD first; HEAD not `<tip>` with the push not yet started runs `_undo_local`; with the push started it reads `ls-remote` once and follows `_push_ff`'s rules (a failed read resets nothing and prints the `PUSH FAILED` line). The sequence then returns 130, or 2 when the cleanup returned 2. It never calls `exit` itself: each caller removes what it owns (the scratch worktree in `merge`) and then exits with that code.

### `_pr_detail_at_head <url> <n> <tip>`: the read after a refused merge (new, T3a)

- Polls `_pr_detail` every 2s until `headRefOid` equals `<tip>` and `mergeable` is not `UNKNOWN`, bounded by `KIT_WRAP_SETTLE_SECS`, and returns the last read. It does not wait while `CONFLICTING`, so a real conflict is seen at once. `_pr_detail_settled` is unchanged.

### `wrap land <worktree> [--title T] [--body-file F] [--with-ci] [--verify <cmd>]`

- New flag `--verify <cmd>` (also `--verify=<cmd>`). A missing value exits 64, the same as `--title`.
- Every existing refusal and step is unchanged up to and including the first `_gh_merge_retry <n> <url> <tip>`. A PR that merges on that first call costs nothing new: no extra read, no wait.
- When that merge call fails, `land` reads `_pr_detail_at_head <url> <n> <tip>`:
  - empty or unreadable: `     MERGE FAILED #<n>: exit <rc>; the PR state is unreadable, nothing merged`, exit 2;
  - head still not `<tip>` at the bound: `     MERGE FAILED #<n>: GitHub still shows head <sha7>, not the pushed <sha7>`, exit 2;
  - `mergeable` other than `CONFLICTING`: today's `MERGE FAILED #<n>: exit <rc>`, exit 2;
  - `CONFLICTING`: `     #<n> is CONFLICTING: merging origin/<def> into <branch>`, then one merge cycle.
- `--verify` runs only inside a merge cycle; a land that merges on its first call runs no command. `bin/wrap` usage says so.
- The merge cycle runs at most once per `land` call. `land` calls `_merge_verify_push <wt> <branch> <def> <tip> <gen> [<cmd>]`, where `<gen>` is `<wt>/lib/registry/feature-registry.sh` when it exists (the same trust as `wrap rebase`: the operator's own checkout).
  - Return 4: `     <branch> already contains origin/<def>; GitHub's conflict is the union-blind case, run wrap merge --apply --pr <n>`, exit 2.
  - Return 1, 2 or 5: `     PR #<n> left open`, exit 2. Return 130: exit 130.
- After the push, `land` re-reads with `_pr_detail_settled <url> <n> <MERGED_OID> <tip>` (the existing pinned form, which waits while GitHub still serves the prior head or its old CONFLICTING verdict), printing `     waiting for GitHub to see <sha7>` once. Every exit from here on ends its line with `; the merge commit <sha7> is on origin`:
  - empty read: `     #<n> is unreadable after the push`, exit 2;
  - head still `<tip>`: `     GitHub has not caught up with <sha7>; run wrap merge --apply --pr <n>`, exit 2;
  - any other head but `MERGED_OID`: `     PR #<n> head is <sha7>, another writer pushed; left open`, exit 2;
  - still `CONFLICTING`: `     #<n> is still CONFLICTING; run wrap merge --apply --pr <n>` (its squash fallback owns that case), exit 2.
- Then `tip=MERGED_OID`. Under `--with-ci` the `ci` label sync and `_ci_checks_wait` run again for the new head, as today. Without `--with-ci`, a pending-only wait runs instead: it reads the head's check rollup every 10s while any entry is pending, bounded by `KIT_WRAP_CARRY_CHECKS_SECS`, and holds no grace when no check reports, so a repo whose push starts no checks pays nothing. Either way, when any check on `MERGED_OID` concluded `FAILURE`, `ERROR`, `CANCELLED` or `TIMED_OUT`, `land` prints `     checks failed on the merged head <sha7>: <names>; the merge commit is on origin` and exits 2 before the second merge, so a clean textual merge that broke the build never lands. Then `_gh_merge_retry <n> <url> <tip>`, and every step after it runs as today with that tip: `_tree_verify`, the ship record, the origin branch delete leased to `<tip>`, the pull, the worktree removal, the branch delete. A second merge failure prints `     MERGE FAILED #<n>: exit <rc> after the merge cycle; once its checks pass, run wrap merge --apply --pr <n>; the merge commit <sha7> is on origin`, exit 2, with no second cycle.

### `wrap merge [--apply] [--pr N] [--with-ci] [--verify <cmd>] <repo>`

- New flag `--verify <cmd>`, same parse and 64 rule. It applies only to the one bounded re-merge; a PR that needs no re-merge runs no command.
- `_union_remerge` keeps its checkout selection, its head checks, and its scratch-worktree creation. `_remerge_push` keeps its "already contains origin/<def>" refusal and its `REMERGE_OID` contract, and calls `_merge_verify_push` in place of its own merge, dedupe and push:
  - return 4: its existing `already contains origin/<def>, so a re-merge cannot clear the conflict` line, return 1 (the squash fallback runs, as today);
  - return 5: its existing `merging origin/<def> into <branch> conflicts beyond the union-marked files, aborted` line, return 1 (the squash fallback's own guard refuses, because the head does not contain origin/<def>);
  - return 1: return 1 with the helper's line only;
  - return 2: return 2. `cmd_merge` then skips the squash fallback, prints `FAILED merge #<n>: the re-merge left <wt> needing a human`, and exits 2;
  - return 130: `_union_remerge` drops its scratch worktree when it made one, then `wrap merge` exits 130.
- `<gen>` in the `merge` path is decided by `_remerge_push` after its own fetch and before the sequence starts: the worktree's generator only when `git -C <wt> diff --quiet <tip> origin/<def> -- lib/registry/feature-registry.sh` holds (the branch and the default branch carry the same generator); otherwise `<gen>` is empty and a FEATURES conflict is refused by name. This is conservative: a generator changed only on origin is refused too, until the branch holds it. `merge` runs unattended under `/kit:wrap` step 3 and `wrap.autoland_carry`, on a branch someone else can push to, so it does not run a generator the two sides disagree on. Git hooks still run on the merge commit and the push exactly as they do today; this rule is about the generator only, not a general guarantee that no branch code runs.

### Unchanged

`wrap rebase`'s behavior and output are byte-identical for every path without a `conflict-marker-size` attribute (T1 only extracts `_rb_resolve` and makes the marker scan read that attribute). `_squash_fallback`, `_pr_gate`, `_pr_detail_settled`, `_tree_verify`, the dependents gate, and every other `land` and `merge` refusal are unchanged. Exit codes keep their meaning: 64 usage, 1 preflight refusal, 2 PR or merge failure, 3 tree mismatch, plus 130 for an interrupted merge cycle. No verb force-pushes.

## Picture

```
  wrap land <wt> [--verify C]                      wrap merge --apply [--verify C]
          |                                                  |
   push, open/adopt PR #n                          _pr_gate: SKIP not mergeable (CONFLICTING)
          |                                                  |
   gh pr merge --match-head-commit <tip> --ok--> (today)    v
          | refused                                  _union_remerge -> _remerge_push
          v                                          (gen only if it matches origin/<def>)
   _pr_detail_at_head <tip>: mergeable?                      |
     | not CONFLICTING / unreadable -> exit 2                |
     | CONFLICTING                                           |
     v                                                       v
   +--------------------------------------------------------------+
   | _merge_verify_push   (fetch; already contains? -> 4; trap)   |
   |   _merge_default     merge --no-ff --no-commit origin/<def>   |
   |                      unmerged -> _rb_resolve (FEATURES,       |
   |                      pure-add CHANGELOG; else REFUSED)        |
   |                      generator again; stage set from a clean  |
   |                      start; marker scan; commit; dedupe rows  |
   |                      any refusal -> _merge_restore            |
   |   _verify_or_undo    bash -c C  --red--> _undo_local          |
   |   _push_ff           push HEAD:refs/heads/<branch>, no force   |
   |                      non-zero -> ls-remote decides            |
   +--------------------------------------------------------------+
          |                                   4 -> already contains line -> squash fallback (today)
          |                                   5 -> REFUSED + old line -> squash fallback refuses
          |                                   2 -> skip squash fallback, exit 2
          |                                   0 -> re-gate (today)
   re-read pinned to the merged head
          |
   [ci label + wait again | pending-only wait] -> failed check? exit 2 -> gh pr merge --match-head-commit <merged>
          -> _tree_verify -> tidy
```

## Design

Design-bearing: it adds a write path (a merge commit and a push) to `land`, and changes `merge`'s re-merge from abort-on-conflict to resolve-or-refuse.

### Approaches considered + chosen

| Approach | Tradeoff | Verdict |
|---|---|---|
| A. `land` merges `origin/<def>` into the branch after GitHub refuses the merge and reports CONFLICTING, through one sequence shared with `merge`'s re-merge | Adds a merge commit to the PR branch. The squash merge flattens it, so the default branch history is unchanged. The happy path pays nothing. | Chosen |
| B. `land` calls `wrap rebase`, then `push --force-with-lease` | Linear branch, but a force-push on every conflict. The operator's rule forbids it without confirmation, and wrap's own contract says it never forces. | Rejected |
| C. `land` precomputes a local `git merge-tree` before the push | No network read, but git applies `merge=union` locally and GitHub does not, so a union-only divergence reads clean locally and CONFLICTING on the PR. | Rejected |
| D. Read `mergeable` before the first merge call | One settle poll on every land (a fresh PR reads UNKNOWN for seconds, Grounding), for the rare conflict. | Rejected (design critique, performance) |
| E. `land` hands a CONFLICTING PR to `wrap merge --apply --pr <n>` | `merge` does not remove the worktree, delete the branch, pull, or record the ship gate; `land` would need a second tidy path. | Rejected; `merge` gets the same sequence instead |
| F. A `[wrap] verify_cmd` knob instead of a flag | A root-only knob is one command for every repo; the kit's suite and a consumer's differ. The knob is the upgrade path if callers repeat one command. | Flag chosen |
| G. Give `_rb_stop`/`_rb_abort` an operation argument and reuse them for the merge | Keeps one function, but threads merge concerns (restore set, untracked capture, `merge --abort`) through rebase code whose output must stay byte-identical. | Rejected (validation round 1); only the classifier is extracted |

### State of one conflicting land

```
                           merged
   PR #n --> MERGE_1 -------------------------------------> TIDY (today)
               | refused
               v
            READ at head (== tip, not UNKNOWN)
               |  --not CONFLICTING / unreadable / head != tip at bound--> exit 2
               | CONFLICTING
               v
            FETCH --fails--> exit 2 --already contains origin/def--> exit 2 (use wrap merge)
               |
               v
            MERGE_DEFAULT --refused / markers / gen fail / commit refused--> _merge_restore --> exit 2
               |          --dedupe fails--> restore dedupe paths, _undo_local --> exit 2
               |                                  (restore or reset failed --> exit 2, names the command)
               v
            VERIFY (optional) --red or tracked change--> _undo_local --> exit 2
               |
               v
            PUSH_FF --origin still tip / moved--> _undo_local --> exit 2
               |    --origin unreadable--> exit 2, no reset
               |    --origin holds the merge--> treated as pushed
               |          (INT/TERM from MERGE_DEFAULT to PUSH_FF --> restore or reset --> exit 130)
               v
            RE_READ --unreadable / tip still / foreign head / still CONFLICTING--> exit 2 (commit on origin)
               |
               v
            [CI label again] --> CHECKS_WAIT --> MERGE_2 --refused--> exit 2 (no second cycle)
                                                   | merged
                                                   v
                                                 TIDY (tree verify with the merged head)
```

### ADR link(s)

No ADR. The lasting rule, "wrap never forces a push", already stands in `lib/wrap/wrap.sh`'s header and `commands/wrap.md` "What this command does NOT do". This spec keeps it.

### Boundaries & failure modes

The helpers write only in the checkout that holds `<branch>` (`land`'s worktree, or `merge`'s selected or scratch checkout, which can be the main checkout when it holds the branch, as today), only on `<branch>`: a merge commit, a dedupe commit, a restore of files the merge itself changed, or a `reset --keep` of those same unpushed commits. They never switch a branch and never rewrite a pushed commit. `merge`'s unattended path does not run a generator the branch and the default branch disagree on; git hooks run as they do today. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes: the PR JSON fields `mergeable` (`MERGEABLE`, `CONFLICTING`, `UNKNOWN`) and `headRefOid` from `gh pr view --json` (sampled below); `git ls-remote origin refs/heads/<branch>`; `origin/<def>`; `<wt>/lib/registry/feature-registry.sh generate` when present (and, for `merge`, only when it matches `origin/<def>`); the repo's `.gitattributes` through git itself; the `--verify` string from the command line.
- Produces: at most one merge commit and one dedupe commit on `<branch>`, one fast-forward push of `<branch>`, the report lines named in the Contract.
- Function signatures: `_rb_resolve <wt> <gen> <path>...` (0, 1 refused, 3 generator failed), `_merge_default <wt> <branch> <def> <tip> <gen>`, `_merge_restore <wt> <branch> <tip>`, `_verify_or_undo <wt> <branch> <tip> <cmd>`, `_undo_local <wt> <branch> <tip>`, `_push_ff <wt> <branch> <tip>`, `_merge_verify_push <wt> <branch> <def> <tip> <gen> [<cmd>]` (adds 4 for "already contains" and 130 from the trap), `_pr_detail_at_head <url> <n> <tip>` (prints the last JSON read). `MERGED_OID` is set on success.
- Invariants: every commit the helpers create has `<tip>` as an ancestor; nothing that reached origin is ever rewritten; no path with a conflict-marker line is ever staged; a return of 1 leaves `<branch>` at `<tip>` with no merge in progress and a clean worktree; a return of 2 always names the command to run and is never downgraded by a caller.

### Data model changes

None.

### API changes

`bin/wrap land` and `bin/wrap merge` each gain `--verify <cmd>`. Exit 130 is new, for an interrupted merge cycle. `wrap merge` now exits 2 when its re-merge needs a human (today every re-merge failure falls through to the squash fallback).

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

| Task | Depends on | Files | Acceptance |
|---|---|---|---|
| T1: extract `_rb_resolve`, widen `_rb_markers` | none | `lib/wrap/wrap.sh` | every existing rebase test green with byte-identical output; `_rb_stop` calls `_rb_resolve` |
| T2a: merge and restore | T1 | `lib/wrap/wrap.sh`: `_merge_default`, `_merge_restore` | `bash -n lib/wrap/wrap.sh`; the existing suite green; the T2a rows below once T5a lands |
| T2b: verify, undo, push, sequence | T2a | `lib/wrap/wrap.sh`: `_verify_or_undo`, `_undo_local`, `_push_ff`, `_merge_verify_push` and its handler | `bash -n`; the existing suite green; the T2b rows below |
| T3a: `land` trigger | T2b | `cmd_land`: `--verify` parse, `_pr_detail_at_head`, the refused-merge read and its exits | the T3a rows below |
| T3b: `land` cycle | T3a | `cmd_land`: the cycle call, the re-read and its exits, the waits and the failed-check exit, the second merge with the merged tip | the T3b rows below |
| T4: `merge` | T2b | `cmd_merge` `--verify` parse; `_remerge_push` through `_merge_verify_push` with the generator decision; `_union_remerge` scratch cleanup on 130; return 2 passed through with the squash fallback skipped | the T4 rows below |
| T5a: `land` tests | T3b | `tests/test-wrap.sh`, a new `land-merge` block | every `land` row passes |
| T5b: `merge` tests | T4 | `tests/test-wrap.sh`, the same block | every `merge` row passes |
| T6: docs | T3b, T4 | `lib/wrap/wrap.sh` header (verb lines, write-set paragraph), `bin/wrap` usage (and the verify-string note), `commands/wrap.md` (the `land` paragraph in step 3; step 10 names `wrap rebase` only for a branch never pushed), `docs/consumer-contract.md` `bin/wrap` row, `docs/CHANGELOG.md`, `docs/FEATURES.md` regenerated, `docs/implementation-notes/land-merge-default.md` | each flag and exit named once; `tests/test-meta.sh` green |
| T7: the proof | T5a, T5b, T6 | the negctl mutation script (in the scratchpad, not the repo), `docs/verification/land-merge-default.md` with the green runs, the negctl PASS block and the `## Test plan coverage` map | `bash lib/gate/negctl.sh ...` prints `Verdict: PASS`; the proof names every Test plan row |

## Test plan

All cases reuse the land fixture (`build_land`: a bare origin, a clone, a worktree on `feat/land`) and the `gh` stub, with `KIT_WRAP_SETTLE_SECS=0`, `KIT_WRAP_CI_GRACE_SECS=0` and `KIT_WRAP_CARRY_CHECKS_SECS=0` so no case waits. Origin's main advances from a second clone after the branch commits. A conflicting case sets `GH_STUB_MERGE_FAILS=1` with a not-mergeable error so the first `pr merge` refuses, `GH_STUB_PR_42` to `{"mergeable":"CONFLICTING","headRefOid":"<old tip>", ...}`, and a later `GH_STUB_PR_42_<j>` to `MERGEABLE` with `headRefOid` `%REMERGE_TIP%`. Every `pr view 42` counts toward `<j>`, including the checks wait's rollup reads, so each case sets its sequence from the reads it actually makes; the `--with-ci` case uses its own PR number so it never shares a sequence with the existing CI-wait cases. The generator is a stub `lib/registry/feature-registry.sh` that writes `docs/FEATURES.md` from a sorted file listing.

Rows map to tasks: T2a covers Real conflict through Dedupe fails; T2b covers Verify green through Fetch fails; T3a covers Unreadable PR after a refused merge, Head not at tip at the bound, Refused but not conflicting and Happy path cost; T3b covers the rest of the `land` rows; T4 covers the `merge` rows. The first four `land` rows exercise T2a through T3b together.

`land` rows:

| Case | Setup | Expected |
|---|---|---|
| FEATURES conflict | both sides change `docs/FEATURES.md` and add a listed file | exit 0; one merge commit, parents (old tip, origin/main), subject `chore(merge): merge origin/main`; FEATURES equals a fresh generate; the second `pr merge 42` carries `--match-head-commit <merge head>`; tree verified; old tip is an ancestor of the pushed head; no `rebase` entry in `git reflog` |
| Union-only divergence | both sides append to a `merge=union` file | exit 0; both lines kept once |
| CHANGELOG pure additions | both sides add a different bullet | exit 0; both bullets once, every base line kept |
| Clean merge still regenerates | origin adds a listed file, no textual conflict | exit 0; FEATURES in the merge commit equals a fresh generate |
| Real conflict | both sides edit the same line of `base.txt` | exit 2; `REFUSED feat/land: conflict in base.txt`; HEAD equals old tip; no `MERGE_HEAD`; worktree clean; origin `feat/land` equals old tip; exactly one `pr merge` call |
| Mixed conflict | FEATURES and `base.txt` both unmerged | exit 2; names `base.txt` only; old tip restored |
| Markers left (negative control target) | stub generator is a no-op on a FEATURES conflict | exit 2; `MARKERS` names `docs/FEATURES.md`; old tip; no marker in any commit reachable from the branch or origin |
| Marker size attribute | origin's `.gitattributes` sets `conflict-marker-size=9` on FEATURES, no-op generator; a second case with size 5 | exit 2; `MARKERS` names it in both |
| Nested blockquote stays legal | a tracked file the generator touches holds a line of eight `>` characters, no attribute | not flagged; exit 0 |
| Abort after a generator side effect | clean auto-merge of `README.md`; the stub generator rewrites `README.md`, then exits 3 | exit 2; `GENERATOR FAILED`; old tip; no `MERGE_HEAD`; worktree clean |
| Generator fails on a conflict | stub exits 3 on a FEATURES conflict | exit 2; `GENERATOR FAILED`; old tip; worktree clean |
| Untracked generator output on a conflict | a FEATURES conflict; the stub also writes a new untracked file on both runs | the file is in the merge commit; worktree clean |
| Untracked output removed on refusal | the stub writes a new untracked file, then a `base.txt` conflict refuses | exit 2; the file is gone; a file ignored by `.gitignore` is untouched |
| Untracked file hidden by config | `status.showUntrackedFiles=no` set in the fixture and one untracked file present before land | exit 2 before any merge (the `_merge_default` precondition names the dirty checkout); the file is untouched and never committed |
| Commit refused | a `commit-msg` hook in the fixture exits 1 | exit 2; `the merge commit was refused`; old tip; clean |
| Dedupe fails | a union-declared kanban file both sides flipped the same row in; `backlog.sh` shimmed to report a drop, and the dedupe commit refused by a hook | exit 2; HEAD equals old tip; worktree clean |
| Verify green | `--verify 'test -f docs/FEATURES.md'` | exit 0; `verified in` line before the push |
| Verify red | `--verify false` | exit 2; `VERIFY FAILED` names the worktree; HEAD equals old tip; origin branch equals old tip; one `pr merge` call |
| Verify changes a tracked file | `--verify 'echo x >> base.txt'` on a file the merge did not touch | exit 2; `changed tracked files`; nothing pushed; the undo reports the leftover `base.txt` and returns 2 |
| Verify commits | `--verify` makes a commit | exit 2; `VERIFY FAILED`; nothing pushed |
| Push rejected | the `--verify` command itself commits to origin `feat/land` from a second clone | exit 2; `PUSH REFUSED ... moved`; HEAD back at old tip; origin keeps the other clone's commit; no push in the run carries `--force`, `--force-with-lease` or a `+` refspec |
| Branch gone on origin | a `git` shim fails the push and `ls-remote` answers nothing | exit 2; `PUSH FAILED`; HEAD still the merge commit (no reset) |
| Push landed but reported failure | a `git` shim first on PATH performs the push, then exits 1 | exit 0; the land continues with the merged head |
| Interrupted | a `--verify` that sends TERM to the land process | exit 130; old tip; no `MERGE_HEAD`; clean |
| Fetch fails | a `git` shim fails `fetch origin main` inside the cycle | exit 2; `fetch origin main failed`; no merge commit |
| Already contains origin/main | branch merged origin/main before land; the first merge refused as CONFLICTING | exit 2; names `wrap merge --apply --pr 42`; no new commit |
| Still CONFLICTING after push | every view after the push answers CONFLICTING at the merged head | exit 2; names `wrap merge --apply --pr 42` and the merge commit on origin; exactly one `pr merge` call |
| GitHub not caught up | every view after the push answers the old tip | exit 2; `has not caught up` |
| Foreign head after push | the re-read answers a third head | exit 2; `another writer pushed` |
| Unreadable after the push | views after the push print nothing | exit 2; `unreadable after the push` |
| Unreadable PR after a refused merge | `pr view` prints nothing | exit 2; `unreadable`; no merge commit |
| Head not at tip at the bound | the read keeps answering an older head | exit 2; `GitHub still shows head` |
| Refused but not conflicting | the first merge refused, the read answers MERGEABLE | exit 2, today's `MERGE FAILED`; no merge commit |
| Failed check on the merged head | after the push the rollup shows one check `FAILURE` | exit 2; `checks failed on the merged head`; no second `pr merge` |
| No checks, no hold | no `--with-ci`, the rollup is empty, `KIT_WRAP_CI_GRACE_SECS=90` with a `sleep` shim that records calls | exit 0; no `sleep` call from the wait |
| Second merge refused | the merge cycle succeeds, the second `pr merge` refuses | exit 2; names `wrap merge --apply --pr 42` and the merge commit on origin; no third merge call |
| Happy path cost | not conflicting, first merge succeeds | exit 0, today's output; zero `pr view 42` calls before the merge |
| Adopted conflicting PR | an open own PR on the branch | the same merge cycle runs on the adopted PR |
| `--with-ci` conflicting | label-gated repo, conflicting, its own PR number | the label sync and the checks wait run before the first merge and again for the merged head |

`merge` rows:

| Case | Setup | Expected |
|---|---|---|
| Re-merge, FEATURES | `wrap merge --apply` on a CONFLICTING own PR with a FEATURES conflict | the re-merge pushes and the PR merges (today it aborts) |
| Re-merge, real conflict | same-line conflict | `REFUSED` then the existing `conflicts beyond the union-marked files, aborted` line; nothing pushed; exit as today |
| Re-merge, generator changed on the branch | the branch edits `lib/registry/feature-registry.sh`, FEATURES conflicts | the generator never runs (a marker file it would write is absent); FEATURES refused by name |
| Re-merge needs a human | a `git` shim fails `merge --abort` on a refused conflict | `ABORT FAILED`; `FAILED merge #<n>: the re-merge left`; exit 2; no squash-fallback PR created |
| `--verify` red | `wrap merge --apply --verify false` | nothing pushed; the PR stays open |
| Scratch worktree interrupted | no checkout holds the branch; `--verify` sends TERM | exit 130; the scratch worktree and its temp dir are gone |

Both verbs:

| Case | Setup | Expected |
|---|---|---|
| Usage | `land --verify` and `merge --verify` with no value | exit 64 |
| Help | `wrap --help` and `bin/wrap` header | both name `--verify` |
| Every existing land, merge, rebase case | unchanged fixtures | still green, with no fixture weakened; the rebase block's output unchanged |

Negative control: `lib/gate/negctl.sh` mutates the `land` trigger so the CONFLICTING comparison never matches. The FEATURES conflict case must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<mutation script>"` reports PASS. `bash tests/test-meta.sh` exits 0. `RUN_ALL_TIMEOUT_SECS=1500 bash tests/run-all.sh --changed` exits 0.

## After state

- [ ] `wrap land` on a CONFLICTING own PR whose conflicts are all generated, union-declared or pure-add CHANGELOG merges `origin/<default>` into the branch, pushes without force, and lands it. (Today: `MERGE FAILED #<n>: exit 1`, exit 2.) Checkable by the FEATURES conflict case.
- [ ] A real content conflict makes `land` exit 2 naming the path, with the branch at its pushed tip, a clean worktree, and nothing pushed. Checkable by the Real conflict case.
- [ ] `wrap land --verify <cmd>` and `wrap merge --verify <cmd>` run the caller's command after the merge and push nothing on red. Checkable by the Verify red cases.
- [ ] `wrap merge --apply` resolves a FEATURES conflict in its re-merge instead of aborting. (Today: aborts.)
- [ ] A land that merges on its first call makes no extra `gh pr view` call. Checkable by the Happy path cost case.
- [ ] The one push this spec adds carries no `--force`, `--force-with-lease` or `+` refspec. Checkable by `sed -n '/^_push_ff()/,/^}/p' lib/wrap/wrap.sh | grep -E 'force|:\+|origin \+'` printing nothing, plus the Push rejected row.
- [ ] `docs/verification/land-merge-default.md` holds the green runs, the negctl PASS and the test-plan coverage map.

## Edge Cases

1. GitHub still computing mergeability when the first merge is refused: `_pr_detail_at_head` waits while `UNKNOWN` or while the head is not yet `<tip>`, bounded; at the bound `land` exits 2 by name.
2. An adopted PR whose old head GitHub still serves right after `land`'s push: the first merge refuses on `--match-head-commit`; the read waits for the head to reach `<tip>` before trusting `mergeable`. GitHub can still serve a stale CONFLICTING for the new head for a moment; the worst case is one merge commit that was not needed plus one CI run, never a wrong tree.
3. A branch that already merged `origin/<def>` but GitHub still calls CONFLICTING: no second merge, exit 2 routing to `merge`'s squash fallback.
4. `docs/FEATURES.md` changed only on origin, with no conflict: the generator pass regenerates it inside the merge commit, the same as the hand loop.
5. Two branches flipped the same kanban row in a union-declared board: `_union_dedupe_rows` drops the duplicate in a follow-up commit, as `merge` does today; both commits are pushed together.
6. The verify command dirties a tracked file: counted red, `reset --keep` keeps the change when it can, and the helper returns 2 naming the command when it cannot. Nothing was pushed either way.
7. A consumer repo without `lib/registry/feature-registry.sh`: FEATURES is an ordinary file; a conflict on it is refused by name, and no generator pass runs.
8. A commit hook rejects the merge commit: restore, abort, named; the branch is back at its tip.
9. Ten stacked PRs landed one after another: each `land` runs at most one merge cycle; each merge moves the default and the next PR conflicts again, costing one cycle and one CI run each. `wrap merge --apply` and `wrap land` never loop.
10. The operator presses Ctrl-C during a long `--verify`: the trap resets the unpushed merge commit and exits 130. A Ctrl-C during the push itself is judged by `ls-remote`, the same as a failed push.
11. A PR branch someone else pushed a changed generator to, landed unattended by `wrap merge`: the generator does not run, and a FEATURES conflict is refused by name.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Real content conflict | an unmerged path outside the handled classes | `_merge_restore`, `REFUSED` names every path, HEAD at the old tip, exit 2, PR left open |
| Generator rewrites an auto-merged staged file, then fails | `merge --abort` would refuse (Grounding) | restore the merge's own changes from the index first, then abort |
| Generator no-op or partial write | marker scan over the exact stage set, any marker size | restore, abort, `MARKERS` |
| Generator exits non-zero | exit code | restore, abort, `GENERATOR FAILED` |
| Untracked generator output | `ls-files -o` after the generator runs | staged on success, removed on refusal |
| Dedupe commit fails | `_union_dedupe_rows` exit code | restore its staged paths from HEAD, `_undo_local` |
| Verify red, or verify changed a tracked file | the command's exit code, `status` after it | `_undo_local`; nothing pushed |
| Verify hangs | none in wrap | the caller bounds its own command; Ctrl-C runs the trap |
| Push fails | push exit code, then `ls-remote` | landed: continue; not landed: `_undo_local`, `PUSH REFUSED`; unreadable: exit 2, no reset, named; never forced |
| Fetch fails inside the cycle | fetch exit code | exit 2 before any merge |
| GitHub lags after the push | head still the prior one at the bound | exit 2, `has not caught up`, commit named as on origin |
| GitHub still CONFLICTING after the push | re-read `mergeable` | exit 2, routed to `wrap merge --apply --pr <n>` |
| Required checks pending after the push | `_ci_checks_wait` | bounded wait; a refused second merge exits 2 naming `wrap merge --apply --pr <n>` |
| Foreign head after the push | re-read `headRefOid` | exit 2, `another writer pushed` |
| PR read fails (auth, rate limit) | empty JSON | exit 2, `unreadable`, before or after the push |
| Abort or reset itself fails | exit code, HEAD, `MERGE_HEAD`, `status` | return 2 naming the command; `merge` skips its squash fallback and exits 2 |
| Unreviewed generator on an unattended path | `diff origin/<def> -- lib/registry/feature-registry.sh` | `merge` does not run it |
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
- Code path: `_rb_resolve` classifies FEATURES as generated and runs the no-op generator, `_merge_default` runs it once more, builds the stage set, `_rb_markers` finds the `<<<<<<<` and `>>>>>>>` lines, and `_merge_restore` restores and aborts.
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
Design source: SPEC-375 `## Contract` and `## Design` (first draft, commit `bfe47629`)
Lenses run: simplicity, performance, boundaries/composability, data-model & correctness, operability/failure-modes, plus `kit:advisor` over-suggest; missing: none

### High findings
1. The pre-merge `mergeable` read put a settle poll on every land, up to 60s. -- found by: performance -- fix: folded; the read runs only after the first merge is refused.
2. `merge --abort` fails once a generator rewrites an auto-merged staged path. -- found by: correctness (reproduced, Grounding) -- fix: folded; restore the helper's own writes from the index before the abort.
3. A rejected push or an interrupted verify left a diverged, unpushed merge commit with no recovery. -- found by: correctness, operability, advisor -- fix: folded; `_undo_local` on a rejected push, an INT/TERM trap, exit 130.
4. The first read was not pinned to the pushed tip, so a stale CONFLICTING on an adopted PR could trigger a needless merge. -- found by: correctness -- fix: folded; the read waits for `headRefOid == <tip>`.
5. `_merge_default` mixed merge, verify and rollback, and T1 made `_rb_abort` sniff `MERGE_HEAD`. -- found by: boundaries -- fix: folded; single-purpose helpers and distinct return codes 1 and 2 (validation round 1 then narrowed the rebase change to extracting `_rb_resolve`).
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
- DEC-4: one set of helpers for `land` and `merge`'s re-merge, built on the classifier `_rb_resolve` extracted from the rebase code, so the three verbs resolve conflicts by one rule set; `_rb_stop` and `_rb_abort` keep their own abort and staging (approach G, rejected in validation round 1).
- DEC-5: `--verify` is a flag, not a knob, and wrap does not bound it.
- DEC-6: a red verify or a rejected push undoes the local merge commit with `reset --keep`. That commit never reached a remote, so no pushed history changes.
- DEC-7 (validation round 1, NEEDS REVISION, 3 criticals): the proof task T7 was missing (Reviewer 4); a failed dedupe left a merge commit behind a return of 1 (Reviewer 5, Reviewer 6 warning); generator output left untracked on the conflict path was lost (Reviewer 2). Folded: T7; `_merge_default` owns the dedupe cleanup; the checkout must start fully clean, so the stage and restore sets are everything changed or new, tracked and untracked.
- DEC-8 (round 1 warnings folded): one `_merge_verify_push` sequence and trap for both callers; `_pr_detail_at_head` as its own function; `ls-remote` judges a failed push; fetch, post-push unreadable and second-merge exits named; return 2 passed through `merge` with the squash fallback skipped; a verify that changes a tracked file counts red; a conventional merge subject; `_ci_checks_wait` before the second merge; only the classifier is extracted from the rebase code, so `wrap rebase` stays byte-identical; wider marker pattern; `rm -f --` per untracked path; `merge` runs only a generator that matches `origin/<def>`; the verify string is echoed as typed; tasks split with a Depends column.
- DEC-9 (validation round 2: APPROVED, 0 critical, 30 warnings, Reviewer 6 pass): folded the handler (INT, TERM, HUP; prior handlers saved; returns 130 or 2, callers exit), `_undo_local` returning 2 when leftovers remain, a verify that commits counts red, a pending-only wait without `--with-ci` plus a failed-check exit before the second merge, the `merge` generator decided before the sequence, return 5 for a refused conflict, marker size read per path, `--untracked-files=all` in every clean check, `ls-remote` answering nothing, `--verify` scoped to a merge cycle, the boundary wording, the push check scoped to `_push_ff`, T2 split, and a row-to-task map.

## Open questions

(none)
