# Implementation notes: mega-merge-head-pin

Delta from `docs/specs/SPEC-402-mega-merge-head-pin.md`. Validate round: 7 reviewers, APPROVED, 0 critical, 26 warnings. The warnings below are for the builder.

## Warnings for the builder

1. SECURITY.md line 14: edit only its last sentence (the `--match-head-commit` residual). Replace it with the residual that stays: the gate's diff rules read the orchestrator checkout's local `HEAD`, not the PR head, so the pin covers the guards that read the PR through `gh` but not the gate's diff rules. AC5 checks that the new sentence exists (Reviewers 1, 4, 5).
2. The verification record says plainly that AC4 proves the pin is passed and a refusal propagates. Server-side enforcement rests on GitHub's documented `--match-head-commit` behavior; no test exercises a real moved head (Reviewers 1, 2, 3, 4, 5).
3. Add the monotonic argument as a short code comment above the `_pr_head` call: the merge succeeds only if the head still equals H, and H was read before every guard, so every guard read H. A later reader must not move the read (Reviewers 3, 5).
4. `head-unreadable-refused`: add a two-line output case and a trailing `\r` case (Reviewer 2).
5. `head-moved-fails`: also assert the fake `gh` recorded no branch delete, so `--delete-branch` never runs on a refused merge (Reviewer 2).
6. AC3 needs a shared call log across the head, state and files stubs. That harness change is part of TASK-1 (Reviewer 3).
7. Keep the head stub in force in the `tests/test-mega-merge.sh` cases that use `env -u` or a PATH fake `gh` (around lines 120 and 167) (Reviewer 3). Grep the tests for every `merge` call path before relying on the two-file stub list (Reviewer 4).
8. `module-registry.md` row for `MEGA_MERGE_PR_HEAD_CMD`: say "test-only; never set in an unattended run" (Reviewer 1).
9. Inherited assumption: `gh pr view` and `gh pr merge` resolve the same cwd repo (no `--repo`), as `_pr_info` and `_pr_files` already do (Reviewers 1, 3).
10. TASK-3's control: name `head-read-first` red under the mutation that moves the read after `_merge_config_guard` (Reviewer 4).
11. A refused pin stops wave convergence on any push to a sub-goal PR, benign or not. That is deliberate; a rerun re-enters `merge` and pins the new head (Reviewer 2).

## Decisions made during the build

- No conflict between the spec and builder items 1 to 11 surfaced.
- `_pr_head` checks the value by length (40) plus a no-non-hex `case`, not a regex. A two-line value, a trailing `\r` and uppercase hex all fail without a `grep -x` that would match per line.
- The head stub in `tests/test-mega-merge.sh` reads `$TMP/head-out` and `$TMP/head-rc`, so the refusal cases mutate files instead of defining one stub per case. It is exported globally, so the `env -u` and PATH-fake-`gh` cases keep it (item 7).
- `head-moved-fails` uses a fake `gh` that logs `DELETED-BRANCH` only after an accepted merge, which is how item 5 asserts no branch delete on a refusal.
- Other callers: no other test calls `mega-merge.sh merge`. `test-ledger-durability.sh`, `test-goal-dispatch.sh` and `test-mega-gate-parity.sh` only source the file, hit usage, or call `gate`; `test-tier4-close.sh` uses its own `WAVE_MERGE_CMD`.
- `docs/FEATURES.md` was regenerated in the docs commit: the committed spec shifted three spec-reference counts, and `test-meta.sh` was red on that drift before this change.
- Code review (Sonnet, security plus correctness): no CRITICAL or HIGH. Fixed: the hex `case` now lists the characters instead of a locale-dependent range, the head-pin comment no longer claims the gate read H, and a 40-character non-hex case was added. Not fixed: `lib/goal/stack-merge.sh:90` merges with no pin; it runs only when the operator says merge, so it stays under the SECURITY.md unguarded-paths line. SHA-256 repos (64 hex) fail closed.
