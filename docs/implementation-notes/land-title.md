# Impl notes: land-title (SPEC-326)

Delta from the spec. Only off-spec calls live here.

## Re-validation folded two rounds of findings before build

The spec went through two validator rounds. Round 1 (NEEDS REVISION, 1 critical: an
unfiltered walk would pick a `Merge ...` commit's subject) added `--no-merges` to both the
walk and the all-housekeeping fallback, corrected the dwarves-kit #771 citation (the branch's
tip was itself a `fix(...)` review follow-up, not a docs commit, so the bug is oldest-vs-newest,
not a housekeeping-filter gap), and fixed the `--fill-first` rejection rationale to cite
SPEC-323's actual finding (a full-lane branch's first commit is the spec doc, not the feature).
Round 2 (APPROVED, 0 critical) added the stacked-branch scope note, tightened the merge-commit
test to a real two-parent merge with an asserted precondition, clarified
`squash_merge_commit_title` only wins on a multi-commit PR, and pinned the `--reverse`/`-1`
git ordering gotcha plus `--topo-order`. Both rounds are folded into the spec as committed;
nothing here duplicates them.

## No deviation from the Contract, Picture, or Test plan otherwise

`_land_feature_title()` (new helper, placed immediately before `cmd_land`) implements the
Contract exactly: `git log --no-merges --topo-order --format=%s --reverse origin/<def>..HEAD`,
first non-`docs`/`chore`/`test` subject wins, `head -1` on the same unbounded list for the
fallback. `cmd_land`'s single call site (`[ -n "$title" ] || title="$(_land_feature_title "$wt"
"$def")"`) replaces the old `git -C "$wt" log -1 --format=%s`; the adopted-PR branch already
ignored `$title` before this change and still does, unmodified.

## `build_land` test fixture gained multi-commit support without touching existing call sites

The fixture's signature is now `build_land <name> [--modify-base|--union-log] [branch]
[commit-subject...]`, extra positional args past `branch`. Every pre-existing call passes at
most three args, so the new `shift "$nshift"` (capped at 3) leaves zero trailing subjects for
them and they fall through to the unchanged single-commit `else` branch. Only the seven new
SPEC-326 cases pass subjects.

## The merge-commit test builds a real merge, not a fixture shortcut

Round 2 specifically asked for a genuinely non-trivial merge: the bare remote's `main` is
advanced by a separate clone-and-push BEFORE the branch merges it, so `git merge --no-edit
origin/main` on the worktree is a real two-parent merge, never a fast-forward the branch
already contained. The test asserts the precondition directly
(`git rev-list --merges --count origin/main..HEAD` = 1) before calling `land`, and asserts on
the actual `gh pr create ... --title` call the stub captured, not merely on `land`'s printed
report line.

## `open_pr_json` ordering

The new title-selection section runs before `tests/test-wrap.sh`'s `=== land: adopting an
operator-owned open PR ===` section, which is where the `open_pr_json` helper function is
defined. The new "adopted PR keeps its own title" case inlines the same JSON shape directly
rather than calling that not-yet-defined function, to avoid reordering unrelated sections of
the file for one call site.

## Post-build critique: FIX THEN SHIP on tests only (design SOLID, code correct)

A fresh critique+review pass found the design sound and the implementation correct, but the
test suite did not actually isolate three of the four flags on `_land_feature_title`'s `git
log` calls. Each gap and its fix:

- **`--reverse` untested (HIGH).** The original #771-shaped fixture (`title-mid`) had its
  original feature commit ALREADY as the sole non-housekeeping candidate with nothing after
  it of the same type, so dropping `--reverse` would have picked the same (only) match either
  way -- the ordering itself was never exercised. Added `title-771`, reproducing the real #771
  shape exactly: `docs(spec): r` -> `feat(x): the change` -> `fix(x): review follow-up`. Kill
  (`sed` dropping `--reverse` from the walk's `git log`, line 2141): RED, 1 failure
  (`title-771` picked the newest non-housekeeping match, the review follow-up, instead of the
  oldest). Restored: green.
- **`--no-merges` untested (HIGH).** The original `title-mrg` fixture's own commit
  (`feat(x): real change`) was ALREADY non-housekeeping, so the walk returned before ever
  reaching the merge commit -- `--no-merges` was never load-bearing in that shape. Two fixes:
  (a) changed `title-mrg`'s own commit to `docs(x): only` (housekeeping), forcing the walk to
  continue past it to the merge commit next. Kill (drop `--no-merges` from the WALK, line
  2141): RED, 2 failures in `title-mrg` (the merge subject won) AND 2 in `title-mrgfb` (the
  walk itself now caught the same front-of-range merge before ever reaching the fallback,
  confirming the walk-level bug's blast radius). Restored: green. (b) added `title-mrgfb`,
  a branch that owns NO commit at all when it merges (`git merge --no-ff origin/main`), only
  committing its own `docs(x): a` afterward, so the walk correctly finds nothing and the
  FALLBACK's own `--no-merges` is what gets exercised. Kill (drop `--no-merges` from the
  FALLBACK only, line 2142): RED, 2 failures, `title-mrgfb` alone (`title-mrg`'s walk still
  found nothing, its own `--no-merges` untouched by this mutation, so it stayed green).
  Restored: green.
- **`--topo-order` untested (MEDIUM).** Added `title-topo`: the branch's own
  `feat(x): the main change` at the real commit date, merged (`--no-ff`) with a local
  `side-topo` branch whose `feat(y): the backdated side change` carries an explicit
  `GIT_COMMITTER_DATE`/`GIT_AUTHOR_DATE` in 2020. Kill (drop `--topo-order` from the walk,
  line 2141): RED, 2 failures, `title-topo` alone (plain date-order picked the backdated side
  commit as "oldest" instead of the branch's own, topologically-earlier commit). Restored:
  green.
- **Argument-boundary check (LOW).** Rather than reformat the shared `gh` stub's primary call
  log (which every pre-existing assertion in the file greps as space-joined text -- reformatting
  it risked breaking hundreds of unrelated checks for one new assertion), added an ADDITIVE,
  opt-in second log (`GH_STUB_CALLS_QUOTED`, each argv entry bracketed: `<arg1><arg2>...`),
  written only when a case sets that env var. `title-mid` now also asserts
  `<--title><fix(x): the real change>` on that second log, proving the title landed as one
  argv entry rather than several word-split ones. Zero existing assertions touched.
- **`title-hk` housekeeping-type coverage (LOW).** Extended from 2 to 4 commits
  (`docs(x): a`, `chore(x): b`, `test(x): c`, `docs!: d`, the last covering the bare-bang
  breaking-change marker with no scope), asserting the fallback still lands on the oldest
  (`docs(x): a`) and never any of the three newer housekeeping subjects, `test` and bare-bang
  `docs!` included.
- **Accepted edge case added to the spec.** A branch that merges in a non-default (side)
  branch, where the branch's OWN commits are all housekeeping but the merged-in side branch
  carries a real non-housekeeping commit, takes the foreign side commit's subject. Documented
  as accepted in the Failure modes table: the walk excludes MERGE commits, not non-merge
  commits inherited via a merge, and has no provenance signal to tell "this branch's own
  history" from "a foreign branch's history that got merged in." Same family as the
  already-accepted stacked-branch limitation.

Every mutation above was applied to `lib/wrap/wrap.sh` alone, the SAME line each time
(`2141` for the walk's three flags, `2142` for the fallback's `--no-merges`), full suite run
under the mutation, confirmed RED with the exact assertion(s) failing named above, then
restored via `git checkout HEAD -- lib/wrap/wrap.sh` and confirmed the tree matched HEAD
exactly (`git diff --stat` empty) before the next mutation. The `--reverse` case additionally
ran through `lib/gate/negctl.sh` end to end (mutate/RED/restore/green in one gated call);
the other three were run by hand for per-assertion detail negctl itself discards.
