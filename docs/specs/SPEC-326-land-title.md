# SPEC-326: wrap land titles the PR from the feature commit

**Status:** DRAFT
Lane: full
Type: spec-fix
**Proof:** `tests/test-wrap.sh`, the land title-selection block.

## Problem

`bin/wrap land <worktree>` (`lib/wrap/wrap.sh` `cmd_land`) opens a fresh PR with no `--title`
flag by falling back to the branch's LAST commit's subject:

```
[ -n "$title" ] || title="$(git -C "$wt" log -1 --format=%s 2>/dev/null)"
```

A full-lane branch never ends on its feature commit. It ends on a doc/chore/test follow-up
(proof, changelog, spec-status flip, `docs/FEATURES.md` regeneration), so `land` titles the PR,
and therefore the squash-merge commit that lands on the default branch, after that follow-up
instead of the change itself:

- dwarves-kit #771 landed as `fix(spec-validate): drop the stale advisory count, disclaim
  reviewer 3` when the branch's last commit was actually a docs follow-up, burying the real
  fix's subject.
- ops-toolkit #3478 landed as `docs(lab-log): ...`, a housekeeping commit, not the feature the
  branch shipped.

SPEC-323 already fixed the same failure shape one level up, in `commands/wrap.md` step 10's
`--fill`/`--fill-first` follow-through PRs. `cmd_land` is a second, independent call site with
the identical bug: it reads `git log -1` (the tip), not the branch's feature commit.

## Contract

- When the caller passes no `--title`, `cmd_land` picks the title from the first commit ahead
  of `origin/<def>` (oldest first) whose subject is **not** a `docs`, `chore`, or `test`
  conventional-commit type (`docs:`/`docs(scope):`, `chore:`/`chore(scope):`,
  `test:`/`test(scope):`). If every commit ahead is one of those three types, it falls back to
  the first commit ahead (oldest), unchanged from today for a single-commit branch.
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
 cmd_land(wt)                          commits ahead of origin/<def>, oldest first:
      |                                  c1: docs(spec): reserve SPEC-326        <- skip (docs)
      v                                  c2: fix(wrap): title from feature commit <- PICK
  --title given? --yes--> use it              c3: docs(wrap): proof + changelog  <- (unreached)
      |
      no
      v
  walk commits ahead, oldest first
      |
      v
  first subject NOT docs:/chore:/test: ----found---> title = that subject
      |
    none found (every commit ahead
    is docs/chore/test, or --title
    was never reached this way)
      |
      v
  title = oldest commit ahead (today's git-log-1 fallback, applied to the OLDEST
          commit instead of the tip)
      |
      v
  open_count == 1 (adopted PR)? --yes--> title computed above is discarded;
      |                                   the adopted PR keeps its own title
      no
      v
  gh pr create --title "<picked title>" ...
```

## Design

obvious for the walk itself (a single ordered scan, first non-housekeeping subject wins,
oldest-first because the feature commit in a full-lane branch is near the start, not the end);
the type list and the "no housekeeping-only fallback" behavior are the parts worth a table.

| Approach | Why not / why |
|---|---|
| Newest-first scan, skip docs/chore/test, first match wins | Rejected: on a branch shaped `spec -> feature -> proof -> changelog -> spec-status -> features`, a newest-first walk still finds the feature commit correctly here, but a branch with a SECOND real change committed later (e.g. a fixup commit that is itself `fix(...)`) would pick the fixup's subject over the original feature's, the same "title from the wrong commit" bug in a new shape. Oldest-first matches the full-lane shape SPEC-323 already documented (spec commit first, feature commit next) and picks the FIRST substantive change, which is the one worth naming the PR after. |
| Reuse `commands/wrap.md`'s literal `--fill-first` gh flag inside `cmd_land` | Not available: `--fill-first` and `--fill` both derive the title from gh's own PR/commit-range summary at `gh pr create` time and only apply when the command is also filling the body; `cmd_land` computes its title in `wrap.sh` itself (bash, not gh) so it can compare it against an adopted PR's existing title and log it before the `gh pr create` call runs. Re-shelling to gh for this one field would need a same-repo, same-branch round trip gh already makes when it opens the PR, for no gain. |
| Regex on the type prefix only (`^[a-z]+(\(.*\))?:`), classifying anything unmatched as "feature" too | This is exactly the chosen shape: a non-conventional subject (no recognized type prefix at all) is never mistaken for housekeeping, so it counts as the feature commit. Listed here because it is the reason the match is an explicit `docs|chore|test` allow-list for SKIP, not a `feat|fix|refactor` allow-list for PICK -- an unlisted type (e.g. `perf:`, `ci:`) must default to "counts as the feature," not silently fall through to the last-commit bug this spec removes. |
| Fall back to the branch's LAST commit (today's behavior) when every commit ahead is housekeeping | Rejected: that is precisely the bug. The spec's contract instead falls back to the FIRST commit ahead in that case -- still not perfect (an all-housekeeping branch has no real "feature commit" to name), but the first commit is closer to "what this branch is about" than the last, and matches SPEC-323's own BUILD/FINISH precedent (`--fill-first` takes the first commit). |

## Failure modes

| Class | Detection | Mitigation |
|---|---|---|
| Every commit ahead is docs/chore/test (an all-housekeeping branch, or a lane whose "feature" step itself commits as `docs(...)`) | the oldest-first walk finds no non-housekeeping subject | fall back to the oldest commit ahead, never the newest; never an empty title |
| `git log --format=%s --reverse origin/<def>..HEAD` returns nothing (a git failure, an unreadable ref) | empty output from both the walk and the fallback `head -1` | `title` stays empty exactly as `git log -1` failing does today; `gh pr create --title ""` is gh's problem to reject, unchanged from the pre-existing behavior on a git failure |
| An adopted PR's title is silently overwritten | contract requires the adopted-PR branch to never read the computed title | the existing `if [ "$open_count" -eq 1 ]` branch already ignores `$title` and only logs a note when flags were given; this spec adds no read of the new default inside that branch |
| A branch whose ONLY commit is `docs(...)`/`chore(...)`/`test(...)` (a legitimate docs-only or chore-only land) gets a title an author would call odd | the walk finds no non-housekeeping match, falls back to that same lone commit | unchanged from today (a single-commit branch always used `git log -1`, which is this exact commit); not a regression, out of scope |

## Task Breakdown

| Task | Files | Acceptance |
|---|---|---|
| T1: oldest-first, skip-housekeeping title pick | `lib/wrap/wrap.sh` (`cmd_land`) | the `--title` fallback walks commits ahead of `origin/<def>` oldest-first, skips a `docs`/`chore`/`test` conventional subject, picks the first remaining one, and falls back to the oldest commit ahead when none remain; an adopted PR's title is never read from this computation |
| T2: tests | `tests/test-wrap.sh` | new cases per `## Test plan` below, added beside the existing `land` fixtures (`build_land`) |
| T3: docs | `commands/wrap.md` (the land bullet, if it names the old `git log -1` behavior), `docs/CHANGELOG.md` `[Unreleased]`, `docs/FEATURES.md` (regenerated last via `lib/registry/feature-registry.sh generate`) | the land bullet, if any, matches the new default; changelog carries one line; FEATURES.md regenerated after everything else |
| T4: proof | `docs/verification/land-title.md`, `docs/implementation-notes/land-title.md` | green `tests/test-wrap.sh`, the negative control (reverting the pick to `git log -1` on the tip must go red), `tests/run-all.sh --changed` exit 0, delta-only implementation notes |

## Test plan

| Case | Setup | Expected |
|---|---|---|
| Multi-commit branch, feature commit not last | a branch with `docs(spec): reserve` then `fix(x): the real change` then `docs(x): proof` ahead of `origin/main` | `land`'s `gh pr create` call carries `--title "fix(x): the real change"`, not the last commit's subject |
| Multi-commit branch, feature commit first | a branch with `fix(x): the real change` then `docs(x): proof and changelog` ahead of `origin/main` | title is `fix(x): the real change` (first commit, also the only non-housekeeping one) |
| All-housekeeping branch | a branch with only `docs(x): a` then `chore(x): b` ahead of `origin/main` | title falls back to the OLDEST commit ahead (`docs(x): a`), never the newest |
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
the branch's feature commit's subject, not whichever commit happens to be last. A single-commit
branch, an explicit `--title`, and an adopted PR are all unaffected -- this only changes the
computed default on a multi-commit branch that lands with no `--title` given.

Not covered: a branch whose feature step itself commits under a non-`feat`/`fix`/`refactor`
type this spec did not anticipate (only `docs`/`chore`/`test` are treated as housekeeping);
such a branch keeps today's already-correct behavior on a single commit and gets the new
oldest-first pick on multiple commits, which is a strict improvement, not a regression, but is
not separately covered by a dedicated test case.

## Decision Log

- Oldest-first walk (not newest-first) to match the full-lane branch shape SPEC-323 already
  established (spec commit, then feature commit, then trailing docs) and to avoid picking a
  later fixup commit's subject over the original feature's.
- `docs`/`chore`/`test` as an explicit SKIP allow-list, not a `feat`/`fix`/`refactor` PICK
  allow-list, so an unrecognized or non-conventional subject defaults to "counts as the
  feature" rather than silently falling through to the removed last-commit bug.
- Fallback on an all-housekeeping branch is the OLDEST commit ahead, not the branch tip,
  consistent with the rest of this spec's oldest-first framing and with SPEC-323's
  `--fill-first` precedent (first commit, not last).
- Left `commands/wrap.md`'s land bullet and `docs/FEATURES.md` regeneration to Phase 2's T3,
  since neither is settled until the exact wording of the implemented walk is known.
