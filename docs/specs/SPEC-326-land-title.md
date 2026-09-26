# SPEC-326: wrap land titles the PR from the feature commit

**Status:** VALIDATED
Lane: full
Type: spec-fix
**Proof:** `tests/test-wrap.sh`, the land title-selection block.

## Problem

`bin/wrap land <worktree>` (`lib/wrap/wrap.sh` `cmd_land`) opens a fresh PR with no `--title`
flag by falling back to the branch's LAST commit's subject:

```
[ -n "$title" ] || title="$(git -C "$wt" log -1 --format=%s 2>/dev/null)"
```

That title matters past the PR itself: GitHub's `squash_merge_commit_title` repo setting
defaults to `COMMIT_OR_PR_TITLE`, which uses the PR's own title **only when the PR carries more
than one commit**; a single-commit PR squashes under that commit's own subject regardless of
the PR title, so a single-commit branch's behavior is unaffected by anything in this spec (it
was already reading that one commit's subject via `git log -1`, and the squash was already
titling from the commit, not the PR, either way). `_gh_merge_retry`'s
`gh pr merge --squash --match-head-commit` call passes no `--subject` of its own, so on a
MULTI-commit branch, whatever title `land` picks for the PR becomes the commit message that
lands on the default branch, not just a label on the PR page.

A full-lane branch rarely ends on its feature commit -- the last commit is typically a
docs/chore follow-up (proof, changelog, spec-status flip, `docs/FEATURES.md` regeneration), or,
independently, a later fixup commit of the same type as the original change:

- dwarves-kit #771's branch committed `feat(...)` first, then a `docs(...)` step, then a
  `fix(...)` review follow-up as its tip. `git log -1` read the tip and landed the PR (and the
  squash-merge commit on master) as `fix(spec-validate): drop the stale advisory count,
  disclaim reviewer 3`, the review follow-up's own subject, not the branch's actual first
  change. Note this is not a docs/chore/test housekeeping case -- the tip commit's type was
  itself `fix`, so a filter that only skips housekeeping types would not have caught it; what
  was wrong was reading the LAST commit instead of the FIRST.
- ops-toolkit #3478 landed as `docs(lab-log): ...`, a housekeeping commit, not the feature the
  branch shipped -- this one IS a housekeeping-tip case.

SPEC-323 already fixed the same failure shape one level up, in `commands/wrap.md` step 10's
`--fill`/`--fill-first` follow-through PRs. `cmd_land` is a second, independent call site with
the identical bug: it reads `git log -1` (the tip), not the branch's feature commit.

## Contract

- When the caller passes no `--title`, `cmd_land` picks the title from the first non-merge
  commit ahead of `origin/<def>` (oldest first) whose subject does not match
  `^(docs|chore|test)(\([^)]*\))?!?:` (matches `docs:`, `docs(scope):`, `docs!:`,
  `docs(scope)!:`, and the same for `chore`/`test`; the trailing `!` covers a
  breaking-change marker on the type itself). If every non-merge commit ahead is one of those
  three types, it falls back to the first non-merge commit ahead (oldest), unchanged from
  today for a single-commit branch.
- **Merge commits are excluded from the walk entirely**, both the main scan and the
  all-housekeeping fallback (`git log --no-merges`). A branch that merged `origin/<def>` back
  into itself mid-development carries a `Merge ...` commit that matches neither the housekeeping
  regex nor anything else meaningful, and would otherwise be picked as "the feature" purely for
  not being docs/chore/test. The walk also carries `--topo-order`, so a side commit merged in
  with an older author/commit date than the branch's own first commit still sorts after it
  (date-order alone could otherwise surface that older commit as "oldest").
- **The walk never combines `--reverse` with `-1`/`-n1`.** Git applies a `-1`/`-n1` count limit
  BEFORE reversing the output order, so `git log --reverse -1` silently returns the newest
  commit, not the oldest -- the opposite of what "oldest first, one result" looks like it should
  do. The implementation instead runs the full `git log --no-merges --topo-order --format=%s
  --reverse origin/<def>..HEAD` list unbounded and takes the first line in the shell (`| head
  -1`) for the fallback; the main skip-housekeeping scan already reads the full list line by
  line and stops at its first match, so it never needed a git-side limit to begin with.
- `fixup!`/`squash!` prefixed subjects are **not** specially handled by this contract: they do
  not match the housekeeping regex, so they count as an ordinary (non-skipped) subject exactly
  like any other non-housekeeping commit. This is deliberate, not an oversight: a branch that
  reaches `land` normally has any `fixup!`/`squash!` commits already folded by
  `rebase --autosquash` before landing (git's own convention), so a real `fixup!`/`squash!`
  subject surviving to this walk is an already-unusual branch state this spec does not attempt
  to special-case.
- This only changes the DEFAULT. An explicit `--title` still wins outright, exactly as today.
- An **adopted** PR (one already open on the branch) still keeps its own title and body
  unconditionally -- `cmd_land` never renames or re-bodies a PR a human or an earlier step
  already opened. The default-title computation still runs (it is cheap and side-effect-free),
  but its result is only ever read on the "open a new PR" branch of the existing `if
  [ "$open_count" -eq 1 ]; ... else ... gh pr create ...` split.
- A single-commit branch (the common case, and every existing `land` test fixture) is
  unaffected: the sole commit ahead is picked whether or not it happens to be a docs/chore/test
  type, exactly as `git log -1` already did.

## Picture

```
 cmd_land(wt)                          non-merge commits ahead of origin/<def>, oldest first:
      |                                  c1: docs(spec): reserve SPEC-326        <- skip (docs)
      v                                  c2: fix(wrap): title from feature commit <- PICK
  --title given? --yes--> use it        c3: docs(wrap): proof + changelog
      |
      no
      v
  walk --no-merges --topo-order --reverse commits ahead, oldest first
      |
      v
  first subject NOT ^(docs|chore|test)(\(...\))?!?: --found--> title = that subject
      |
    none found (every non-merge
    commit ahead is docs/chore/test)
      |
      v
  title = full list | head -1  (oldest non-merge commit ahead; never
          git log --reverse -1, which limits BEFORE reversing and
          would silently return the NEWEST commit instead)
      |
      v
  open_count == 1 (adopted PR)? --yes--> title computed above is discarded;
      |                                   the adopted PR keeps its own title
      no
      v
  gh pr create --title "<picked title>" ...
      |
      v
  gh pr merge --squash --match-head-commit ...   (no --subject: GitHub's
      |                                            squash_merge_commit_title
      v                                            default takes the PR title)
  squash-merge commit on <def> carries "<picked title>"
```

## Design

obvious for the walk itself (a single ordered scan, first non-housekeeping subject wins,
oldest-first because the feature commit in a full-lane branch is near the start, not the end);
the type list, the merge-commit exclusion, and the "no housekeeping-only fallback" behavior are
the parts worth a table.

| Approach | Why not / why |
|---|---|
| Newest-first scan, skip docs/chore/test, first match wins | Rejected: dwarves-kit #771 is exactly this failure in a new shape -- the branch's tip was itself a `fix(...)` commit (a review follow-up), which no docs/chore/test filter would skip, so a newest-first scan would still pick the review follow-up's subject over the original `feat(...)` commit's. Oldest-first matches the full-lane shape SPEC-323 already documented (spec commit first, feature commit next) and picks the FIRST substantive change, which is the one worth naming the PR after, whether the tip is housekeeping or a later same-type commit. |
| Reuse `commands/wrap.md`'s literal `--fill-first` gh flag inside `cmd_land` | Not viable as-is: SPEC-323 found that on a full-lane branch the FIRST commit is the spec (typically `docs(spec): ...`), not the feature -- exactly why that spec gave the full-lane draft command an explicit `--title` instead of `--fill-first`. `cmd_land` lands the same full-lane branches, so a bare `--fill-first` would take the spec commit's subject, not the feature's; `cmd_land` needs its own housekeeping-skipping walk, not gh's plain "first commit" rule. |
| A `feat`/`fix`/`refactor` PICK allow-list (skip anything that is not one of those three named types) | Rejected: an unlisted-but-real type (`perf:`, `ci:`, `build:`, or any type this repo's history has not used yet) would fail the PICK test and fall through exactly like a housekeeping commit, right back into the removed last-commit bug for any branch whose feature step used a type this list forgot. The chosen shape inverts it: `docs`/`chore`/`test` is a SKIP allow-list, so a non-conventional or unlisted-type subject defaults to "counts as the feature" and is never silently treated as housekeeping. |
| Fall back to the branch's LAST commit (today's behavior) when every commit ahead is housekeeping | Rejected: that is precisely the bug. The spec's contract instead falls back to the FIRST non-merge commit ahead in that case -- still not perfect (an all-housekeeping branch has no real "feature commit" to name), but the first commit is closer to "what this branch is about" than the last, and matches SPEC-323's own BUILD/FINISH precedent (`--fill-first` takes the first commit). |
| Include merge commits in the walk (no `--no-merges`) | Rejected: a `Merge branch 'main' into feat/x` subject matches no housekeeping type, so an unfiltered walk would pick it as "the feature" on a branch that happened to merge the default branch back into itself, which is worse than the bug this spec removes. `--no-merges` on both the main scan and the fallback removes this class outright. |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| A branch merged `origin/<def>` back into itself mid-development, leaving a `Merge ...` commit ahead of `origin/<def>` | that merge commit's subject matches neither the housekeeping regex nor anything meaningful, so an unfiltered walk would pick it | `git log --no-merges` on both the main scan and the all-housekeeping fallback excludes every merge commit from consideration entirely |
| Every non-merge commit ahead is docs/chore/test (an all-housekeeping branch, or a lane whose "feature" step itself commits as `docs(...)`) | the oldest-first walk finds no non-housekeeping subject | fall back to the oldest non-merge commit ahead, never the newest; never an empty title |
| `git log --no-merges --format=%s --reverse origin/<def>..HEAD` returns nothing (a git failure, an unreadable ref, or every commit ahead is itself a merge commit) | empty output from both the walk and the fallback `head -1` | `title` stays empty exactly as `git log -1` failing does today; `gh pr create --title ""` is gh's problem to reject, unchanged from the pre-existing behavior on a git failure |
| An adopted PR's title is silently overwritten | contract requires the adopted-PR branch to never read the computed title | the existing `if [ "$open_count" -eq 1 ]` branch already ignores `$title` and only logs a note when flags were given; this spec adds no read of the new default inside that branch |
| A branch whose ONLY commit is `docs(...)`/`chore(...)`/`test(...)` (a legitimate docs-only or chore-only land) gets a title an author would call odd | the walk finds no non-housekeeping match, falls back to that same lone commit | unchanged from today (a single-commit branch always used `git log -1`, which is this exact commit); not a regression, out of scope |
| A STACKED branch cut from a parent that already squash-merged still carries the parent's pre-squash commits ahead of `origin/<def>` | `origin/<def>..HEAD` is not ancestry-aware of a squash: the parent's original commits are not reachable from the new squash commit on `<def>`, so they still show up in the range, oldest first, exactly as if they were this branch's own | not fixed by this spec (see After state's "Not covered"); `--cherry-pick` does not help either, since a cherry-picked commit keeps the same subject under a new SHA and still shows up in the range |
| `cmd_land` never checks whether its own `git -C "$wt" fetch -q origin "$def"` (a few lines above the title pick) succeeded | the fetch's exit code is discarded (`2>/dev/null`, no `\|\|` check) | pre-existing, unrelated to this spec's change; noted here, not fixed -- a failed fetch means the walk runs against a stale `origin/<def>`, which is the same staleness every other `origin/<def>`-relative read in `cmd_land` (the `ahead` count, the tree-verify) already tolerates |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: oldest-first, skip-housekeeping, no-merges title pick | `lib/wrap/wrap.sh` (`cmd_land`) | the `--title` fallback runs `git log --no-merges --topo-order --format=%s --reverse origin/<def>..HEAD` (no `-1`/`-n1` combined with `--reverse`), skips a subject matching `^(docs\|chore\|test)(\([^)]*\))?!?:`, picks the first remaining one, and pipes the same unbounded list to `head -1` for the fallback when none remain; an adopted PR's title is never read from this computation |
| T2: tests | `tests/test-wrap.sh` | `build_land` gains multi-commit support (a mode or argument that seeds more than the fixture's one commit ahead of `origin/main`); new cases per `## Test plan` below, added beside the existing `land` fixtures |
| T3: docs | `commands/wrap.md` (the land bullet at the "A branch committed in a HAND-MADE worktree..." paragraph, ~line 104), `docs/CHANGELOG.md` `[Unreleased]`, `docs/FEATURES.md` (regenerated last via `lib/registry/feature-registry.sh generate`) | the land bullet gains one clause naming the default: with no `--title`, `land` titles a fresh PR from the branch's first non-merge, non-docs/chore/test commit ahead of the default branch, falling back to the first non-merge commit ahead when every one is housekeeping; changelog carries one line; FEATURES.md regenerated after everything else |
| T4: proof | `docs/verification/land-title.md`, `docs/implementation-notes/land-title.md` | green `tests/test-wrap.sh`, the negative control (reverting the pick to `git log -1` on the tip must go red), `tests/run-all.sh --changed` exit 0, delta-only implementation notes |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Multi-commit branch, feature commit not last | a branch with `docs(spec): reserve` then `fix(x): the real change` then `docs(x): proof` ahead of `origin/main` | `land`'s `gh pr create` call carries `--title "fix(x): the real change"`, not the last commit's subject |
| Multi-commit branch, feature commit first | a branch with `fix(x): the real change` then `docs(x): proof and changelog` ahead of `origin/main` | title is `fix(x): the real change` (first commit, also the only non-housekeeping one) |
| All-housekeeping branch | a branch with only `docs(x): a` then `chore(x): b` ahead of `origin/main` | title falls back to the OLDEST commit ahead (`docs(x): a`), never the newest |
| Branch that merged `origin/main` mid-branch | `feat(x): real change` committed first; THEN a commit is pushed to advance the bare remote's `main` (so the branch is genuinely behind before merging); then `git merge origin/main` on the branch, a real two-parent merge, not a fast-forward. Precondition asserted before calling `land`: `git rev-list --merges --count origin/main..HEAD` equals `1` | title is `feat(x): real change`; the merge commit's subject is never picked and never counted toward "every commit ahead is housekeeping"; the assertion is on the actual `gh pr create ... --title "feat(x): real change"` call captured by the `gh` stub, not merely on `land`'s printed output |
| Single-commit branch (every existing `land` fixture) | `build_land`'s one `feat: the landed change` commit | title unchanged: `feat: the landed change`, matching every pre-existing `land` test's expectation |
| Explicit `--title` still wins | `land <wt> --title "custom title"` on a multi-commit branch whose feature commit differs | `gh pr create` carries `--title "custom title"`, the walk never runs (or its result is discarded) |
| Adopted PR keeps its own title | an already-open PR on the branch, `land` called with no flags on a multi-commit branch | the computed default title is never sent anywhere (no `gh pr create` call at all on the adopt path); the existing "adopted PR #N" report line is unchanged |
| Non-conventional subject counts as feature | a branch with `docs(x): a` then a subject with no recognized type prefix at all (e.g. `wip stuff`) ahead of `origin/main` | title is the non-conventional subject, not the docs one and not a fallback to oldest |

Negative control: `lib/gate/negctl.sh` mutates the picked-title logic back to `git -C "$wt" log
-1 --format=%s` (today's tip-only read). The multi-commit "feature commit not last" case above
must go red.

## Verification

`bash tests/test-wrap.sh` exits 0. `bash tests/run-all.sh --changed` exits 0.

## After state

`bin/wrap land <worktree>` with no `--title` flag opens (and then squash-merges) the PR under
the branch's feature commit's subject, not whichever commit happens to be last, and never under
a merge commit's subject. A single-commit branch, an explicit `--title`, and an adopted PR are
all unaffected -- this only changes the computed default on a multi-commit branch that lands
with no `--title` given.

Not covered: a branch whose feature step itself commits under a non-`feat`/`fix`/`refactor`
type this spec did not anticipate (only `docs`/`chore`/`test` are treated as housekeeping);
such a branch keeps today's already-correct behavior on a single commit and gets the new
oldest-first pick on multiple commits, which is a strict improvement, not a regression, but is
not separately covered by a dedicated test case. Also not covered: a `fixup!`/`squash!`
subject surviving to `land` unsquashed -- it is treated as an ordinary non-housekeeping subject,
per the Contract's explicit note.

Not covered: a STACKED branch cut from a parent branch that already squash-merged still carries
the parent's original (pre-squash) commits ahead of `origin/<def>`, so the walk picks the
parent's oldest non-housekeeping subject, not this child branch's own. `--cherry-pick`-ing the
parent's commits onto a fresh branch does not avoid this either -- the cherried commits keep
their original subjects under new SHAs and still show up in the range. The operator's fix is
external to this walk: rebase the child onto the post-squash `<def>` before landing (so only the
child's own commits remain ahead), or simply pass an explicit `--title`.

## Decision Log

- Oldest-first walk (not newest-first) because dwarves-kit #771's own failure was a LATER
  same-type (`fix(...)`) commit outranking the original feature commit, which a
  housekeeping-only filter would never catch from the newest end; oldest-first also matches the
  full-lane branch shape SPEC-323 already established (spec commit, then feature commit, then
  trailing docs).
- `docs`/`chore`/`test` as an explicit SKIP allow-list, not a `feat`/`fix`/`refactor` PICK
  allow-list, so an unrecognized or non-conventional subject defaults to "counts as the
  feature" rather than silently falling through to the removed last-commit bug.
- `--no-merges` on both the main walk and the all-housekeeping fallback, found while checking
  the walk against a scratch repro of ops-toolkit #3478: a branch that merges the default branch
  back into itself leaves a merge commit that matches no housekeeping type and would otherwise
  be picked as "the feature" purely by elimination.
- `fixup!`/`squash!` subjects are explicitly left unhandled (counted as ordinary, non-skipped
  subjects) rather than added to the skip list, since git's own `rebase --autosquash` convention
  means a real branch reaching `land` should never carry one unsquashed.
- Fallback on an all-housekeeping branch is the OLDEST non-merge commit ahead, not the branch
  tip, consistent with the rest of this spec's oldest-first framing and with SPEC-323's
  `--fill-first` precedent (first commit, not last).
- `commands/wrap.md`'s land bullet gains one clause naming this default (T3); the exact wording
  is written once the implemented walk's shell is final, but the clause itself is not optional.
- `--topo-order` added to the walk: date-order alone can surface an older-dated side commit
  merged in from another branch ahead of the feature branch's own earlier commit; topo-order
  keeps parent-before-child ancestry, which date-order does not guarantee.
- The fallback pipes the full `--reverse` list to `head -1` in the shell rather than asking git
  for one result directly, because `git log --reverse -1` (or `-n1`) applies the count limit
  BEFORE reversing and would silently return the newest commit, the exact opposite of "oldest."
- A stacked branch cut from an already-squash-merged parent is explicitly out of scope (see
  After state): the walk has no way to distinguish "this branch's own commits" from "a parent's
  commits that happen to still show up in the range" without more context than a subject-only
  scan carries; rebase-or-`--title` is left to the operator.
- `cmd_land`'s pre-existing silent fetch failure (`git fetch ... 2>/dev/null` with no exit-code
  check) is noted in Failure modes but deliberately not fixed here -- it is a repo-wide,
  pre-existing pattern in this function, not something this spec's title-pick change introduces
  or worsens.
