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

Delta from the spec and the warnings above.

- Items 1 to 13 are built, with these differences. Item 1: `merge` reads `_pr_base` again only before `EXECUTING`, not on a dry-run (a dry-run merges nothing). Item 13 is a picture change only and is not applied to the spec.
- Item 2: the fetch timeout is `MEGA_MERGE_FETCH_TIMEOUT` (seconds, default 60), a new env knob with a registry row (the spec lists two knobs; this is a third). The wait polls `kill -0` every 0.1 s and sends TERM, then KILL after 1 s. A first version used a watchdog subshell and `kill`; it hung 60 s per merge under `negctl.sh`, which hands its children an ignored TERM, so it was replaced.
- Item 4: the name rules live in `spec_path_matches` (`lib/spec/spec-find.sh`) and the head-mode lookup uses it. `spec_for_slug` keeps its own `ls` glob, untouched, so the hook path cannot drift. The two must agree; the hyphenated and non-numeric co-located cases pin that.
- `ship_rule_large_spec` takes an optional fifth argument, the path its message names, so head mode prints the in-tree path and not the scratch file. The hook passes four arguments and is unchanged. `hooks/` did not change, so `hooks/codex-hooks.json` is not repinned.
- Item 5: the fetch override replaces the fetch and the head comparison. The gate's head validation (40 lowercase hex, a commit in the repo) covers both `H` and the printed tip, so a bad tip refuses with a `BLOCKED: mega gate:` message from the gate, not the fetch message.
- `--head` with a `MEGA_MERGE_ROOT` that is not a repo reaches `cat-file` and prints `is not a commit` (item 10); the test matches that message.
- Private refs are deleted right after the gate returns (and inside `_pr_fetch` on a failure), not at function exit: only the objects matter after the gate, and this avoids a RETURN trap.
- Item 8: the silent passes (no ledger file, `lane_gates` off at the base, missing or failing classifier) are named in the `gate` header comment and in `SECURITY.md`.
- Existing merge tests (`test-mega-merge.sh`, `test-mega-reconcile.sh`) now run against a throwaway one-commit repo set as `MEGA_MERGE_ROOT`, with base and fetch stubs; head and tip are the same commit, so the diff is empty. They no longer read the kit repo.
- `docs/FEATURES.md` was regenerated: `test-meta.sh` reported drift from the spec file itself.
- `docs/verification/mega-gate-pr-head-e2e.sh` uses the real `gate-ledger.sh` against a temp `DWARVES_KIT_LOG_DIR` only, as `test-mega-reconcile.sh` does; no ledger record was written for this spec.
- Security review fix 1: in head mode every config read is at the base-branch tip `T` (`--base-tip`, else the resolved default branch), not at `merge-base(H, T)`; the merge base only scopes the diff. `ship_rule_floor` takes an optional 7th argument `<cfg-rev>` and hands it to the classifier as `KIT_FLOOR_CONFIG_AT` (set to empty on the hook path, so an ambient value never reaches the hook). Unset, every read stays at the base.
- Security review fix 2: `lane_extra_hard_paths` also unions the `.kit.toml` committed at `KIT_FLOOR_CONFIG_AT`. The working tree and `HEAD` copies still count (they only add entries); the `mega-merge.sh` header no longer says the gate never reads the working tree.
- Security review fix 3: head mode refuses when `merge-base == H`, whatever `T` is. A fetch override printing `H` (or a descendant of `H`) as the tip would otherwise make the diff empty. Cost: a PR already inside its base branch is refused; it has nothing to merge. The `test-mega-merge.sh` and `test-mega-reconcile.sh` fixtures now have a head one commit ahead of the tip.
- Security review fix 4: `MEGA_MERGE_FETCH_TIMEOUT` must be all digits before the fetch starts. The value fed `$(( ))`, which evaluates `a[$(cmd)]` as code.
- Security review fix 5: `git merge-base --all H T` with more than one base refuses (`ambiguous merge base`); the gate never picks one.

### Negative controls (security review fixes)

- `head-mode-config-at-tip`: head cut from a `lane_gates = false` commit, tip has it on; RED on the old code (gate passes), GREEN now.
- `head-mode-extras-at-tip`: stale head and checkout, `extra_hard_paths` committed only at the tip; RED then GREEN.
- `head-mode-base-is-head`: head equal to the tip, and head already inside the tip; RED then GREEN. The head-ahead case stays green both ways.
- `head-mode-criss-cross`: two merge bases; RED then GREEN.
- `merge-fetch-timeout-value`: `abc`, `-5`, `1.5`, `1 2` and `a[$(touch ...)]`; RED then GREEN, and the injected command never ran.
