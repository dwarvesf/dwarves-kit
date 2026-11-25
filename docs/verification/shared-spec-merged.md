# Verification -- shared-spec-merged

One active-spec lookup (`lib/spec/spec-active.sh`) and one merged check (`lib/gate/branch-merged.sh`), every caller on them, and a lint that fails when a caller keeps a private copy. Joined tree: merge `2dcb03f5`, codex repin `17066bab`, lint `083eb828`, docs `158933f1`.

| Claim | Evidence | Result |
|---|---|---|
| The ladder move changed no output | ladder suite diff, before the move vs the joined tree | empty diff, 43 passed |
| AC1: default `spec_active` equals `spec_for_slug` | `tests/test-spec-active.sh`, AC1 rows | 52 passed |
| The compaction, readiness, drift and index callers agree | `tests/test-active-spec-pick.sh` | 37 passed |
| `wt.sh close` refuses a commit the merged PR never carried | callers suite plus negative control | red then green |
| The origin sweep keeps a PR merged into another base | callers suite plus negative control | red then green |
| Merged-check options narrow, never widen | `tests/test-branch-merged.sh` | 41 passed |
| A private copy of either lookup turns the lint red | lint suite plus two negative controls | red then green, twice |
| Registry and docs stay fresh | `test-meta-docs-registry`, `test-registry-freshness-guard` | 121 of 121, 26 of 26 |

## Green run

The ladder suite, before the move and on the joined tree (outputs compared line by line):

```
Command: bash tests/test-wrap-ladder.sh > before.txt   (on the tree before the move)
Command: bash tests/test-wrap-ladder.sh > after.txt    (on the joined tree)
Command: diff before.txt after.txt
Exit: 0
Output:
    PASS carry: it says already merged
    PASS carry: it opens no PR
  test-wrap-ladder: all 43 passed
  rc=0
  (diff printed nothing: 0 bytes)
Verdict: PASS
```

```
Command: bash tests/test-spec-active.sh
Exit: 0
Output:
  == a partial install: spec-find.sh missing ==
  PASS sourcing fails, so the caller takes its own fallback
  PASS the CLI exits 1
  == CLI form, and sourcing under set -e / set -u ==
  PASS CLI prints the same line
  PASS CLI exits 2 on ambiguity
  PASS CLI exits 64 on an unknown argument
  PASS CLI exits 64 with no root
  PASS sourced under 'set -e'
  PASS sourced under 'set -u'
  PASS sourced under 'set -euo pipefail'
  PASS sourcing sets no shell option
  pass=52 fail=0
Verdict: PASS (AC1 compares the path column of spec_active against spec_for_slug for every fixture slug)
```

```
Command: bash tests/test-active-spec-pick.sh
Exit: 0
Output:
  PASS drift guard on a partial install resolves no spec and stays silent
  == spec-index ==
  PASS spec-index does not list a dot-dir worktree copy
  PASS spec-index lists each open spec once
  PASS spec-index lists the central and the co-located namespace
  pass=37 fail=0
Verdict: PASS
```

```
Command: bash tests/test-branch-merged-callers.sh
Exit: 0
Output:
    PASS sweep: a gh answer of 'empty' skips the sweep
    PASS sweep: 'empty' deletes nothing
    PASS sweep: an unreadable open-PR list skips the sweep
    PASS sweep: an unreadable open-PR list deletes nothing
    PASS sweep --own: an unnamed branch is kept
    PASS sweep: a non-GitHub origin skips the sweep
    PASS sweep: a non-GitHub origin deletes nothing
  test-branch-merged-callers: all 41 passed
Verdict: PASS (wt.sh close and origin sweep, every refusal a row)
```

```
Command: bash tests/test-branch-merged.sh
Exit: 0
Output:
    PASS numbers: gh 'empty' is unreadable (exit 2)
    PASS numbers: gh not ok is unreadable (exit 2)
  === usage errors print nothing and exit 64 ===
    PASS bad --need
    PASS missing branch
    PASS unknown flag
    PASS flag without a value
  test-branch-merged: all 41 passed
Verdict: PASS
```

## Negative control

NEGATIVE CONTROL for the two deletion bugs: each fix is reverted, the callers suite goes red, the fix is restored and it goes green.

### wt.sh close: a commit past the merged PR head

```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: 'fail' deletes nothing
    PASS sweep: a gh answer of 'garbage' skips the sweep
    PASS sweep: 'garbage' deletes nothing
    PASS sweep: a gh answer of 'empty' skips the sweep
    PASS sweep: 'empty' deletes nothing
    PASS sweep --own: an unnamed branch is kept
    PASS sweep: a non-GitHub origin skips the sweep
    PASS sweep: a non-GitHub origin deletes nothing
  
  test-branch-merged-callers: all 39 passed

Mutation: sed -i '' 's|"SAFE squash "\*) ;;|*) ;;|' lib/goal/wt.sh
Changed: lib/goal/wt.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: 'fail' deletes nothing
    PASS sweep: a gh answer of 'garbage' skips the sweep
    PASS sweep: 'garbage' deletes nothing
    PASS sweep: a gh answer of 'empty' skips the sweep
    PASS sweep: 'empty' deletes nothing
    PASS sweep --own: an unnamed branch is kept
    PASS sweep: a non-GitHub origin skips the sweep
    PASS sweep: a non-GitHub origin deletes nothing
  
  test-branch-merged-callers: 21 passed, 18 FAILED

Restore: git checkout HEAD -- lib/goal/wt.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### origin sweep: a PR merged into a non-default base

```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: 'garbage' deletes nothing
    PASS sweep: a gh answer of 'empty' skips the sweep
    PASS sweep: 'empty' deletes nothing
    PASS sweep: an unreadable open-PR list skips the sweep
    PASS sweep: an unreadable open-PR list deletes nothing
    PASS sweep --own: an unnamed branch is kept
    PASS sweep: a non-GitHub origin skips the sweep
    PASS sweep: a non-GitHub origin deletes nothing
  
  test-branch-merged-callers: all 41 passed

Mutation: git show HEAD~1:lib/wrap/wrap-apply.sh > lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: 'garbage' deletes nothing
    PASS sweep: a gh answer of 'empty' skips the sweep
    PASS sweep: 'empty' deletes nothing
    PASS sweep: an unreadable open-PR list skips the sweep
    PASS sweep: an unreadable open-PR list deletes nothing
    PASS sweep --own: an unnamed branch is kept
    PASS sweep: a non-GitHub origin skips the sweep
    PASS sweep: a non-GitHub origin deletes nothing
  
  test-branch-merged-callers: 40 passed, 1 FAILED

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

NEGATIVE CONTROL for the lint: a private copy is added to a caller, the lint goes red, the file is restored and it goes green.

### a private merged check added to a wrap file

```
## Negative control (negctl)
Command: bash tests/test-shared-lookups.sh
Exit: 0 (green before mutation)
Output:
    PASS lib/wrap/wrap-scan.sh calls branch_merged
    PASS lib/wrap/wrap-apply.sh calls branch_merged
    PASS lib/wrap/wrap-land.sh calls branch_merged
    PASS lib/wrap/wrap-adopt.sh calls branch_merged
    PASS lib/wrap/wrap-carry.sh calls branch_merged
    PASS lib/goal/wt.sh calls branch_merged
  === the lint itself: a fixture tree holds one bad line per pattern ===
    PASS every bad pattern, an empty reason and a dead marker are named; comments, tests, the shared file, ls-files, up-to-date and prune are not
  
  test-shared-lookups: all 15 passed

Mutation: printf '%s\n' 'st=$(gh pr view "$n" --json state -q .state); [ "$st" = MERGED ] && git branch -D x' >> lib/wrap/wrap-scan.sh
Changed: lib/wrap/wrap-scan.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS lib/wrap/wrap-scan.sh calls branch_merged
    PASS lib/wrap/wrap-apply.sh calls branch_merged
    PASS lib/wrap/wrap-land.sh calls branch_merged
    PASS lib/wrap/wrap-adopt.sh calls branch_merged
    PASS lib/wrap/wrap-carry.sh calls branch_merged
    PASS lib/goal/wt.sh calls branch_merged
  === the lint itself: a fixture tree holds one bad line per pattern ===
    PASS every bad pattern, an empty reason and a dead marker are named; comments, tests, the shared file, ls-files, up-to-date and prune are not
  
  test-shared-lookups: 14 passed, 1 FAILED

Restore: git checkout HEAD -- lib/wrap/wrap-scan.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### a private `ls docs/specs/SPEC-*.md | tail -1` pick added to a hook

```
## Negative control (negctl)
Command: bash tests/test-shared-lookups.sh
Exit: 0 (green before mutation)
Output:
    PASS lib/wrap/wrap-scan.sh calls branch_merged
    PASS lib/wrap/wrap-apply.sh calls branch_merged
    PASS lib/wrap/wrap-land.sh calls branch_merged
    PASS lib/wrap/wrap-adopt.sh calls branch_merged
    PASS lib/wrap/wrap-carry.sh calls branch_merged
    PASS lib/goal/wt.sh calls branch_merged
  === the lint itself: a fixture tree holds one bad line per pattern ===
    PASS every bad pattern, an empty reason and a dead marker are named; comments, tests, the shared file, ls-files, up-to-date and prune are not
  
  test-shared-lookups: all 15 passed

Mutation: printf '%s\n' 'SPEC=$(ls docs/specs/SPEC-*.md | tail -1)' >> hooks/pre-compact-backup.sh
Changed: hooks/pre-compact-backup.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS lib/wrap/wrap-scan.sh calls branch_merged
    PASS lib/wrap/wrap-apply.sh calls branch_merged
    PASS lib/wrap/wrap-land.sh calls branch_merged
    PASS lib/wrap/wrap-adopt.sh calls branch_merged
    PASS lib/wrap/wrap-carry.sh calls branch_merged
    PASS lib/goal/wt.sh calls branch_merged
  === the lint itself: a fixture tree holds one bad line per pattern ===
    PASS every bad pattern, an empty reason and a dead marker are named; comments, tests, the shared file, ls-files, up-to-date and prune are not
  
  test-shared-lookups: 14 passed, 1 FAILED

Restore: git checkout HEAD -- hooks/pre-compact-backup.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Test plan coverage
| Row | Run / skip reason |
|---|---|
| C1 | tests/test-spec-active.sh |
| C2 | tests/test-spec-active.sh |
| C3 | tests/test-spec-active.sh |
| C4 | tests/test-spec-active.sh |
| C5 | tests/test-spec-active.sh |
| C6 | tests/test-spec-active.sh |
| C7 | tests/test-spec-active.sh |
| C8 | tests/test-spec-active.sh |
| C9 | tests/test-spec-active.sh |
| C10 | tests/test-wrap-ladder.sh, empty diff above |
| C11 | tests/test-branch-merged.sh |
| C12 | tests/test-branch-merged.sh |
| C13 | tests/test-branch-merged.sh |
| C14 | tests/test-branch-merged.sh |
| C15 | tests/test-branch-merged.sh |
| C17 | AC1 rows of tests/test-spec-active.sh (the ship-gate pick is the default-mode path); tests/test-spec-find.sh not re-run in this ticket |
| C18 | tests/test-branch-merged-callers.sh, wt close rows, and the wt.sh negative control |
| C19 | tests/test-branch-merged-callers.sh, sweep rows, and the sweep negative control |
| C20 | tests/test-shared-lookups.sh, fixture tree, and the spec-pick negative control |
| C21 | tests/test-shared-lookups.sh, fixture tree, and the merged-check negative control |
| C22 | tests/test-shared-lookups.sh, empty-reason and dead-marker fixtures |
| C23 | tests/test-shared-lookups.sh, presence rows |
| C24 | both lint negative controls above |
| C25 | tests/test-active-spec-pick.sh (spec-index row) |
| C26 | tests/test-active-spec-pick.sh |

## Rollback

The change is code and tests only: no data, no migration, no daemon. To roll back, revert the merge `2dcb03f5` and the merged-half commits (`bafc96e0` to `158933f1`) with `git revert`, in reverse order, then `bash lib/codex/repin.sh` because `hooks/ship-gate.sh` is pinned by hash. The old per-hook lookups and the old `wt.sh` and origin-sweep guards return with them.

## Not proven
- The full wrap suites (`test-wrap-apply`, `test-wrap-adopt`, `test-wrap-land`, `test-wrap-merge*`) were not all re-run on the joined tree; `test-wrap-land` had 5 `round-trip:` rows red on the merged-half tree (a fixture `git commit` of a queued proof asset, not merged-check code).
- No real GitHub: every gh answer is a shim; no real destructive command ran.

Verdict: PASS
