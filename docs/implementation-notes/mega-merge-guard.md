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

## 2026-07-02 review: glob-injection in the label loop (BLOCKER, fixed)

First cut iterated labels with `for l in ${labels//,/ }` (unquoted), which word-splits AND
pathname-expands. A GitHub label is attacker-influenced (anyone who can label a PR), so a
label of `*` run from a CWD with matching files expanded into filenames, making hold
detection depend on `$PWD` , non-deterministic in a security backstop. Fixed to
`IFS=',' read -ra larr <<< "$labels"` + quoted `"${larr[@]}"` + whitespace/case normalization
(`tr -d '[:space:]'`), so an attacker label is a literal string and a whitespaced/odd-case
hold label still matches. Pinned (AC6b glob-literal, AC6c whitespace/case, AC8 held+--execute
never calls gh).

## 2026-07-02 security review: 2 BLOCKERs

- B2 fail-open on malformed state (FIXED): `_pr_info` only guarded empty/nonzero, so a
  non-empty non-conforming line (a gh-wrapper banner) parsed to a garbage `draft` and fell
  through to CLEAR , the opposite of the fail-closed promise. Fixed: validate exactly two
  \037 separators AND `draft in {true,false}`, else `return 2`. Pinned (AC5b).
- B1 blind to an UN-marked held PR (ACKNOWLEDGED + narrowed, not "fixed in code"): the guard
  keys off PR state, so it only defends a MARKED held PR; nothing in-repo auto-applies the
  mark. Honest resolution: narrowed the SPEC claim to "marked held PR" (which IS the
  label/state cross-check ID-083 asked for), recommend opening held PRs as DRAFTS (GitHub
  natively blocks draft merges = an intrinsic second layer), and filed ID-089 to enforce
  always-mark-at-creation in commands/mega.md (out of SG-05 scope). A comma-in-a-label can
  only over-block (fail-safe), never under-block.
