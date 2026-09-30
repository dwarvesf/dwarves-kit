# Spec: wrap land recognizes an already-merged own PR before opening a new one
Generated: 2026-09-30
Status: DRAFT
Lane: full
Depth: blind-spot (failure: a branch re-pushed with new commits after its own PR already merged must still open a fresh PR for those new commits; a detection rule that only checks "does gh already call this PR MERGED" could wrongly treat the whole branch as landed and silently drop the new commits. Round 1 validation also found four more blind spots in the first draft -- a lock-destroying reorder, an unleased origin-branch delete, a missing origin-freshness check, and a silently-closed coexisting PR -- which is why this depth held rather than getting downgraded after the first pass)
References: `lib/wrap/wrap.sh:441-461` (`_merge_proof`, the ancestor/absorbed/squash proof `wrap apply`'s worktree tidy already trusts for "this branch is already merged, tidy it"); `lib/wrap/wrap.sh:1325-1349` (`_autoland_carry`, the one other caller that checks a squash proof AND an origin-freshness ls-remote before deciding to open a PR at all -- both patterns this spec reuses); `lib/wrap/wrap.sh:581-597` (`_apply_worktrees`, the fetch-then-proof-then-recheck-then-lock-guard sequence this spec mirrors for `cmd_land`); `docs/verification/wrap-land.md:3` (the documented refusal list, including "no commits ahead of the default branch," that this spec keeps unchanged).

## Problem

On 2026-09-30, in a consumer repo adopted into this operate-contract, PR A on a feature branch was squash-merged. `bin/wrap land <worktree>` then ran on the same worktree, which still held the pre-merge commits. It:

1. Pushed the stale worktree copy of the feature branch to origin (harmless by itself -- the branch ref, not the default branch).
2. Looked up open PRs for that branch, found none (PR A is `MERGED`, not `OPEN`), and fell through to `gh pr create`.
3. Opened PR B with a diff byte-identical to PR A's already-landed content, then squash-merged PR B too.

Expected: land notices the branch's own PR already merged (or that the branch's content is already on the default branch by another proven route), stops without pushing or opening anything, and tidies the worktree the same way a normal post-merge land does. The adopt path (an already-OPEN own PR for the branch) is unaffected and must keep working exactly as it does today. A round-1 validation pass (7 parallel reviewers) found the first draft's ordering would have introduced a worse bug than the one it fixed -- see `## Design` and `## Decision Log` for the corrected shape.

## Root cause

`cmd_land` (`lib/wrap/wrap.sh:2408` onward) has no step that asks "has this branch's content already landed?" before deciding to push and open a PR. Two things hide the fact from it:

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

`wrap.sh` already has the check land is missing: `_merge_proof` (`lib/wrap/wrap.sh:441-461`) answers "has this branch already reached the default branch," across three routes -- a plain ancestor, tree-identical content absorbed without a matching PR (`_absorbed`), or a gh-recorded squash merge (`_squash_json` / `_squash_verdict`, the same helper `_autoland_carry` already checks at `:1346-1349` before it will open a PR). `wrap apply`'s worktree-tidy pass (`lib/wrap/wrap.sh:581-583`) already calls `_merge_proof "$repo" "$def" "$ghs" "$wtb"` before removing a worktree and deleting its branch. `cmd_land` is the one caller that reaches the same "should I open a PR / should I tidy this worktree" fork without ever asking that helper.

**A mathematical fact that shapes where this check may run:** `ahead` (line 2456) and `_merge_proof`'s ANCESTOR route (`lib/wrap/wrap.sh:449-451`, `merge-base --is-ancestor refs/heads/<b> refs/remotes/origin/<def>`) are mutually exclusive. If the branch tip is an ancestor of `origin/<def>`, then every commit reachable from the branch is already reachable from `origin/<def>`, so `origin/<def>..<branch>` (what `ahead` counts) is empty and `ahead` is 0. `cmd_land` already refuses outright at `ahead == 0` (`:2458-2459`, documented at `docs/verification/wrap-land.md:3`) before this spec's new check ever runs. So **the ancestor route can never fire from this call site**: only the absorbed and gh-squash routes are reachable once the check is gated behind `ahead > 0` (see `## Design`, Decision 1). This also means a brand-new, zero-commit `wrap start` worktree -- trivially an ancestor of `origin/<def>` -- never reaches the new code at all; it still refuses at `ahead == 0` exactly as today.

## Solution

### Approaches considered

| # | Approach | Tradeoff |
|---|---|---|
| A | Widen the open-PR lookup to `--state all` and special-case a `MERGED` result | Catches the squash-merged-PR case only; still blind to content absorbed without a matching PR (e.g. a subagent branch a lead re-committed under its own PR), and re-derives a check `_merge_proof` already gets right |
| B | Call `_merge_proof` after the existing `ahead > 0` gate; a proof found (guarded, see `## Design`) skips to a shared tidy tail; no proof falls through to today's push/PR/merge path, which now ends at the same tidy tail | One extra call to a helper this file already trusts for the identical question, plus the guards `_apply_worktrees` and `_autoland_carry` already carry for exactly this kind of check (fetch-rc, dirty/tip recheck, lock-live, origin-freshness) |
| C | A narrower, gh-only check: call `_squash_json`/`_squash_verdict` directly against the local tip, skipping `_merge_proof`'s ancestor and absorbed routes entirely | Smaller diff and no dependency on `_absorbed`'s tree walk, but blind to the absorbed-content route entirely (a branch whose net change landed without ever having its own merged PR, e.g. a re-committed subagent branch, or `wrap merge`'s `<branch>-squash` fallback that leaves the original PR open -- commands/wrap.md:116). It still needs the same post-round-trip guards B does, since it still makes a network call, so it saves no guard code, only the one extra `_absorbed` tree walk. Rejected: it trades real coverage for a saving that does not materialize |

### Chosen approach + why

B. `_merge_proof` already owns the enumeration of "how a branch's content can already be on the default branch" and is exercised in production by two other callers; land reusing it, gated behind the pre-existing `ahead > 0` refusal and wrapped in the same guards those callers already carry, is the only approach that closes the absorbed and gh-squash cases at once without opening the lock-destruction risk round 1 found in a naive "check before the ahead gate" ordering (Decision 1 below), and without inventing new proof logic a second way (C's narrower rewrite would still need every guard B needs, for strictly less coverage).

### Extensibility & boundaries

- Load-bearing dimension: the set of ways a branch's content can already be on the default branch. `_merge_proof` already owns that enumeration; this spec adds no fourth way, and reachable here it is really only two of the three (ancestor is excluded by construction, see `## Root cause`).
- Unit boundary: a shared `_land_tidy` helper (Decision 6 below) is the one new named unit; the proof-and-guards block that decides whether to call it stays inline in `cmd_land`, used once, per the "if it needs a name and is used more than once, extract it" line this spec draws.

## Design

**Decision 1 -- the check runs AFTER today's `ahead == 0` refusal, never before it.** The incident is a squash merge, and squash merges always leave `ahead > 0` (see `## Root cause`'s mutual-exclusion fact), so nothing about the incident needs the check to run any earlier. Running it before the `ahead` refusal, so it could also cover a plain fast-forward merge (`ahead == 0`), was the first draft's approach and round 1 found it dangerous: a freshly-created, zero-commit `wrap start` worktree is trivially an ancestor of `origin/<def>` (`_merge_proof`'s first route, `:449-451`), so the old ordering would have force-removed it (`worktree remove -f -f`, `:2648`, which overrides the Agent tool's own lock) and deleted its branch -- destroying a live agent's ignored files and uncommitted work, and reversing the documented refusal at `docs/verification/wrap-land.md:3`. The fix stays scoped to the incident: after `ahead > 0` is already established, ask whether the ahead-looking commits are actually already landed.

**Decision 2 -- `tip` and `url` move above the branch point.** They are declared at `:2461-2463` today, after the `ahead` refusal; the tail already reads them at (today's) `:2616` (the origin-branch delete's `--force-with-lease=...:${tip}`) and `:2620` (`_origin_url`-derived `$url`). Once the new check can jump straight to the tidy tail without ever reaching `:2461-2463`, those two locals must already be set before that branch point, or the tail reads an unbound variable under `set -uo pipefail` (`:81`). The origin-branch delete leases ONLY to this proven local `$tip` -- the SHA `cmd_land` itself verified, never a value later read back from origin.

**Decision 3 -- the guards `_apply_worktrees` and `_autoland_carry` already carry, reused here.** `_merge_proof`'s gh-squash route is a network round trip; time passes while it runs. Before trusting a proof:
- the `git fetch origin "$def"` call (`:2455`, its `rc` silenced today) is checked; a failed fetch skips the new check entirely and falls back to today's unchanged path -- a fetch failure proves nothing either way, so it is never read as "not landed" or "landed," it is read as "cannot tell, do what we always did";
- after the round trip, the worktree's dirty state and local tip are re-read and compared against what was captured before the round trip, the same shape `_apply_worktrees` uses at `:587-593` (a live process could still be committing to this exact branch while `_merge_proof` runs); a mismatch refuses by name rather than acting on a stale snapshot;
- the worktree's lock is checked with `_wt_lock_live` (`:521-525`), the same guard `_apply_worktrees` reads at `:596`; a live pid refuses by name rather than touching a worktree an agent may still be writing to.

**Decision 4 -- origin freshness, mirroring `_autoland_carry`'s `:1343-1345`.** A proof is about the LOCAL tip; it says nothing about whether origin's copy of `<branch>` has moved past that tip since the worktree last knew about it. Before printing "already landed," `cmd_land` reads `git ls-remote origin refs/heads/<branch>` and compares it to the proven local `$tip`. Three outcomes: the ref is absent (fine -- already deleted, nothing to compare, proceed); it matches `$tip` (fine, proceed); it names something else (refuse loudly by name -- `origin/<branch> holds <sha>, ahead of the proven <tip>` -- and touch nothing, because pushed work would otherwise be reported "already landed" while it is not landed anywhere this run can see).

**Decision 5 -- a coexisting OPEN PR is reported, never silently resolved.** `_merge_proof` can return a proof (typically the absorbed route) while an open PR for this exact branch still exists -- either by coincidence, or by design: `wrap merge`'s `<branch>-squash` fallback (`commands/wrap.md:116`) commit-trees the merged tree onto a sibling branch and PR, and deliberately leaves the ORIGINAL PR for `<branch>` open for a manual close. When the (reused, not re-queried -- see Interfaces) open-PR lookup for this branch returns one or more results at the same time the proof holds, `cmd_land` reports BOTH facts on their own lines and refuses: no push, no PR opened, no origin-branch delete, no worktree or local-branch removal. This spec's own judgment call, since the decision above does not name the worktree's fate explicitly: leaving the worktree and local branch untouched too is the conservative reading of "leave ... untouched," and it keeps the operator's ability to inspect or close that PR from the same worktree.

**Decision 6 -- a shared `_land_tidy` helper.** The tail both paths need (origin-branch delete leased to `$tip`, fast-forward-pull the main checkout, remove the worktree, delete the local branch, the existing exit-0-unless-blocked convention at `:2661`) is about 50 lines today (`:2610-2662`) and was going to be needed twice (the new short-circuit path and the unchanged existing path) or duplicated. A named helper, `_land_tidy <repo> <wt> <branch> <def> <url> <tip>`, replaces the inline block; both `cmd_land` paths call it once, at the end. **The origin-branch delete runs on the already-landed path too** (Interfaces, Picture and Task Breakdown all agree on this): a proven-landed branch is exactly the branch whose origin ref is safe to retire, leased to the tip `cmd_land` itself proved, per Decision 2.

### Diagram

See `## Picture`.

### ADR link(s)

None. This is a local bug fix inside an existing, already-designed helper (`_merge_proof`) plus one small extraction (`_land_tidy`); it makes no new lasting architectural decision.

### Boundaries & failure modes

See `## Failure modes` below.

## Picture

```
                     bin/wrap land <worktree>
                              |
                    resolve wt/repo/branch/def, protected-name refusal
                    _gh_state == ok  (else refuse, as today)
                              |
              MOVED UP: tip=$(git rev-parse HEAD); url=$(_origin_url)   (Decision 2)
                              |
                    git fetch origin <def>; fetch_ok=$?          (rc now checked, Decision 3)
                              |
                    ahead=$(rev-list --count origin/<def>..<branch>)
                    ahead == 0  --------------------------------------->  REFUSE, as today
                    (a fresh zero-commit worktree stops HERE, unchanged)  (docs/verification/wrap-land.md:3)
                              |  ahead > 0
                    open_json = gh pr list --head <branch> --state open   (moved up, computed ONCE,
                              |                                            reused by both branches below)
              fetch_ok? --no--> proof="" (skip the new check; today's path, unchanged)
                  | yes
              NEW: proof="$(_merge_proof "$repo" "$def" "$ghs" "$branch")"
                    /                                    \
          proof found                               proof NOT found
   (content absorbed, or                         (genuinely unlanded work,
    gh-recorded squash merge --                    OR re-pushed with new
    the ancestor route cannot                       commits past what merged,
    fire here, see Root cause)                       OR fetch failed)
          |                                                |
   re-check dirty + tip (Decision 3)                 unchanged today's path:
   refuse if changed since capture                   push branch
          |                                          open-PR lookup already computed above
   refuse if _wt_lock_live (Decision 3)              adopt (1 open) / refuse (>1)
          |                                          create PR (0 open)  <-- PR B bug lived here
   ls-remote origin refs/heads/<branch>               squash-merge -> tree-verify
   vs proven tip (Decision 4)                               |
   mismatch --------------------------> REFUSE, name it, touch nothing
          |  matches or absent
   open_json (computed above) has >=1 entry for <branch>?
          |                                    \
         no                                    yes (Decision 5)
          |                                     |
   print "already landed: <proof>;      print "already landed: <proof>" AND
   nothing to push, no PR opened"        "PR #<n> still open for <branch>: left untouched"
          |                                     |
   _land_tidy (Decision 6, origin              REFUSE (no push, no PR, no origin delete,
   delete DOES run, leased to $tip)            no worktree/branch removal)
          |
          `----------------> _land_tidy <----------------' (unchanged path's end, too)
                    fast-forward-pull main checkout
                    (origin-branch delete: `ls-remote --exit-code` -- only
                     exit 2 means "already gone," any other non-zero keeps
                     the FAILED delete line, per the Failure modes table)
                    remove worktree, delete local branch
                    exit 0, or 2 on PULL BLOCKED / a failed removal
```

## Technical Design

### Interfaces (I/O contract)

- Consumes: `_merge_proof <repo> <def> <ghs> <branch>` (unchanged signature, no edit to the helper itself), called with `repo` (the main checkout, resolved at `:2435-2437`), matching `_apply_worktrees`'s exact call shape at `:581`. Also consumes `_wt_lock_live <worktree path>` (`:521-525`) and a new `git ls-remote origin refs/heads/<branch>` read, mirroring `_autoland_carry`'s `:1343`.
- Produces: `_land_tidy <repo> <wt> <branch> <def> <url> <tip>` (new), the single tail both the already-landed short-circuit and today's unchanged merge path call. It performs the origin-branch delete (leased to `$tip`; the `ls-remote --exit-code` guard treats exit 2 as "gone," any other non-zero as an unknown failure that keeps trying the delete and reports `FAILED` on refusal), the fast-forward pull, the worktree removal, and the branch delete, in that order, exactly as today's tail does.
- Exit code: **0 on a clean land or a clean already-landed stop; 2 when `_land_tidy` hits `PULL BLOCKED` or a failed worktree/branch removal** (unchanged from today's `:2661` convention, now shared by both paths); 1 on any refusal before `_land_tidy` runs (dirty worktree, no branch, protected name, `gh` not ok, no commits ahead, a stale dirty/tip/lock/origin-freshness re-check, or a coexisting open PR per Decision 5); 2 also on a `gh pr create`/merge/tree-verify failure on the unchanged path, as today.
- Invariant: the adopt path (`open_count -eq 1`) and the create-new-PR path (`open_count -eq 0`, no proof) are behaviorally unchanged; only the branch that reaches them changes (a proven-landed branch with no coexisting open PR never reaches either now), and the open-PR lookup itself runs exactly once per `land` call regardless of which path is taken.

### Data model changes

None.

### API changes

None (internal script only).

### UI changes

Two new stop-line shapes:
- `     already landed: <proof>; nothing to push, no PR opened` (the clean short-circuit), where `<proof>` is one of `content already on origin/<def>` or `squash-merged per gh` (never `ancestor of origin/<def>`, per `## Root cause`).
- `     already landed: <proof>` followed by `     PR #<n> still open for <branch>: left untouched` (Decision 5's coexisting-PR refusal).
Plus one new refusal line for Decision 4 (`origin/<branch> holds <sha>, ahead of the proven <tip>`) and one rewritten origin-delete failure line distinguishing "already gone" from an unknown `ls-remote` failure.

### Infrastructure changes

None.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-1: Tail-state setup. Move `local tip url rc; tip=...; url=...` (today's `:2461-2464`) above the fetch/ahead block, right after the `ghs` check (`:2452-2453`). Add `fetch_ok` tracking to the existing `git -C "$wt" fetch -q origin "$def"` call (`:2455`) without changing its silenced stderr. Leave the `ahead == 0` refusal (`:2456-2459`) exactly where it is and exactly as it reads today -- no new code runs before it, so a zero-commit worktree still refuses there unchanged. AC: T8 in `## Test plan`.
- [ ] TASK-2: Extract `_land_tidy <repo> <wt> <branch> <def> <url> <tip>` from today's tail (`:2610-2662`): the origin-branch delete (leased to `$tip`), the fast-forward pull, the worktree removal, the branch delete, the `return 2`-on-block convention. Refine the origin-branch delete's absence check: `git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}"`; treat ONLY exit code 2 as "the ref is gone" (print `${branch} already gone from origin`); any other non-zero exit (network, auth, a transient error) falls through to the existing delete attempt and its existing `FAILED delete` line, never assumed gone. Call `_land_tidy` from the end of today's unchanged merge path with no behavior change (AC9, no regressions). AC: T4, T5 in `## Test plan`.

### Phase 2: Core

- [ ] TASK-3: The proof call and its guards. Move the open-PR lookup (today's `:2479-2491`) up to run once, right after the `ahead > 0` gate, before the fetch-failure branch -- both the already-landed path and the unchanged path read the same `open_json`/`open_count`, never a second `gh pr list --head ... --state open` call. When `fetch_ok`, call `proof="$(_merge_proof "$repo" "$def" "$ghs" "$branch")"`. On a non-empty proof: re-check dirty state and the local tip against the values captured before the round trip (refuse by name on a mismatch, per Decision 3); refuse if `_wt_lock_live "$wt"` (Decision 3); read `git ls-remote origin refs/heads/<branch>` and refuse by name if it names something other than the proven `$tip` (Decision 4); if `open_count -ge 1` for this branch, print both the proof and the open-PR line and refuse, touching nothing (Decision 5); otherwise print the "already landed" stop line and call `_land_tidy`. On an empty proof (including a failed fetch), fall through unchanged to today's push/PR/merge path, which now also ends by calling `_land_tidy`. AC: T1, T1b, T2, T3, T6, T7 in `## Test plan`.

### Phase 3: Polish

- [ ] TASK-4: `commands/wrap.md`'s land bullet (`:118` in this worktree's copy; re-check after the rebase noted below) gets one added clause describing the merged-PR short-circuit, its guards, the origin-freshness refusal, and the coexisting-open-PR report-and-refuse, next to the existing adopt-path sentence. AC: `grep -n "already landed" commands/wrap.md` finds it.
- [ ] TASK-5: `tests/test-wrap.sh`, new cases alongside the existing `land:` sections (after line 2867's happy-path block, and near the SPEC-299 adopt test at line 3434): T1, T1b, T2-T8 in `## Test plan` below. AC: `bash tests/test-wrap.sh` passes with the new cases included.

**Rebase note:** see `## Siblings`. This spec's build rebases onto whichever of the two branches lands second, and re-runs `bash tests/test-wrap.sh` after, before opening its own PR, rather than assuming the cited line numbers above still hold.

## After state

- [ ] `bin/wrap land <worktree>` on a worktree whose branch has a `MERGED` PR (no open PR) AND whose local tip exactly matches what gh recorded as merged (or whose content is absorbed on the default branch) exits 0, pushes nothing, opens no PR, and still deletes the origin branch and the local branch and removes the worktree. (Today: it pushes the branch and opens a redundant PR.) This claim is deliberately narrower than "any already-merged branch": a LOCAL TIP BEHIND its own merged PR's recorded head (see Edge Cases) is not detected and still repeats a version of the incident.
- [ ] The same command on a worktree whose branch has an OPEN own PR still adopts it exactly as today (unchanged).
- [ ] The same command on a worktree whose branch was re-pushed with new commits after its earlier PR merged still opens a fresh PR for the new commits.
- [ ] The same command on a worktree whose branch is proven landed but still carries an open PR for itself reports both facts and refuses, touching nothing.
- [ ] The same command on a worktree whose origin copy of the branch holds commits beyond the proven local tip refuses by name rather than claiming "already landed."
- [ ] A freshly-created, zero-commit worktree still refuses at `ahead == 0`, unchanged, and is never force-removed by this spec's new code.

## Acceptance Criteria (global)

| # | Criterion | Command | Pass |
|---|---|---|---|
| AC1 | A branch whose PR already landed (absorbed content, or a gh-recorded squash record) with no open PR: no push, no PR, clean tidy including the origin-branch delete | `bash tests/test-wrap.sh` (T1, T1b) | exit 0; output has `already landed:` with the proof text that fixture actually produces; no `pr create` call; origin-delete line present; worktree removed, branch deleted |
| AC2 | Adopt path unaffected | `bash tests/test-wrap.sh` (T2, the existing SPEC-299 adopt case) | still passes unmodified |
| AC3 | Re-pushed-with-new-commits still opens a fresh PR | `bash tests/test-wrap.sh` (T3) | `pr create` called; PR opened for the branch's current tip, not skipped |
| AC4 | Already-gone origin branch (`ls-remote --exit-code` returns 2) never reports FAILED | `bash tests/test-wrap.sh` (T4) | `<branch> already gone from origin`, not `FAILED delete` |
| AC5 | A non-2 `ls-remote` failure never reports "already gone" | `bash tests/test-wrap.sh` (T5) | `FAILED delete` line, not `already gone from origin` |
| AC6 | Origin ahead of the proven local tip: refuse loudly, claim nothing, delete nothing | `bash tests/test-wrap.sh` (T6) | non-zero exit; output names the origin sha and the proven tip; no `already landed` line; no origin-branch delete attempted |
| AC7 | A coexisting open PR alongside a proof: report both, refuse, leave everything untouched | `bash tests/test-wrap.sh` (T7) | non-zero exit; both an `already landed:` line and a `still open for` line print; no push, no PR create/merge, no origin delete, worktree and local branch still present |
| AC8 | A zero-commit fresh worktree still refuses exactly as today | `bash tests/test-wrap.sh` (T8) | `has no commits ahead of origin/<def>`, exit 1, worktree untouched, no `_merge_proof` call made (nothing to prove would need proving) |
| AC9 | No regressions | `bash tests/test-wrap.sh && bash tests/test-meta.sh` | both exit 0 |

## Verification

```bash
bash tests/test-wrap.sh
bash tests/test-meta.sh
```

## Test plan

Date: 2026-09-30

Fixture base: `tests/test-wrap.sh`'s existing `land:` block (`build_land`, around line 2814) already gives a hand-made worktree with a real git remote and a stubbed `gh`; these cases extend it rather than building a new harness. Stub keys already in the file: `GH_STUB_MERGED_<branch-sanitized>` answers `gh pr list --head <branch> --state merged` (what `_squash_json`/`_merge_proof` call), `GH_STUB_OPEN_HEAD_<branch-sanitized>` answers the same call with `--state open`, both default to `[]` when unset (`tests/test-wrap.sh:74-94`).

| # | Case | Kind | Covers | Proof |
|---|---|---|---|---|
| T1 | `build_land squashed-absorbed`: the bare remote's `main` is updated (before `land` runs) by a commit whose net change, for every path the worktree branch itself touched, is byte-identical to the branch tip -- a plain squash merge with nothing else landed since. No `GH_STUB_MERGED_*` set at all (this route needs no gh call). `GH_STUB_OPEN_HEAD_feat_land` unset | positive | AC1 | `_merge_proof` returns via the ABSORBED route (`_absorbed` succeeds before the squash check ever runs); output reads `already landed: content already on origin/main`; `GH_STUB_CALLS` has no `pr create` line and, since this route needs no gh squash lookup, no `--state merged` call for this head either; origin-delete line present; worktree removed |
| T1b | `build_land squashed-gh`: same starting shape as T1, but ONE MORE commit lands on the bare remote's `main` after the squash, editing one of the SAME paths the worktree branch touched (so `_absorbed` now fails for that path -- the trees genuinely differ). `GH_STUB_MERGED_feat_land` set to one entry with `headRefOid` = the worktree's own tip, `baseRefName=main`, a non-null `mergedAt`. `GH_STUB_OPEN_HEAD_feat_land` unset | positive | AC1 | `_absorbed` fails; `_squash_verdict` still returns `OK` (the gh record is unaffected by the later edit); output reads `already landed: squash-merged per gh`; no `pr create` call; origin-delete line present |
| T2 | The existing SPEC-299 adopt case (`tests/test-wrap.sh:3434`, an operator-owned OPEN PR for the branch, no merge proof) | regression control | AC2 | Unmodified: still adopts the open PR |
| T3 | `build_land repushed`: `GH_STUB_MERGED_feat_land` set with `headRefOid` = an OLDER commit on the branch (the state at the time the earlier PR merged), while the worktree's current tip has one additional commit on top (the re-push) | **negative control** | AC3 | `_squash_verdict` returns `TIP <old-sha>`, not `OK`; `_absorbed` also fails (the new commit's own path is not on origin/main); `land` takes today's unchanged path: `pr create` IS called for the branch's current (post-re-push) tip |
| T4 | Same starting shape as T1's squash, but the origin remote's `feat/land` ref is deleted before `land` runs (GitHub's auto-delete-branch-on-merge) | positive | AC4 | `ls-remote --exit-code` returns 2; output reads `feat/land already gone from origin`, never `FAILED delete` |
| T5 | Same as T4, but the stub's `ls-remote` is made to fail with a non-2, non-zero exit (simulating a transient network/auth error, not "ref not found") | **negative control** | AC5 | The delete attempt still runs (never short-circuited as "gone"); on the stub's existing push-based delete failing too, output reads `FAILED delete feat/land on origin`, never `already gone from origin` |
| T6 | Same starting shape as T1's squash (proof holds against the LOCAL fetch's view of origin), but the stub's `ls-remote origin refs/heads/feat/land` reports a SHA one commit ahead of the proven tip (someone pushed more to `feat/land` after the worktree's clone last saw it, before `land` ran) | **negative control** | AC6 | `land` refuses: output names the origin sha and the proven tip; no `already landed` line; no push (still, per the proof); no origin-branch delete; worktree and branch untouched |
| T7 | Same starting shape as T1's absorbed case, but `GH_STUB_OPEN_HEAD_feat_land` is set to one open PR for `feat/land` | **negative control** | AC7 | `land` reports both `already landed: content already on origin/main` and a `still open for` line, then refuses (non-zero exit); `GH_STUB_CALLS` has no `pr create`, no `pr merge`, no origin-branch delete attempt; the worktree and local branch are still present afterward |
| T8 | `build_land fresh`: a `wrap start`-shaped worktree with zero commits ahead of `origin/main` (branch created at `origin/main`'s tip, nothing committed) | regression control (the exact shape round 1 found dangerous under the old ordering) | AC8 | `ahead` is 0; `land` refuses with `has no commits ahead of origin/main`, exit 1; the worktree is still present and unlocked-or-not, its lock state never inspected, because `_merge_proof` is never called for this branch at all |

Dry trace for the negative control at T3: the worktree's local `refs/heads/feat/land` points at tip `C` (`A -> B -> C`, where `B` is what the earlier PR's squash actually merged). `_merge_proof` runs: not an ancestor of `origin/main` (impossible anyway once `ahead > 0` already held, per `## Root cause`); `_absorbed` compares paths changed since `merge-base(feat/land, origin/main)` -- `C`'s own change is not on `origin/main`, so the trees differ, not absorbed; `_squash_json --head feat/land --state merged` returns the stub's one entry with `headRefOid=B`; `_squash_verdict` compares `B` against `tip=C`: no match, `baseRefName=main` matches but the tip differs, so it returns `TIP <B>`, not `OK`. `_merge_proof` returns non-zero (no proof). `cmd_land` falls through, unchanged, to the push/open-PR-lookup/create path for the branch's current tip `C`. Reverting TASK-3 (skipping the tip/path comparison, or matching on `baseRefName` alone) makes T3 wrongly report `already landed` and silently drop commit `C`, which is the failure this control exists to catch.

Dry trace for the negative control at T6: `_merge_proof` proves the LOCAL tip landed (absorbed or squash, same as T1/T1b) -- that check only ever looks at the local worktree's ref and gh's record of it, never at origin's CURRENT state of `refs/heads/feat/land`. `ls-remote` then reads origin directly and finds a sha the proof never saw. Skipping this read (reverting TASK-3's Decision-4 step) makes T6 wrongly print `already landed` and, worse, wrongly run `_land_tidy`'s origin-branch delete leased to the stale proven tip, which is a force-with-lease delete of a ref that has moved -- git's own lease would refuse that specific push, so the observable failure moves from a silent claim to a `FAILED delete` line, but the "already landed" claim itself would already be printed and wrong. This is exactly the check this control exists to prove is present.

## Edge Cases

1. Branch has a `MERGED` PR into a DIFFERENT base than `<def>` (landed somewhere else): `_squash_verdict` returns `BASE <name>`, not `OK`, so `_merge_proof`'s squash route returns no proof; land falls through and opens a PR against `<def>` as today. Correct: a merge into another branch is not a merge into the default branch.
2. Branch's PR was closed WITHOUT merging (abandoned): no open PR, no merged PR (`_squash_json --state merged` never lists it), not absorbed. `_merge_proof` returns no proof; land opens a fresh PR, as it should -- an abandoned attempt is not a landed one.
3. `wrap.delete_merged_remote_branches` is `false`: `_land_tidy` still skips the origin-branch delete and reports it the same way on either path (`:2613-2614` today), unchanged.
4. The worktree is dirty when land runs: the existing dirty-check (`:2442-2444`) still refuses before any new code runs; unaffected.
5. **A zero-commit branch (`ahead == 0`) never reaches the new check at all**, by construction (Decision 1); it refuses exactly as today, and the ancestor route of `_merge_proof` is consequently unreachable from this call site (see `## Root cause`'s mutual-exclusion fact).
6. **Known gap, not fixed by this spec:** a local tip STALE and BEHIND its own merged PR's recorded head (a GitHub "Update branch" click, a review-suggestion commit applied on GitHub, a bot commit -- anything pushed to the PR's branch on GitHub after the worktree's clone last fetched it, before the merge). `_absorbed` correctly fails (the local tip is missing content that IS on `origin/<def>`) and `_squash_verdict` correctly returns a `TIP <newer-sha>` mismatch (gh recorded a different, newer head as merged) -- so `_merge_proof` correctly reports no proof, and land's behavior is UNCHANGED by this spec: it falls through to today's path and opens a new PR for the branch's stale, incomplete content. This does not reproduce the original incident's exact symptom (a false "already landed" claim never happens here), but it does open a PR that omits content already on the default branch, a distinct but related failure this spec does not close. Named here, and in `## After state`, because fetching only `origin/<def>` (`:2455`) rather than the branch's own remote ref means land never learns the branch moved on GitHub's side.
7. `wrap merge`'s `<branch>-squash` fallback (`commands/wrap.md:116`) leaves the original PR for `<branch>` open while its content lands via a sibling branch/PR. `_merge_proof` has no dedicated check for this route (unlike `_autoland_carry`, which additionally checks `<branch>-squash`'s own merge record at `:1347-1349`); it is caught here only indirectly, when the sibling's commit-treed content happens to satisfy `_absorbed` for `<branch>`'s own paths. When it does, Decision 5's coexisting-open-PR report-and-refuse fires (the original PR is still open). When the sibling's tree diverges enough that `_absorbed` does not hold, `_merge_proof` returns no proof and land falls through to the unchanged path -- naming a brand-new PR against an already-superseded branch. Listed under `## Out of Scope`.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `gh` reachable at land's startup check but the later squash-list or open-PR-list call errors or times out silently | `2>/dev/null` on every `gh pr list` call means a failed call and a genuinely empty result are indistinguishable; **this run gives no signal that the two cases differ** | Land takes whichever path an empty result implies -- typically today's unchanged push/PR path. Worst case is the original bug's symptom returning for that one run, never a false "already landed" that skips a real merge. Hardening the gh-call layer to distinguish a failure from an empty result is a shared change across every caller of `_squash_json` (`_merge_proof`, `_apply_worktrees`, `_autoland_carry`) and is out of scope here |
| `git fetch origin "$def"` fails | Its exit code, now checked (TASK-1) | The new proof check is skipped entirely; land falls through to today's unchanged path, which computes `ahead` off whatever `origin/<def>` locally holds (a pre-existing, unrelated behavior this spec does not change) |
| Worktree goes dirty, or its tip moves, during the gh round trip | Re-read after the round trip, compared to the pre-round-trip capture (Decision 3) | Refuses by name rather than acting on a stale snapshot; nothing is pushed, deleted, or removed |
| Worktree carries a live agent lock | `_wt_lock_live` (Decision 3) | Refuses by name; the worktree, its lock, and its branch are untouched |
| Origin's copy of `<branch>` holds commits beyond the proven local tip | `ls-remote` vs `$tip` mismatch (Decision 4) | Refuses by name, claims nothing, deletes nothing (T6) |
| A coexisting open PR for the same branch a proof also covers | The (reused) open-PR lookup returns >=1 for this branch while a proof also holds (Decision 5) | Reports both facts, refuses, leaves the origin branch, the PR, the worktree, and the local branch untouched (T7) |
| Origin already deleted the branch (squash-merge auto-delete), on either path | `ls-remote --exit-code origin refs/heads/<branch>` returns exactly 2 | Reports `already gone from origin` instead of attempting the delete (T4) |
| A non-2 `ls-remote` failure (network, auth, a transient error) | Any non-zero, non-2 exit from the same call | Never read as "gone"; the delete is still attempted and a real failure still reports `FAILED delete` (T5) |
| PR closed without merging | `_squash_json --state merged` never lists a closed-unmerged PR | Already correct, no fix needed (Edge case 2) |
| A local tip stale and behind its own merged PR's recorded head | `_squash_verdict` returns `TIP <newer-sha>`; `_absorbed` also fails | Known gap, not fixed here (Edge case 6); land's behavior is unchanged from today (opens a new, incomplete PR) |
| Branch re-pushed with new commits after its earlier PR merged | `_squash_verdict` returns `TIP <old-sha>`, not `OK` | `_merge_proof` returns no proof; land opens a fresh PR for the new commits (T3) |
| Fast-forward pull of the main checkout is blocked (dirty tracked file, wrong branch checked out) | `_land_ff_pull` returns non-zero, or `cur != def` | Unchanged from today: `PULL BLOCKED`, `_land_tidy` continues, worktree/branch removal still runs, exit 2 |

## Out of Scope

- Hardening `_squash_json`/`_squash_verdict`/the open-PR lookup to distinguish a failed `gh` call from a genuinely empty result. Shared by `_merge_proof`, `_apply_worktrees`, and `_autoland_carry`; changing its failure semantics is a separate, cross-cutting change.
- Giving `_merge_proof` (or land specifically) a dedicated check for `wrap merge`'s `<branch>-squash` fallback route, the way `_autoland_carry` layers one on top at `:1347-1349`. This spec catches that scenario only indirectly, through the absorbed route, and only when the sibling's content happens to satisfy it (Edge case 7).
- Fetching the branch's own remote ref (only `origin/<def>` is fetched, `:2455`) to detect a local tip that has fallen behind its own PR's GitHub-side updates. Known gap, Edge case 6.
- Recording a `ship` gate ledger line for the original PR (PR A in the incident) when `wrap land` takes the already-landed short-circuit. `/kit:ship` or an earlier `land` run already records that PR's ship gate on its own path; this spec does not add a new ledger-recording branch for a PR this run never opened.
- Any change to `_merge_proof`, `_absorbed`, `_squash_json`, or `_squash_verdict` themselves. This spec is `cmd_land` calling an existing, already-trusted check later and more carefully, not new proof logic.
- `feat/wrap-pull-only`'s own scope (`cmd_apply --pull-only`). See `## Siblings`.

## Touches

Not applicable -- this spec is built by one worker in its own worktree, not fanned out via `/kit:dispatch`.

## Siblings

| Spec or branch | Relation |
|---|---|
| `feat/wrap-pull-only` | Also edits three of the same files: `lib/wrap/wrap.sh` (its hunks sit at the top-of-file verb list and near `cmd_scan`/`_apply_repo`/`cmd_apply`, confirmed by reading that branch's diff -- no hunk near `cmd_land`, `_merge_proof`, or `_land_ff_pull`'s definitions), `commands/wrap.md` (a hunk in the `apply`/pull knobs area, a different paragraph from this spec's land-bullet edit, but not independently verified to never move that paragraph's line numbers), and `tests/test-wrap.sh` (new cases appended near its own pinned-config tests). No confirmed logic conflict, but three shared files is enough that neither branch should assume the other's line citations still hold. Whichever of the two lands second rebases onto the first and re-runs `bash tests/test-wrap.sh` before opening its own PR |

## Decision Log

- DEC-1: Reuse `_merge_proof` rather than widening the open-PR lookup to `--state all` (Approach A) or narrowing to a gh-only check (Approach C). A rejected because it re-derives logic `_merge_proof` already gets right; C rejected because it needs every guard B needs for strictly less coverage (misses the absorbed route).
- DEC-2 (round-1 correction): the proof check runs AFTER the existing `ahead == 0` refusal, never before it. The first draft ran it unconditionally after the fetch, which round 1 found would force-remove a fresh, zero-commit `wrap start` worktree (trivially an ancestor of `origin/<def>`), destroying a live agent's uncommitted work and reversing a documented refusal. Superseded: the old DEC-2 ("the proof check runs unconditionally... before the ahead refusal") and its AC2/T2 are dropped.
- DEC-3: `tip` and `url` move above the branch point so the tail's existing reads of them stay valid under `set -u` regardless of which path reaches it.
- DEC-4: the proof-guard block re-checks dirty state, tip, and lock liveness after the gh round trip, mirroring `_apply_worktrees`'s own re-check pattern, rather than trusting a snapshot taken before a network call.
- DEC-5: an origin-freshness check (`ls-remote` vs the proven tip) runs before any "already landed" claim, mirroring `_autoland_carry`'s own freshness check, because a local proof says nothing about origin's current state of the branch.
- DEC-6: a coexisting open PR for a proven-landed branch is reported and refused, never silently resolved one way or the other -- closing it could contradict `wrap merge`'s own documented `<branch>-squash` fallback behavior, which deliberately leaves that PR open for a human.
- DEC-7: the shared tidy tail is a named helper, `_land_tidy`, rather than duplicated code or one large conditional, because it is now called from two places with identical behavior.
- DEC-8: a re-pushed-with-new-commits branch is deliberately left on today's unchanged path (no proof found), because `_merge_proof`'s existing tip comparison already resolves it correctly with no new special-case logic.

## Grounding

- The bug: in a consumer repo adopted into this operate-contract, PR A squash-merged on a feature branch, then `bin/wrap land` on the same worktree opened and merged PR B with an identical diff -- reported directly in this task's brief, not independently re-observed (no access to that repo's PR history from this worktree).
- `_merge_proof`'s three checks and their call sites: read directly, `lib/wrap/wrap.sh:441-461` (definition, ancestor route at `:449-451`), `:581-583` (`_apply_worktrees`'s use before a worktree/branch removal, its dirty/tip re-check at `:587-593`, its lock-live guard at `:596`), `:1325-1349` (`_autoland_carry`'s squash-only proof at `:1346-1349` plus its origin-freshness `ls-remote` check at `:1342-1344`).
- The exact decision point: `lib/wrap/wrap.sh:2479-2537`, read in full; the `else` arm creating a new PR sits at `:2521-2537`, reached whenever `open_count` is 0 (`:2489-2493`). The tail this spec extracts into `_land_tidy` reads `lib/wrap/wrap.sh:2610-2662`, including the exit-code convention at `:2661`.
- The `ahead`/ancestor mutual-exclusion fact (`## Root cause`): derived directly from `git rev-list --count origin/<def>..<branch>`'s definition (commits reachable from `<branch>` and not from `origin/<def>`) versus `merge-base --is-ancestor` (`<branch>` wholly reachable from `origin/<def>`) -- the two are logically exclusive by definition, not sampled from a live run.
- The documented refusal list, including "no commits ahead of the default branch": `docs/verification/wrap-land.md:3`.
- `wrap merge`'s `<branch>-squash` fallback and its "stays open for a manual close" behavior: `commands/wrap.md:116`, read directly.
- `feat/wrap-pull-only` overlap check: `git diff origin/master...HEAD -- lib/wrap/wrap.sh commands/wrap.md tests/test-wrap.sh` in that worktree. `lib/wrap/wrap.sh` hunks confirmed at the top-of-file verb list and near `cmd_scan`/`_apply_repo`/`cmd_apply` (old lines ~3-9, ~117-118, ~387-388, ~1545-1660); no hunk near `cmd_land` (`:2400+`) or `_merge_proof`/`_land_ff_pull`'s definitions. `commands/wrap.md` carries one hunk around its old line ~130-136 (the `pull_past_dirty`/stray-lines knobs paragraph); not independently verified against this spec's own `commands/wrap.md:118` land-bullet edit surviving a rebase without a line shift. `tests/test-wrap.sh` carries one hunk appended after its old line ~5531 (pinned-config tests), separate from this spec's own new cases appended near lines 2867/3434, but again not verified line-for-line stable across a rebase.
- Cannot be sampled live: there is no reachable copy of that consumer repo's PRs A/B from this worktree to re-verify the incident's gh state directly; the incident description in the task brief is taken as given, and the fix is grounded instead in this repo's own `_merge_proof`/`_apply_worktrees`/`_autoland_carry` mechanisms and their existing callers.

## Open questions

(none; the round-1 review decided every open design point -- the ordering relative to `ahead == 0`, the tip/url move, the reused guards, the origin-freshness check, the coexisting-PR report-and-refuse, and the `_land_tidy` shape -- and this revision applies each one without reopening it. The one place this spec makes its own judgment call rather than following an explicit instruction is the worktree's fate in the coexisting-open-PR case (Decision 5), named as such at the point it is made)
