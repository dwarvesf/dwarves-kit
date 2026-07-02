# Implementation notes: mega-merge code-level exclusion (SPEC-100)

Delta from SPEC-100.

## 2026-07-02 Unit-Separator delimiter (a real bug caught in smoke test)

First cut joined `_pr_info` fields with a tab and read them with `IFS=$'\t'`. A PR with NO
labels (empty middle field) silently mis-parsed: `read` collapses runs of WHITESPACE IFS
chars (tab is whitespace), so `false<TAB><TAB>[HOLD]...` assigned the title to `labels` and
left `title` empty -> the title-marker check never fired (a held PR slipped through as
"clear"). Switched the delimiter to the ASCII Unit Separator (\037), which is non-whitespace,
so `read` preserves empty fields. (DEC-004.) The smoke test caught it: PR#4 was dry-running
to merge instead of being blocked.

## 2026-07-02 the exclusion broke a sibling test (fail-closed on fake PRs)

`test-mega-reconcile.sh` merges FAKE PR numbers (999, 888) with a fake `gh` that returns
empty for everything. My exclusion calls `gh pr view` first; empty -> unclassifiable ->
fail-closed -> BLOCKED, so 11 of its assertions flipped. Fix: inject a CLEAR PR-state stub
(`MEGA_MERGE_PR_INFO_CMD`) in that test so its merge cases keep testing the gate/posture path;
the exclusion itself is covered by the new `test-mega-merge.sh`. This is the right seam , the
same injection point the exclusion exposes for testability , not a workaround.

## 2026-07-02 how the held final PR is marked

For THIS mega-goal's gated-final flow, the held final PR (SG-05's own PR) is labelled
`do-not-merge` when opened, so the code guard refuses to auto-merge it , the guard protects
even its own sub-goal's PR. Han does the final merge.

## 2026-07-02 dogfood

SG-05 classified `full` at intake because SG-03 added `mega-merge` to the kit-machinery
hard-gate. Third wave sub-goal whose own lane was corrected by an earlier sub-goal of the
same wave.
