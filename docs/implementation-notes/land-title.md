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
