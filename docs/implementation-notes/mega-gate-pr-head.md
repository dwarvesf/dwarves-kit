# Implementation notes: mega-gate-pr-head

Delta from `docs/specs/SPEC-403-mega-gate-pr-head.md`. Round 1: NEEDS REVISION, 4 critical (one finding: an empty merge base skipped the floor in head mode), folded as DEC-3 to DEC-5. Round 2: APPROVED, 0 critical, 34 warnings. The warnings below are for the builder.

## Warnings for the builder

1. Base retarget: `--match-head-commit` pins only the head. Re-read `_pr_base` right before `gh pr merge` and refuse when it changed (Reviewers 1, 3).
2. Fetch hang: run the fetch with `GIT_TERMINAL_PROMPT=0` and a bounded wait (a background `git fetch` plus a watchdog kill, since macOS has no `timeout`); a timeout is a failed fetch (Reviewers 2, 3).
3. Argument parsing: `--base-tip` without `--head`, and `--head` or `--base-tip` with no value, are usage errors (exit 64), never a fallback to local `HEAD` (Reviewers 2, 3).
4. Spec lookup parity: the root match is the glob `docs/specs/SPEC-*-<rid>.md` (the `*` spans dashes); only co-located specs need `SPEC-<digits>-<rid>.md`. Match with a fixed-string `case` on the full path, never a regex built from `<rid>`. Prefer sharing the rule with `spec_for_slug` over a copy, and add a case with a hyphenated slug (Reviewers 1, 3, 5).
5. Override contract: `MEGA_MERGE_PR_FETCH_CMD` replaces the fetch and the head comparison. `merge` still checks that `H` is a commit and that the printed tip is 40 hex and a commit (Reviewers 1, 2, 3, 5).
6. Test legs to add: `_pr_base` read failure and a name `check-ref-format` rejects; the base branch missing on origin; AC8 as explicit `grep` checks on `SECURITY.md` line 14 and the CHANGELOG line; stub `MEGA_MERGE_PR_BASE_CMD` (or the fake `gh` answering `baseRefName`) in AC5 so no real `gh` runs (Reviewers 2, 4).
7. Private refs: delete `refs/kit/pr-<n>/head` and `/base` when `merge` returns, so they do not pin objects against gc (Reviewers 1, 2, 3, 5).
8. Silent passes: `ship_rule_floor` also passes when the classifier file is missing or the classifier errors. Keep that for hook parity, and name it in the Interfaces wording you touch and in `SECURITY.md` (Reviewers 2, 6).
9. Shallow clone: an orchestrator clone with `--depth` makes the merge base empty, which refuses. Say "shallow clone?" in that BLOCKED message (Reviewer 3).
10. `MEGA_MERGE_ROOT` pointed at a non-repo reaches `cat-file` and prints "not a commit", not "--head needs a repo". Either is a fail-closed BLOCKED; match the test to the real message (Reviewer 2).
11. SECURITY.md (TASK-3b): add two residuals, the PR-chosen spec in the head's tree (hook parity) and the base retarget window if item 1 is not built (Reviewer 1).
12. A head-moved refusal stops the whole wave in the converge loop; say so in the Edge Case 7 wording in the verification record (Reviewer 3).
13. Picture: add a `--fail--> BLOCKED` arm on `_pr_base` and a "validate SHAs and repo" step when the ADR or docs show the flow (Reviewer 6).

## Decisions made during the build

(none yet)
