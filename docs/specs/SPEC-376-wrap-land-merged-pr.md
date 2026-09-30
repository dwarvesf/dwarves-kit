# Spec: wrap land recognizes an already-merged PR before opening a new one
Generated: 2026-09-30
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a branch re-pushed with new commits after its own PR already merged must still open a fresh PR for those new commits; a detection rule that only checks "does gh already call this PR MERGED" could wrongly treat the whole branch as landed and silently drop the new commits)
References: `lib/wrap/wrap.sh:441-461` (`_merge_proof`, the ancestor/absorbed/squash proof `wrap apply`'s worktree tidy already trusts for "this branch is already merged, tidy it"); `lib/wrap/wrap.sh:1346-1349` (`_autoland_carry`, the one other caller that checks a squash proof before deciding to open a PR at all) -- both are the mechanism this spec reuses, not duplicates.

## Problem

On 2026-09-30, in a consumer repo adopted into this operate-contract, PR A on a feature branch was squash-merged. `bin/wrap land <worktree>` then ran on the same worktree, which still held the pre-merge commits. It:

1. Pushed the stale worktree copy of the feature branch to origin (harmless by itself -- the branch ref, not the default branch).
2. Looked up open PRs for that branch, found none (PR A is `MERGED`, not `OPEN`), and fell through to `gh pr create`.
3. Opened PR B with a diff byte-identical to PR A's already-landed content, then squash-merged PR B too.

Expected: land notices the branch's own PR already merged (or that the branch's content is already on the default branch by any other route), stops without pushing or opening anything, and tidies the worktree the same way a normal post-merge land does. The adopt path (an already-OPEN own PR for the branch) is unaffected and must keep working exactly as it does today.

## Root cause

`cmd_land` (`lib/wrap/wrap.sh:2408-2408` onward) has no step that asks "has this branch's content already landed?" before deciding to push and open a PR. Two things hide the fact from it:

- The `ahead` check (`lib/wrap/wrap.sh:2456-2459`, `git rev-list --count origin/<def>..<branch>`) is pure commit-graph ancestry. A squash merge writes a brand-new commit on the default branch with a new SHA; none of the original branch's commits become ancestors of it. So `ahead` stays greater than zero forever after a squash merge, and land reads that as "real, unlanded work."
- The open-PR lookup (`lib/wrap/wrap.sh:2479-2491`, `gh pr list --head <branch> --state open ...`) filters `--state open` only. A `MERGED` PR for the same head is invisible to it.

**The exact decision point is `lib/wrap/wrap.sh:2521-2537`**, the `else` arm of the `open_count` cascade (`open_count -gt 1` refuse / `-eq 1` adopt / else create):

```
2521    else
2522      # `--head`, never `--base`: ...
2523      if [ -n "$body_file" ]; then
2524        created="$(gh pr create --repo "$url" --head "$branch" --title "$title" --body-file "$body_file" 2>&1)"; rc=$?
...
2536      echo "     opened PR #${n}"
```

`open_count` is 0 whenever there is no *open* PR for the branch -- which is exactly the state a branch is in the moment its own PR merges. Nothing between the fetch (line 2455) and this `else` ever asks whether the branch is already proven merged, so a just-merged branch and a genuinely brand-new branch look identical to this code, and both fall into the same "create a PR" arm.

The fix is not a special case bolted onto this `else`. `wrap.sh` already has the check land is missing: `_merge_proof` (`lib/wrap/wrap.sh:441-461`) answers exactly "has this branch already reached the default branch," across all three ways that can happen -- a plain fast-forward/rebase ancestor, tree-identical content absorbed without a matching PR (`_absorbed`), or a gh-recorded squash merge (`_squash_json` / `_squash_verdict`, the same helper `_autoland_carry` already checks at line 1346-1349 before it will open a PR). `wrap apply`'s worktree-tidy pass (`lib/wrap/wrap.sh:581-583`) already calls `_merge_proof "$repo" "$def" "$ghs" "$wtb"` before removing a worktree and deleting its branch. `cmd_land` is the one caller in this file that reaches the same "should I open a PR / should I tidy this worktree" fork without ever asking that helper.

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Widen the open-PR lookup to `--state all` and special-case a `MERGED` result | Catches the squash-merged-PR case only; still blind to a plain ancestor/absorbed merge with no PR record at all (e.g. someone fast-forward-merged by hand), and re-derives a check `_merge_proof` already does correctly |
| B | Call the existing `_merge_proof` helper right after the fetch, before the `ahead` refusal; a proof found skips straight to the tidy tail, no proof falls through to the existing push/PR/merge path unchanged | One extra call to a helper this file already trusts for the identical question; no new proof logic to get subtly wrong a second way |
| C | Treat `ahead -eq 0` (today's refusal) as "already landed" and tidy there, leave the open-PR/state-open gap alone | Only fixes the fast-forward case; the reported bug is a squash merge, where `ahead` is never 0, so this leaves the actual incident unfixed |

### Chosen approach + why

B. `_merge_proof` is the one function in this file whose whole job is "is this branch's content already on the default branch, by any of the three ways that can be true," and it is already exercised in production by `wrap apply`'s worktree tidy and by `_autoland_carry`. Land reusing it, rather than land's `else` arm growing its own second opinion on the same question, is the only approach that fixes the ancestor case, the absorbed case, and the squash case at once, and it does so without touching the two things that must stay exactly as they are: the adopt path (`open_count -eq 1`) and the "genuinely new work" push/PR/merge path (no proof).

### Extensibility & boundaries

- Load-bearing dimension: the set of ways a branch's content can already be on the default branch. `_merge_proof` already owns that enumeration; this spec adds no fourth way, it only makes `cmd_land` ask the question that already has three answers.
- Unit boundary: the new check is one guarded early-return inside `cmd_land`, reusing `_merge_proof` and the tidy tail `cmd_land` already runs after a real merge (fast-forward pull, worktree remove, branch delete). No new helper function is introduced.

## Picture

```
                     bin/wrap land <worktree>
                              |
                    resolve wt/repo/branch/def
                    _gh_state == ok  (else refuse, as today)
                              |
                    git fetch origin <def>
                              |
              NEW: proof="$(_merge_proof "$repo" "$def" "$ghs" "$branch")"
                    /                                    \
          proof found                               proof NOT found
   (ancestor of origin/<def>,                    (genuinely unlanded work,
    content absorbed, or                          OR re-pushed with new
    gh-recorded squash merge)                      commits past what merged)
          |                                                |
   print "already landed: <proof>;                 unchanged today's path:
   nothing to push, no PR opened"                   ahead-check (>0 required)
          |                                          -> push branch
          |                                          -> open-PR lookup (state=open)
          |                                          -> adopt (1 open) / refuse (>1)
          |                                          -> create PR (0 open)  <-- PR B bug lived here
          |                                          -> squash-merge -> tree-verify
          |                                                |
          `-------------------> same tidy tail <-----------'
                    fast-forward-pull main checkout
                    (skip origin-branch delete if the ref
                     is already gone -- squash merges often
                     auto-delete it)
                    remove worktree, delete local branch
```

## Design

### Approaches considered + chosen

See `## Solution` above.

### Diagram

See `## Picture`.

### ADR link(s)

None. This is a local bug fix inside an existing, already-designed helper (`_merge_proof`); it makes no new lasting decision.

### Boundaries & failure modes

See `## Failure modes` below, in particular the re-pushed-with-new-commits case, which is the one this spec must get right rather than merely avoid regressing.

## Technical Design

### Interfaces (I/O contract)

- Consumes: `_merge_proof <repo> <def> <ghs> <branch>` (unchanged signature, no edit to the helper itself). `cmd_land` calls it with `repo` (the main checkout it already resolves at `lib/wrap/wrap.sh:2435-2437`), not `wt`, matching the exact call shape `_apply_worktrees` uses at line 581.
- Produces: on a proof, `cmd_land` prints one stop line naming the proof text, then runs the same tidy calls it already makes for a normal merged land (`_land_ff_pull`, `git worktree remove -f -f`, `git branch -D`). Exit code 0.
- Invariant: the adopt path (`open_count -eq 1`, `lib/wrap/wrap.sh:2496-2520`) and the create-new-PR path (`open_count -eq 0`, no proof) are byte-for-byte unchanged in behavior; only the branch that reaches them changes (a branch with a merge proof never reaches either now).

### Data model changes

None.

### API changes

None (internal script only).

### UI changes

Output only: one new stop-line shape, `     already landed: <proof>; nothing to push, no PR opened`, where `<proof>` is `_merge_proof`'s own text (`ancestor of origin/<def>`, `content already on origin/<def>`, or `squash-merged per gh`).

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: In `cmd_land`, right after the `git fetch origin "$def"` call (`lib/wrap/wrap.sh:2455`) and before the `ahead` refusal (`:2456-2459`), call `_merge_proof "$repo" "$def" "$ghs" "$branch"`. On success, skip the `ahead` refusal, the push, the open-PR lookup, `gh pr create`/adopt, the merge, and the ship-gate record block entirely; print `land ${branch} -> ${def} (${wt})` then `     already landed: ${proof}; nothing to push, no PR opened`; fall through into the existing tidy tail (fast-forward pull, worktree remove, branch delete) unchanged. On failure (no proof), fall through to today's `ahead` check and everything after it, unmodified. AC: T1-T4 in `## Test plan` below.
- [ ] TASK-2: Guard the origin-branch delete (`lib/wrap/wrap.sh:2610-2628`) against a ref that is already gone: `git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}"` (or equivalent) before the `push --force-with-lease ... :refs/heads/${branch}` delete; an absent ref prints `     ${branch} already gone from origin` instead of attempting a delete that would otherwise report `FAILED delete`. This runs for both the new "already landed" path and today's normal merged path, since a squash merge's own "delete branch" setting can beat land to it either way. AC: T5 in `## Test plan`.

### Phase 2: Polish

- [ ] TASK-3: `commands/wrap.md`'s land bullet (`:118`) gets one added clause describing the merged-PR short-circuit and its "no push, no PR, still tidies" contract, next to the existing adopt-path sentence. AC: `grep -n "already landed" commands/wrap.md` finds it.
- [ ] TASK-4: `tests/test-wrap.sh`, new cases alongside the existing `land:` sections (after line 2867's happy-path block, and near the SPEC-299 adopt test at line 3434): the four cases in `## Test plan` below. AC: `bash tests/test-wrap.sh` passes with the new cases included.

**Rebase note:** `feat/wrap-pull-only` (SPEC-359) also edits `lib/wrap/wrap.sh` (its own hunks sit in `_apply_repo`/`cmd_apply`, `lib/wrap/wrap.sh:1545-1660`; confirmed by reading that branch's diff, no overlap with `cmd_land` at line 2400+ or with `_merge_proof`/`_land_ff_pull`'s definitions). The overlap here is line-number drift only, not a logic conflict, but this spec's build still rebases onto `feat/wrap-pull-only` once it merges, before opening its own PR, so the line numbers cited above are re-checked against the post-rebase file rather than assumed.

## After state

- [ ] `bin/wrap land <worktree>` on a worktree whose branch has a `MERGED` PR (no open PR) exits 0, pushes nothing, opens no PR, and still removes the worktree and deletes the local branch. (Today: it pushes the branch and opens a redundant PR.)
- [ ] The same command on a worktree whose branch has an OPEN own PR still adopts it exactly as today (unchanged).
- [ ] The same command on a worktree whose branch was re-pushed with new commits after its earlier PR merged still opens a fresh PR for the new commits. (This must not regress: `_merge_proof` returns no proof for this case because the recorded squash head differs from the current tip.)

## Acceptance Criteria (global)

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | A branch whose PR already squash-merged: no push, no PR, clean tidy | `bash tests/test-wrap.sh` (new case, T1) | exit 0; output has `already landed:`, no `pr create` call in `GH_STUB_CALLS`, worktree removed, branch deleted |
| AC2 | A branch that is a plain fast-forward ancestor of `origin/<def>` (no gh PR record at all): same clean stop | `bash tests/test-wrap.sh` (T2) | exit 0; `already landed: ancestor of origin/<def>` |
| AC3 | Adopt path unaffected | `bash tests/test-wrap.sh` (T3, the existing SPEC-299 adopt case) | still passes unmodified |
| AC4 | Re-pushed-with-new-commits still opens a fresh PR | `bash tests/test-wrap.sh` (T4) | `pr create` called; PR opened for the branch's current tip, not skipped |
| AC5 | Already-gone origin branch never reports FAILED | `bash tests/test-wrap.sh` (T5) | `<branch> already gone from origin`, not `FAILED delete` |
| AC6 | No regressions | `bash tests/test-wrap.sh && bash tests/test-meta.sh` | both exit 0 |

## Verification

```bash
bash tests/test-wrap.sh
bash tests/test-meta.sh
```

## Test plan

Date: 2026-09-30

Fixture base: `tests/test-wrap.sh`'s existing `land:` block (`build_land`, around line 2814) already gives a hand-made worktree with a real git remote and a stubbed `gh`; these cases extend it rather than building a new harness. The stub keys are the ones the file already uses elsewhere: `GH_STUB_MERGED_<branch-sanitized>` answers `gh pr list --head <branch> --state merged` (the call `_squash_json`/`_merge_proof` make), `GH_STUB_OPEN_HEAD_<branch-sanitized>` answers the same call with `--state open`, both default to `[]` when unset (`tests/test-wrap.sh:74-94`).

| # | Case | Kind | Covers | Proof |
|---|---|---|---|---|
| T1 | `build_land squashed`: worktree branch unchanged since a squash merge; `GH_STUB_MERGED_feat_land` set to one entry with `headRefOid` = the worktree's own tip, `baseRefName=main`, a non-null `mergedAt`; `GH_STUB_OPEN_HEAD_feat_land` unset (`[]`) | positive | AC1 | `land` exits 0; output has `already landed: squash-merged per gh`; `GH_STUB_CALLS` has no `pr create` line; worktree path is gone; local branch deleted |
| T2 | `build_land ffmerged`: no `GH_STUB_MERGED_*` set at all, but the bare remote's `main` is fast-forwarded to already include the worktree branch's tip commit (a plain merge, no PR record) | positive | AC2 | `land` exits 0; output has `already landed: ancestor of origin/main`; no `pr create` call; worktree removed |
| T3 | The existing SPEC-299 adopt case (`tests/test-wrap.sh:3434`, an operator-owned OPEN PR for the branch) | regression control | AC3 | Unmodified: still adopts the open PR, unaffected by the new early check (no merge proof exists for an open, unmerged PR) |
| T4 | `build_land repushed`: `GH_STUB_MERGED_feat_land` set with `headRefOid` = an OLDER commit on the branch (the state at the time the earlier PR merged), while the worktree's current tip has one additional commit on top (the re-push) | **negative control** | AC4 | `_squash_verdict` must return `TIP <old-sha>`, not `OK`; `land` takes today's unchanged path: `pr create` IS called, a fresh PR opens and merges for the branch's current (post-re-push) tip. A land that wrongly treated this as "already landed" would silently drop the new commit -- this is the exact case this spec must not regress |
| T5 | Same as the existing happy-path case (`tests/test-wrap.sh:2852`), but with the origin remote's `feat/land` ref deleted before `land` runs (simulating GitHub's auto-delete-branch-on-merge) | positive | AC5 | Output reads `feat/land already gone from origin`, never `FAILED delete` |

Dry trace for the negative control (T4): the worktree's local `refs/heads/feat/land` points at tip `C` (`A -> B -> C`, where `B` is what the earlier PR's squash actually merged). `_merge_proof` runs: not an ancestor of `origin/main` (`C` was never pushed there); `_absorbed` compares paths changed since `merge-base(feat/land, origin/main)` -- `C`'s own change is not on `origin/main`, so the trees differ, not absorbed; `_squash_json --head feat/land --state merged` returns the stub's one entry with `headRefOid=B`; `_squash_verdict` compares `B` against `tip=C`: no match, `baseRefName=main` matches but the tip differs, so it returns `TIP <B>`, not `OK`. `_merge_proof` returns non-zero (no proof). `cmd_land` therefore falls through, unchanged, to the `ahead` check (`C` is ahead of `origin/main` by one commit -- the fresh work), pushes, finds no open PR, and opens a new one. Reverting TASK-1 (removing the early `_merge_proof` call, or wrongly matching on `baseRefName` alone without the tip) makes T1 alone go red, or makes T4 wrongly report `already landed` and skip the new commit, which is the failure this control exists to catch.

## Edge Cases

1. Branch has a `MERGED` PR into a DIFFERENT base than `<def>` (landed somewhere else): `_squash_verdict` returns `BASE <name>`, not `OK`, so `_merge_proof`'s squash check returns no proof; land falls through and opens a PR against `<def>` as today. Correct: a merge into another branch is not a merge into the default branch.
2. Branch's PR was closed WITHOUT merging (abandoned): no open PR, no merged PR (`_squash_json --state merged` never lists it), not an ancestor, not absorbed. `_merge_proof` returns no proof; land opens a fresh PR, as it should -- an abandoned attempt is not a landed one. No change needed; named here because it looks similar to the bug at a glance.
3. `wrap.delete_merged_remote_branches` is `false`: the already-landed path still skips the origin-branch delete and reports it the same way the normal merged path already does (`lib/wrap/wrap.sh:2613-2614`), unchanged.
4. The worktree is dirty when land runs: the existing dirty-check (`lib/wrap/wrap.sh:2442-2444`) still refuses before the new proof check ever runs; unaffected.
5. `_merge_proof`'s ancestor check and `_absorbed` both need only local git state (no network); the squash check needs `gh`, already required by land's upfront `_gh_state` check. No new network dependency is introduced, only an additional local-first call into an existing helper.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `gh` reachable at land's startup check but the later squash-list call inside `_merge_proof` times out or errors | `_squash_json`'s `gh pr list ... 2>/dev/null` returns empty on any failure, indistinguishable from "no merged PR found"; `_merge_proof` then reports no proof | Land falls through to its unchanged existing path (push + open-PR lookup + create), i.e. today's exact behavior -- worst case is the original bug's symptom returns for that one run, never a false "already landed" that skips a real merge. Hardening `_squash_json` to distinguish a failed call from an empty result is a shared change across every caller (`_merge_proof`, `_apply_worktrees`, `_autoland_carry`) and is out of scope here (see `## Out of Scope`) |
| PR closed without merging | `_squash_json --state merged` never lists a closed-unmerged PR | Already correct, no fix needed (Edge case 2) |
| Branch re-pushed with new commits after its earlier PR merged | `_squash_verdict` returns `TIP <old-sha>`, not `OK`, because the recorded merged head differs from the branch's current tip | `_merge_proof` returns no proof; land takes today's unchanged path and opens a fresh PR for the new commits (AC4/T4). This is the hard case named in the incident brief and the reason this spec's Depth is `blind-spot` |
| Origin already deleted the branch (squash-merge auto-delete) before land's tidy runs, in either the new or the existing merged path | A delete attempt on an absent ref | TASK-2's `ls-remote --exit-code` guard reports `already gone from origin` instead of `FAILED delete` |
| Fast-forward pull of the main checkout is blocked (dirty tracked file, wrong branch checked out) | `_land_ff_pull` returns non-zero, or `cur != def` | Unchanged from today: `PULL BLOCKED`, tidy continues, worktree/branch removal still runs |

## Out of Scope

- Hardening `_squash_json`/`_squash_verdict` to distinguish a failed `gh` call from a genuinely empty result. That helper is shared by `_merge_proof`, `_apply_worktrees`, and `_autoland_carry`; changing its failure semantics is a separate, cross-cutting change.
- Recording a `ship` gate ledger line for the original PR (PR A in the incident) when `wrap land` takes the already-landed short-circuit. `/kit:ship` or an earlier `land` run already records that PR's ship gate on its own path; this spec only stops the redundant push/PR/merge and tidies, it does not add a new ledger-recording branch for a PR this run never opened.
- Any change to `_merge_proof`, `_absorbed`, `_squash_json`, or `_squash_verdict` themselves. This spec is `cmd_land` calling an existing, already-trusted check earlier, not new proof logic.
- `feat/wrap-pull-only` (SPEC-359)'s own scope (`cmd_apply --pull-only`). No shared logic beyond the same file.

## Touches

Not applicable -- this spec is built by one worker in its own worktree, not fanned out via `/kit:dispatch`.

## Siblings

| Spec or branch | Relation |
|---|---|
| `feat/wrap-pull-only` (SPEC-359) | Also edits `lib/wrap/wrap.sh`, in `_apply_repo`/`cmd_apply` (`:1545-1660`), not `cmd_land` or `_merge_proof`. Confirmed by reading that branch's diff: no hunk near either. Line-number drift only; this spec's build rebases onto it once it merges, before opening its own PR, and re-checks the cited line numbers post-rebase rather than assuming them |

## Decision Log

- DEC-1: Reuse `_merge_proof` rather than widening the open-PR lookup to `--state all` (Approach A). Rejected A because it only catches the gh-recorded-squash case and re-derives logic `_merge_proof` already gets right for the ancestor and absorbed cases.
- DEC-2: The proof check runs unconditionally after the fetch, before the `ahead` refusal, so a plain fast-forward-merged branch (`ahead == 0`, today's silent refusal with no tidy) is fixed by the same change as the squash case, not as a second special case.
- DEC-3: A re-pushed-with-new-commits branch is deliberately left on today's unchanged path (no proof found) rather than given any new special-case logic, because `_merge_proof`'s existing tip comparison already resolves it correctly.

## Grounding

- The bug: in a consumer repo adopted into this operate-contract, PR A squash-merged on a feature branch, then `bin/wrap land` on the same worktree opened and merged PR B with an identical diff -- reported directly in this task's brief, not independently re-observed (no access to that repo's PR history from this worktree).
- `_merge_proof`'s three checks and their call sites: read directly, `lib/wrap/wrap.sh:441-461` (definition), `:581-583` (`_apply_worktrees`'s use before a worktree/branch removal), `:1346-1349` (`_autoland_carry`'s squash-only use before deciding to open a PR).
- The exact decision point: `lib/wrap/wrap.sh:2479-2537`, read in full; the `else` arm creating a new PR sits at `:2521-2537`, reached whenever `open_count` is 0 (`:2489-2493`).
- `feat/wrap-pull-only` (SPEC-359) overlap check: `git diff origin/master...HEAD -- lib/wrap/wrap.sh` in that worktree, hunks confined to `lib/wrap/wrap.sh:1545-1660` (`_apply_repo`/`cmd_apply`); no hunk near `cmd_land` (`:2400+`) or `_merge_proof`/`_land_ff_pull`'s definitions.
- Cannot be sampled live: there is no reachable copy of that consumer repo's PRs A/B from this worktree to re-verify the incident's gh state directly; the incident description in the task brief is taken as given, and the fix is grounded instead in this repo's own `_merge_proof` mechanism and its existing callers.

## Open questions

(none; the operator named the exact incident, the required merged-PR detection rule (reuse `_merge_proof`), the "stops cleanly, tidies as normal" contract, and the hard case to spell out (re-push with new commits))
