# SPEC-374: wrap land merges the default branch into a conflicting own PR instead of stopping

**Status:** DRAFT
Lane: full
Type: spec-feature
**Proof:** `docs/verification/land-merge-default.md`; `tests/test-wrap.sh`, the land-merge block.
References: `lib/wrap/wrap.sh` `cmd_rebase` and its `_rb_*` helpers (SPEC-329): the stop classifier, the CHANGELOG pure-addition resolver, the exact stage set and the marker scan this spec reuses unchanged. `_remerge_push` and `_union_dedupe_rows` (the `wrap merge` re-merge): the merge-not-rebase shape, the "already contains origin/<def>" guard, and the union-row dedupe.

## Problem

`wrap land <worktree>` pushes the branch, opens or adopts the PR, then calls `gh pr merge --squash --match-head-commit`. When `origin/<default>` moved on and the PR is CONFLICTING, GitHub refuses the merge and `land` exits 2 with `MERGE FAILED #<n>: exit 1`. The only verb that moves a branch past the default is `wrap rebase`, which rewrites history. The branch is already on origin, so the rebased branch needs a force-push, and the operator's rule forbids a force-push without confirmation.

In one session this happened four times. Each time the lead ran the same loop by hand in the worktree: `git merge --no-edit origin/<default>`, regenerate `docs/FEATURES.md` with the repo's own generator, rerun the tests, push normally, run `wrap land` again. The loop never needed a rebase, and it never needed a force.

`wrap merge --apply` already re-merges `origin/<default>` into a conflicting own PR (`_remerge_push`), but it aborts on any conflict git's union driver does not resolve, so a `docs/FEATURES.md` or `docs/CHANGELOG.md` conflict stops it too.

## Contract

### The shared merge step

One helper, `_merge_default <wt> <branch> <def> <tip> [<verify-cmd>]`, runs in a checkout that holds `<branch>` at `<tip>`, clean (no tracked or untracked change), with `origin/<def>` freshly fetched and not already an ancestor of `<tip>`.

- It runs `git merge --no-ff --no-commit origin/<def>` with `-c rerere.enabled=false` and `GIT_EDITOR=true` (the `_rb_git` pins). It never runs `git rebase` and never pushes.
- Unmerged paths are classified with the rebase rules, unchanged: `docs/FEATURES.md` with `<wt>/lib/registry/feature-registry.sh` present is regenerated; `docs/CHANGELOG.md` is kept both sides only when both sides purely added lines; anything else, including a union-declared path still unmerged (a delete or rename conflict), is refused. Every path is classified before any is resolved.
- One refused path: `git merge --abort`, the line `REFUSED <branch>: conflict in <path>, <path>`, a check that HEAD is `<tip>` and no merge is in progress, return 1. When the abort fails or HEAD is elsewhere: `ABORT FAILED <branch>: run git merge --abort in <wt>`, return 1.
- After the classified paths resolve, and also on a merge with no conflict at all, the generator runs once more when it exists. The stage set is exact, as in the rebase: the unmerged paths plus every tracked path whose worktree copy changed between a `git diff --name-only` record taken before the resolvers and one taken after the generator. The set is marker-scanned (`_rb_markers`); a hit aborts the merge with `MARKERS <branch>: <paths>`, return 1. A generator exit other than 0 aborts with `GENERATOR FAILED <branch>`, return 1. Then `git add -- <set>`, never `-u` or `-A`.
- `git commit --no-edit` records one merge commit with two parents: `<tip>` first, `origin/<def>` second. A refused commit (a commit hook) aborts the merge, prints `FAILED <branch>: the merge commit was refused`, return 1.
- `_union_dedupe_rows <wt> <tip>` runs after the commit, as `_remerge_push` runs it today. A failed dedupe commit returns 1 with its existing line.
- When `<verify-cmd>` is given, it runs as `bash -c "<verify-cmd>"` with the checkout as cwd, output to the terminal. Exit 0 prints `verified: <verify-cmd>`. Any other exit prints `VERIFY FAILED <branch>: <verify-cmd> exited <rc> after merging origin/<def>`, then `git reset -q --keep <tip>` undoes the local merge (and dedupe) commit, which no remote ever held, and the helper returns 1. When `reset --keep` itself refuses (the verify command left a conflicting change), the line says `the merge commit <sha7> stays local, never pushed` and the helper returns 1.
- Success sets `MERGED_OID` to the new HEAD and prints `merged origin/<def> into <branch>: <n> conflict(s) resolved, head <sha7> (was <sha7>)`, return 0.

### `wrap land <worktree> [--title T] [--body-file F] [--with-ci] [--verify <cmd>]`

- New flag `--verify <cmd>` (also `--verify=<cmd>`). A missing value exits 64, the same as `--title`. Without `--verify`, the merge step runs no command.
- Every existing refusal is unchanged: usage, non-worktree, main checkout, dirty worktree, detached HEAD, protected branch, gh state, nothing ahead, push refused, every PR lookup refusal, adopting only the operator's own PR on the default base.
- After the PR is opened or adopted, and before the `ci` label sync, `land` reads the PR once with `_pr_detail_settled <url> <n>` (it waits while GitHub reports `UNKNOWN`, bounded by `KIT_WRAP_SETTLE_SECS`). When `.mergeable` is not `CONFLICTING`, nothing below runs and `land` continues exactly as today.
- When `.mergeable` is `CONFLICTING`, `land` prints `     #<n> is CONFLICTING: merging origin/<def> into <branch>` and:
  - When `origin/<def>` is already an ancestor of HEAD, nothing is merged: `land` prints `     <branch> already contains origin/<def>; GitHub's conflict is the union-blind case, run wrap merge --apply --pr <n>` and exits 2. The PR stays open.
  - Otherwise it runs `_merge_default` in `<wt>` with the `--verify` command. A return of 1 exits 2 after one line `     PR #<n> left open; <branch> is back at <sha7>` (or, after a reset that refused, the helper's own line). Nothing was pushed.
  - On success it pushes with a plain `git -C <wt> push origin <branch>`: never `--force`, never `--force-with-lease`, never a refspec with `+`. The merge commit descends from the pushed tip, so the push is a fast-forward. A rejected push prints `     PUSH REFUSED: git push origin <branch> exited <rc>; the merge commit <sha7> stays local` and exits with git's code.
  - It re-reads the PR with `_pr_detail_settled <url> <n> <MERGED_OID> <old tip>`. A head other than `MERGED_OID` exits 2 with `     PR #<n> head is <sha7>, not the pushed <sha7>; left open`. A `.mergeable` still `CONFLICTING` exits 2 with `     #<n> is still CONFLICTING after the merge; run wrap merge --apply --pr <n>` (its squash fallback owns that case).
  - Otherwise `land` continues with `tip=MERGED_OID`: the `ci` label sync, `_gh_merge_retry <n> <url> <tip>` (so `--match-head-commit` pins the merged head), `_tree_verify` against that head, the ship record, the origin branch delete leased to that head, the pull, the worktree removal and the branch delete, all unchanged.

### `wrap merge [--apply] [--pr N] [--with-ci] [--verify <cmd>] <repo>`

- New flag `--verify <cmd>`, same parse and 64 rule. It applies only to the one bounded re-merge; a PR that needs no re-merge runs no command.
- `_remerge_push` keeps its fetch, its "already contains origin/<def>" refusal (which routes to the squash fallback), and its push and `REMERGE_OID` contract. Its `git merge --no-edit origin/<def>` plus abort-on-any-conflict is replaced by `_merge_default`, with the `--verify` command. On a return of 1 it prints its existing line `     merging origin/<def> into <branch> conflicts beyond the union-marked files, aborted` after the helper's own line, and returns 1. In the scratch-worktree case the scratch worktree is still removed afterwards.

### Unchanged

`wrap rebase` is unchanged. `_squash_fallback`, `_pr_gate`, `_tree_verify`, the dependents gate, and every `land` and `merge` refusal outside this section are unchanged. No verb force-pushes.

## Picture

```
  wrap land <wt> [--verify C]                     wrap merge --apply [--verify C]
          |                                                  |
          v                                                  v
   push, open/adopt PR #n                         _pr_gate: SKIP not mergeable (CONFLICTING)
          |                                                  |
          v                                                  v
   _pr_detail_settled: mergeable?               _union_remerge -> _remerge_push
     |            |                                          |
  not CONFLICTING CONFLICTING                                |
     |            |                                          |
     |            +------------------+  +--------------------+
     |                               v  v
     |              +------------------------------------------+
     |              | _merge_default <wt> <branch> <def> <tip> |
     |              |  git merge --no-ff --no-commit origin/def|
     |              |  classify unmerged (the _rb_ rules):     |
     |              |    FEATURES -> repo's generator          |
     |              |    CHANGELOG pure-add -> union           |
     |              |    other -> merge --abort, REFUSED       |
     |              |  generator once more, exact stage set    |
     |              |  marker scan -> MARKERS, abort           |
     |              |  commit --no-edit (2 parents)            |
     |              |  dedupe union rows                       |
     |              |  verify C -> red: reset --keep <tip>     |
     |              +------------------------------------------+
     |                               |
     |                               v
     |                  git push origin <branch>   (fast-forward, never forced)
     |                               |
     |                               v
     |                  re-read PR pinned to the pushed head
     |                               |
     v                               v
   ci label sync -> gh pr merge --squash --match-head-commit <tip> -> _tree_verify -> tidy
```

## Design

Design-bearing: it adds a write path (a merge commit and a push) to `land`, and changes `merge`'s re-merge from abort-on-conflict to resolve-or-refuse.

### Approaches considered + chosen

| Approach | Tradeoff | Verdict |
|---|---|---|
| A. `land` merges `origin/<def>` into the branch when the PR reads CONFLICTING, through one helper shared with `merge`'s re-merge | Adds a merge commit to the PR branch. The squash merge flattens it, so the default branch history is unchanged. | Chosen |
| B. `land` calls `wrap rebase`, then `push --force-with-lease` | Linear branch, but a force-push on every conflict. The operator's rule forbids it without confirmation, and wrap's own contract says it never forces. | Rejected |
| C. `land` precomputes a local `git merge-tree` before the push and merges only then | No network read, but git applies `merge=union` locally and GitHub does not, so a union-only divergence reads clean locally and CONFLICTING on the PR. The trigger would miss the case `merge`'s re-merge exists for. | Rejected |
| D. `land` hands a CONFLICTING PR to `wrap merge --apply --pr <n>` | `merge` does not remove the worktree, delete the branch, pull, or record the ship gate; `land` would need a second tidy path. It also still aborts on FEATURES. | Rejected; `merge` gets the same helper instead |
| E. A `[wrap] verify_cmd` knob instead of a flag | A root-only knob is one command for every repo; the kit's own suite and a consumer's differ. A flag is the caller's command for this landing. The knob is the upgrade path if callers repeat one command. | Flag chosen |

The trigger is GitHub's own `mergeable` field, read once after the PR exists. That is the verdict the squash merge obeys, and `merge` already keys its re-merge on it.

### State of one conflicting land

```
            +---------------+  mergeable != CONFLICTING
  PR #n --> | READ_PR       | ------------------------------> MERGE_PR (today's path)
            +---------------+
                   | CONFLICTING
                   v
            +---------------+  origin/def already in HEAD
            | MERGE_DEFAULT | ------------------------------> exit 2 (union-blind, use merge)
            +---------------+
              |    |     |
   refused /  |    |     | verify red
   markers /  |    |     +--> reset --keep <tip> ----------> exit 2 (nothing pushed)
   gen fail   |    |
   v          |    | merged
  merge --abort    v
  exit 2    +---------------+  rejected
            | PUSH (ff)     | ------------------------------> exit rc (merge commit local)
            +---------------+
                   |
                   v
            +---------------+  head moved / still CONFLICTING
            | RE_READ       | ------------------------------> exit 2 (PR open)
            +---------------+
                   | head == pushed, not CONFLICTING
                   v
               MERGE_PR with tip = merged head
```

### ADR link(s)

No ADR. The lasting rule, "wrap never forces a push", already stands in `lib/wrap/wrap.sh`'s header and `commands/wrap.md` "What this command does NOT do". This spec keeps it.

### Boundaries & failure modes

The helper writes only in the checkout it is given, only on `<branch>`, and only commits a merge or resets its own unpushed commit. It never touches the main checkout, never switches a branch, never rewrites a pushed commit. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Consumes: the PR JSON field `mergeable` (`MERGEABLE`, `CONFLICTING`, `UNKNOWN`) and `headRefOid` from `gh pr view --json` (sampled below); `origin/<def>`; `<wt>/lib/registry/feature-registry.sh generate` when present; the repo's `.gitattributes` through git itself.
- Produces: at most one merge commit and one dedupe commit on `<branch>`, one fast-forward push of `<branch>`, the report lines named in the Contract.
- Invariants: every commit the helper creates has `<tip>` as an ancestor; nothing that reached origin is ever rewritten; no path with a conflict-marker line is ever staged by the helper; a refusal leaves `<branch>` at `<tip>` with no merge in progress.

### Data model changes

None.

### API changes

`bin/wrap land` and `bin/wrap merge` each gain `--verify <cmd>`. Exit codes unchanged: 64 usage, 1 preflight refusal, 2 PR or merge failure (now also a refused merge step), 3 tree mismatch.

### UI changes

None.

### Infrastructure changes

None.

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: the shared merge step | `lib/wrap/wrap.sh` (`_merge_default`; `_rb_abort` learns a merge: `merge --abort` when `MERGE_HEAD` exists, else `rebase --abort`, message names the verb) | the Contract's helper rules; every rebase test still green |
| T2: `land` trigger | `lib/wrap/wrap.sh` (`cmd_land`: `--verify` parse, the CONFLICTING read, merge, push, re-read, `tip` swap) | the Contract's `land` rules |
| T3: `merge` re-merge | `lib/wrap/wrap.sh` (`cmd_merge` `--verify` parse, `_remerge_push` calls the helper) | FEATURES and pure-add CHANGELOG conflicts now resolve; a real conflict still aborts with the old line |
| T4: tests | `tests/test-wrap.sh` | every Test plan row passes |
| T5: docs | `lib/wrap/wrap.sh` header (verb lines, write-set paragraph), `bin/wrap` usage, `commands/wrap.md` (the `land` paragraph in step 3; step 10 names `wrap rebase` only for a branch never pushed), `docs/consumer-contract.md` `bin/wrap` row, `docs/CHANGELOG.md`, `docs/FEATURES.md` regenerated, `docs/implementation-notes/land-merge-default.md` | each flag and exit named once; `tests/test-meta.sh` green |

## Test plan

All cases reuse the land fixture (`build_land`: a bare origin, a clone, a worktree on `feat/land`) and the `gh` stub. `GH_STUB_PR_42` answers the first view with `{"mergeable":"CONFLICTING", ...}` and `GH_STUB_PR_42_2` answers later views with `MERGEABLE` and `headRefOid` `%REMERGE_TIP%`. Origin's main is advanced from a second clone after the branch commits. The generator is a stub `lib/registry/feature-registry.sh` that writes `docs/FEATURES.md` from a sorted file listing.

| Case | Setup | Expected |
|---|---|---|
| FEATURES conflict | both sides change `docs/FEATURES.md` and add a listed file | exit 0; one merge commit with parents (old tip, origin/main); FEATURES equals a fresh generate; `pr merge 42 ... --match-head-commit <merge head>`; tree verified; old tip is an ancestor of the pushed head; no `rebase` in `git reflog` |
| Union-only divergence | both sides append to a `merge=union` file; GitHub reports CONFLICTING | exit 0; both lines kept once; merged head landed |
| CHANGELOG pure additions | both sides add a different bullet | exit 0; both bullets once, every base line kept |
| Clean merge still regenerates | origin adds a listed file, no textual conflict, PR reads CONFLICTING | exit 0; FEATURES in the merge commit equals a fresh generate |
| Real conflict | both sides edit the same line of `base.txt` | exit 2; `REFUSED feat/land: conflict in base.txt`; HEAD equals old tip; no `MERGE_HEAD`; origin `feat/land` equals old tip; no `pr merge` call |
| Mixed conflict | FEATURES and `base.txt` both unmerged | exit 2; names `base.txt` only; old tip restored |
| Markers left (negative control target) | stub generator is a no-op | exit 2; `MARKERS` names `docs/FEATURES.md`; old tip; no marker in any commit reachable from the branch or origin |
| Generator fails | stub exits 3 | exit 2; `GENERATOR FAILED`; old tip |
| Verify green | `--verify 'test -f docs/FEATURES.md'` | exit 0; `verified:` line before the push line |
| Verify red | `--verify false` | exit 2; `VERIFY FAILED`; HEAD equals old tip; origin branch equals old tip; no `pr merge` call |
| Already contains origin/main | branch merged origin/main before land; PR still CONFLICTING | exit 2; names `wrap merge --apply --pr 42`; no new commit |
| Still CONFLICTING after push | every view answers CONFLICTING | exit 2; names `wrap merge --apply --pr 42`; the merge commit is on origin; no `pr merge` call |
| Head moved after push | re-read answers a foreign head | exit 2; names both heads |
| Push rejected | the `--verify` command itself pushes a new commit to origin `feat/land` from a second clone, so origin moves after the merge commit and before `land`'s push | exit non-zero; `PUSH REFUSED`; the merge commit stays local; origin keeps the other clone's commit; never forced |
| Not conflicting | `GH_STUB_PR_42` unset (reads `{}`) or `MERGEABLE` | exit 0, today's output; no merge commit on the branch |
| Adopted conflicting PR | an open own PR on the branch, CONFLICTING | the same merge path runs on the adopted PR |
| merge re-merge, FEATURES | `wrap merge --apply` on a CONFLICTING own PR with a FEATURES conflict | the re-merge pushes and the PR merges (today it aborts) |
| merge re-merge, real conflict | same-line conflict | the existing `conflicts beyond the union-marked files, aborted` line plus `REFUSED`; nothing pushed |
| merge --verify red | `wrap merge --apply --verify false` | nothing pushed; the PR stays open |
| Usage | `land --verify` and `merge --verify` with no value | exit 64 |
| Help | `wrap --help` and `bin/wrap` header | both name `--verify` |
| Every existing land, merge, rebase case | unchanged fixtures | still green. The new PR read adds one `pr view` per land, which shifts the stub's per-PR view counter; a `--with-ci` case that steps `GH_STUB_PR_<n>_<j>` is re-indexed by one, never weakened |

Negative control: `lib/gate/negctl.sh` mutates the `land` trigger so the CONFLICTING comparison never matches. The FEATURES conflict case must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap.sh" "<mutation script>"` reports PASS. `bash tests/test-meta.sh` exits 0. `RUN_ALL_TIMEOUT_SECS=1500 bash tests/run-all.sh --changed` exits 0.

## After state

- [ ] `wrap land` on a CONFLICTING own PR whose conflicts are all generated, union-declared or pure-add CHANGELOG merges `origin/<default>` into the branch, pushes without force, and lands it. (Today: `MERGE FAILED #<n>: exit 1`, exit 2.) Checkable by the FEATURES conflict case.
- [ ] A real content conflict makes `land` exit 2 naming the path, with the branch back at its pushed tip and nothing pushed. Checkable by the Real conflict case.
- [ ] `wrap land --verify <cmd>` and `wrap merge --verify <cmd>` rerun the caller's command after the merge and push nothing on red. Checkable by the Verify red cases.
- [ ] `wrap merge --apply` resolves a FEATURES conflict in its re-merge instead of aborting. (Today: aborts.)
- [ ] No `git push` in `lib/wrap/wrap.sh` added by this spec carries `--force`, `--force-with-lease` or a `+` refspec. Checkable by `git diff origin/master -- lib/wrap/wrap.sh | grep '^+.*push' | grep -E 'force|\+refs|origin \+'` printing nothing.

## Edge Cases

1. GitHub still computing mergeability when `land` reads it: `_pr_detail_settled` waits while `UNKNOWN`; a verdict that never settles reads as not CONFLICTING and `land` runs today's merge, which GitHub refuses by name if it really conflicts.
2. The PR head on GitHub is not the tip `land` pushed (another writer pushed between): the merge step would build on a stale tip. Covered: `land` pushed that tip seconds earlier, and the re-read after the merge push compares heads and refuses a foreign one.
3. A branch that already merged `origin/<def>` but GitHub still calls CONFLICTING: no second merge, exit 2 routing to `merge`'s squash fallback.
4. `docs/FEATURES.md` changed only on origin, with no conflict: the post-merge generator pass regenerates it in the merge commit, the same as the operator's hand loop.
5. Two branches flipped the same kanban row in a union-declared board: `_union_dedupe_rows` drops the duplicate in a follow-up commit, as `merge` does today.
6. The verify command dirties the worktree: `reset --keep` keeps those changes when it can; when it cannot, the merge commit stays local and is named. Either way nothing was pushed, and the next `land` refuses the dirty worktree.
7. A consumer repo without `lib/registry/feature-registry.sh`: FEATURES is an ordinary file; a conflict on it is refused by name.
8. A commit hook rejects the merge commit: the merge is aborted and named; the branch is back at its tip.
9. An adopted draft PR: `land` marks it ready before the read (today's behavior), so the merge step runs on it the same way.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Real content conflict | an unmerged path outside the handled classes | `merge --abort`, `REFUSED` names every path, HEAD at the old tip, exit 2, PR left open |
| Generator no-op or partial write | marker scan over the exact stage set | abort, `MARKERS`, nothing staged |
| Generator exits non-zero | exit code | abort, `GENERATOR FAILED` |
| Verify red | the command's exit code | `reset --keep <tip>` of the unpushed commit; `VERIFY FAILED`; nothing pushed |
| Push rejected (origin branch moved) | push exit code | `PUSH REFUSED`, merge commit local; never forced |
| GitHub still CONFLICTING after the push | re-read `mergeable` | exit 2, routed to `wrap merge --apply --pr <n>` |
| Foreign head after the push | re-read `headRefOid` | exit 2, both heads named |
| Abort itself fails | exit code, HEAD, `MERGE_HEAD` | `ABORT FAILED ... run git merge --abort in <wt>` |
| rerere replays an old resolution | none needed | `-c rerere.enabled=false` on the merge |
| Squash merge pinned to a stale head | `--match-head-commit` gets the merged head | GitHub refuses a mismatch, as today |

## Out of Scope

- A refusal in `wrap rebase` for a branch already on origin. The rebase stays for a branch never pushed (`commands/wrap.md` step 10 before its first push); this spec only documents that.
- `land` running `merge`'s squash fallback itself. It names the command instead.
- A second generated file. The `ponytail:` note on `_RB_GENERATED` keeps the knob as the upgrade path.
- A `[wrap] verify_cmd` knob (Design, approach E).

## Grounding

### Live sample: the PR `mergeable` field

Read-only, `dwarvesf/dwarves-kit`, 2026-09-30:

```
$ gh pr view 444 --json number,mergeable,mergeStateStatus,headRefOid,baseRefName
{"baseRefName":"master","headRefOid":"ba6200e4…a749bb9a","mergeStateStatus":"DIRTY","mergeable":"CONFLICTING","number":444}
```

The first `gh pr list --json mergeable` a few seconds earlier answered `"mergeable":"UNKNOWN"` for the same PR. That is the lag `_pr_detail_settled` already waits out, and why `land` reads through it.

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

### Dry trace: the negative control

- Mutation: in `cmd_land`, the comparison `[ "$m" = "CONFLICTING" ]` (the trigger after the PR read) becomes `[ "$m" = "CONFLICTING-NEVER" ]`.
- Fixture reads: the FEATURES conflict case sets `GH_STUB_PR_42` to a CONFLICTING JSON. The stub serves it on the first `pr view 42`.
- Code path under mutation: the trigger never matches, so `land` skips the merge step, goes to `_gh_merge_retry` with the old tip, and the stub's `pr merge` lands `feat/land` as-is (the stub always succeeds). The pushed head is the old tip.
- Red test: `land-merge: FEATURES conflict merges origin/main into the branch` (asserts a two-parent commit at HEAD whose second parent is origin/main) and `land-merge: the merge pins the merged head` (asserts `--match-head-commit <merge head>`) both fail.

### Dry trace: the markers case

- Mutation (the fixture itself): the stub generator exits 0 and writes nothing, so git's conflict markers stay in `docs/FEATURES.md`.
- Code path: `_merge_default` classifies FEATURES as generated, runs the no-op generator, builds the stage set, `_rb_markers` finds `<<<<<<<` and `>>>>>>>` lines, and the helper aborts the merge.
- Red test if the scan were removed: `land-merge: no marker in any commit` would find `+<<<<<<<` in `git log -p`.

### Dry trace: verify red

- Fixture: `--verify false`, the FEATURES conflict fixture.
- Code path: the merge commit is made, `bash -c false` exits 1, `reset --keep <tip>` restores the branch, the helper returns 1, `land` exits 2 before any push.
- Red test if the reset were skipped: `land-merge: verify red restores the old tip` fails on `rev-parse HEAD`.

### Unsampled

GitHub's `mergeable` after a push of a merge commit that already contains the base is not sampled here. `_squash_fallback`'s comment records that GitHub has kept `CONFLICTING` in that state before; the Contract routes that case to `wrap merge --apply --pr <n>` and does not assume it clears.

## Decision Log

- DEC-1: merge, never rebase, for a branch that is already on origin. A rebase needs a force-push; a merge commit is flattened by the squash merge anyway.
- DEC-2: the trigger is GitHub's `mergeable`, not a local `merge-tree`, because git applies `merge=union` and GitHub does not.
- DEC-3: one helper for `land` and `merge`'s re-merge, built from the rebase's `_rb_*` classifier, so the three verbs resolve conflicts by one rule set.
- DEC-4: `--verify` is a flag, not a knob (Design, approach E).
- DEC-5: a red verify undoes the local merge commit with `reset --keep`. That commit never reached a remote, so no pushed history changes.

## Open questions

(none)
