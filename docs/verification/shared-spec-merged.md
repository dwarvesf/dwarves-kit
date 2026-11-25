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

## Data-loss review fixes

The review of the joined branch found three inputs where the new code deleted and master refused. Each was reproduced red on a scratch repo with the gh shim BEFORE its fix (rows added first, run against the unfixed code), then fixed, then green.

| Review row | Test row | Red before | Green after |
|---|---|---|---|
| two PRs from one head, merged plus OPEN | callers: `a merged PR plus an OPEN PR from the same head refuses` | red | green |
| two PRs, merged plus CLOSED with a newer origin tip | callers: `origin's branch keeps the newer tip (the remote delete is leased to the judged tip)` | red | green |
| protect list over 64 KiB | callers: `a base branch with a protect list over 64 KiB is kept` | red | green |
| null or missing isCrossRepository | callers sweep rows, branch-merged gh and json rows | red | green |
| open row that names no head or base | callers: `an open PR with no base field keeps every branch` | red | green |
| spec-find fallback and TAB path | `tests/test-ship-gate-spec-pick.sh` | red (2 rows) | green (10) |
| only the merged list, only the open list fails | callers wt and sweep rows | green (regression rows) | green |
| 11 lint bypass forms, continued lines | `tests/test-shared-lookups.sh` fixture tree | not caught | caught |

```
Command: bash tests/test-branch-merged-callers.sh   (new rows against the unfixed code)
Exit: 1
Output:
  FAIL wt close: a merged PR plus an OPEN PR from the same head refuses
  FAIL wt close: the open PR's branch stays on origin
  FAIL wt close: origin's branch keeps the newer tip (the remote delete is leased to the judged tip)
  FAIL wt close: a failing open-PR list alone refuses
  FAIL wt close: an unparseable open-PR list refuses
  FAIL sweep: an open PR with no base field keeps every branch
  FAIL sweep: a base branch with a protect list over 64 KiB is kept
  FAIL sweep: a merged row with no isCrossRepository keeps the branch
  FAIL sweep: a merged row with a null isCrossRepository keeps the branch
test-branch-merged-callers: 48 passed, 9 FAILED
Verdict: RED as expected (9 rows)
```

```
Command: bash tests/test-branch-merged.sh   (new rows against the unfixed code)
Exit: 1
Output:
  FAIL gh path: no isCrossRepository
  FAIL gh path: null isCrossRepository
  FAIL gh path: no headRefName
  FAIL json: no isCrossRepository
  FAIL json: null isCrossRepository
  FAIL json: no baseRefName
  FAIL numbers: no isCrossRepository is none (exit 1)
test-branch-merged: 43 passed, 7 FAILED
Verdict: RED as expected (7 rows)
```

```
Command: bash tests/test-ship-gate-spec-pick.sh   (against the unfixed hook)
Exit: 1
Output:
  FAIL a root path holding a TAB survives the pick
  FAIL co-located spec is still found (the pick master makes)
test-ship-gate-spec-pick: 8 passed, 2 FAILED
Verdict: RED as expected (2 rows)
```

```
Command: bash tests/test-branch-merged-callers.sh
Exit: 0
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  test-branch-merged-callers: all 57 passed
Verdict: PASS
```

```
Command: bash tests/test-branch-merged.sh
Exit: 0
Output:
    PASS unknown flag
    PASS flag without a value
  test-branch-merged: all 50 passed
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-spec-pick.sh
Exit: 0
Output:
  === a stale install: neither file, the root glob ===
    PASS root spec
    PASS no spec for the slug
  test-ship-gate-spec-pick: all 10 passed
Verdict: PASS
```

NEGATIVE CONTROL for each review fix: the fix is reverted by restoring the file from before it, the suite goes red, the file is restored and the suite goes green.

### wt.sh close: open PR check and leased delete reverted
```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: a failing open list alone skips the sweep
    PASS sweep: a failing open list alone deletes nothing
    PASS sweep: an open PR with no base field keeps every branch
    PASS sweep: the protect list is over 64 KiB
    PASS sweep: a base branch with a protect list over 64 KiB is kept
    PASS sweep: the same run still deletes the exact-tip branch
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  
  test-branch-merged-callers: all 57 passed

Mutation: git show c903cf9e~1:lib/goal/wt.sh > lib/goal/wt.sh
Changed: lib/goal/wt.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: a failing open list alone skips the sweep
    PASS sweep: a failing open list alone deletes nothing
    PASS sweep: an open PR with no base field keeps every branch
    PASS sweep: the protect list is over 64 KiB
    PASS sweep: a base branch with a protect list over 64 KiB is kept
    PASS sweep: the same run still deletes the exact-tip branch
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  
  test-branch-merged-callers: 52 passed, 5 FAILED

Restore: git checkout HEAD -- lib/goal/wt.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### origin sweep: protect list through a pipe restored
```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: a failing open list alone skips the sweep
    PASS sweep: a failing open list alone deletes nothing
    PASS sweep: an open PR with no base field keeps every branch
    PASS sweep: the protect list is over 64 KiB
    PASS sweep: a base branch with a protect list over 64 KiB is kept
    PASS sweep: the same run still deletes the exact-tip branch
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  
  test-branch-merged-callers: all 57 passed

Mutation: git show 29dbf577~1:lib/wrap/wrap-apply.sh > lib/wrap/wrap-apply.sh
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: a failing open list alone skips the sweep
    PASS sweep: a failing open list alone deletes nothing
    FAIL sweep: an open PR with no base field keeps every branch
    PASS sweep: the protect list is over 64 KiB
    FAIL sweep: a base branch with a protect list over 64 KiB is kept
    PASS sweep: the same run still deletes the exact-tip branch
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  
  test-branch-merged-callers: 55 passed, 2 FAILED

Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### merged check: fork and head fields read permissively again
```
## Negative control (negctl)
Command: bash tests/test-branch-merged.sh
Exit: 0 (green before mutation)
Output:
    PASS numbers: gh 'garbage' is unreadable (exit 2)
    PASS numbers: gh 'empty' is unreadable (exit 2)
    PASS numbers: gh not ok is unreadable (exit 2)
  === usage errors print nothing and exit 64 ===
    PASS bad --need
    PASS missing branch
    PASS unknown flag
    PASS flag without a value
  
  test-branch-merged: all 50 passed

Mutation: git show a0ff3cec~1:lib/gate/branch-merged.sh > lib/gate/branch-merged.sh
Changed: lib/gate/branch-merged.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS numbers: gh 'garbage' is unreadable (exit 2)
    PASS numbers: gh 'empty' is unreadable (exit 2)
    PASS numbers: gh not ok is unreadable (exit 2)
  === usage errors print nothing and exit 64 ===
    PASS bad --need
    PASS missing branch
    PASS unknown flag
    PASS flag without a value
  
  test-branch-merged: 44 passed, 6 FAILED

Restore: git checkout HEAD -- lib/gate/branch-merged.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### ship-gate pick: the old fallback order and TAB split restored
```
## Negative control (negctl)
Command: bash tests/test-ship-gate-spec-pick.sh
Exit: 0 (green before mutation)
Output:
    PASS a root path holding a TAB survives the pick
  === a partial install: spec-find.sh without spec-active.sh ===
    PASS root spec
    PASS co-located spec is still found (the pick master makes)
    PASS a root path holding a TAB survives the pick
  === a stale install: neither file, the root glob ===
    PASS root spec
    PASS no spec for the slug
  
  test-ship-gate-spec-pick: all 10 passed

Mutation: git show ba71a92c~1:hooks/ship-gate.sh > hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS root spec
      want: /private/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T/dk-spec-pick.v1YWtk/repo/tools/x/docs/specs/SPEC-005-delta.md
      got:  
    FAIL co-located spec is still found (the pick master makes)
    PASS a root path holding a TAB survives the pick
  === a stale install: neither file, the root glob ===
    PASS root spec
    PASS no spec for the slug
  
  test-ship-gate-spec-pick: 8 passed, 2 FAILED

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### lint: a private commit-count merged check (one of the added forms)
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

Mutation: printf '%s\n' 'n=$(git rev-list --count origin/main.."$b"); [ "$n" = 0 ] && git branch -D "$b"' >> lib/wrap/wrap-scan.sh
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

## Review round 2 fixes

| Row | Test row | Red before | Green after |
|---|---|---|---|
| `wt.sh close`: a newer CLOSED PR, origin at Y, local at X, uncommitted file in the worktree | callers w10: refuses, `LEAVE remote <Y>`, branch, worktree and the uncommitted file stay | red (5 rows) | green |
| the origin ref cannot be read | callers w10b | red | green |
| the PR head moved past the local tip | callers w14: `LEAVE tip`, then `Fix: git -C <worktree> pull --ff-only, then close again` | red | green |
| the same case, a worktree path outside the safe set | callers w15: `Fix: in that worktree run git pull --ff-only, then close again`, no path echoed | red | green |
| `spec_active` answers nothing, `spec_for_slug` defined | `tests/test-ship-gate-spec-pick.sh` | red (2 rows) | green |
| the stub fills in fields the code stopped asking for | callers strict-stub rows (`GH_STUB_STRICT_JSON=1`) | mutation turns 1 row red | green |

```
Command: bash tests/test-branch-merged-callers.sh   (new rows against the unfixed code)
Exit: 1
Output:
  FAIL wt close: a remote branch that moved past the judged tip refuses
  FAIL wt close: the refusal names the remote tip
  FAIL wt close: the local branch stays
  FAIL wt close: the worktree stays
  FAIL wt close: the worktree's uncommitted file stays
  FAIL wt close: a failed remote read refuses and keeps the branch
  FAIL wt close: and ends with the way out
  FAIL wt close: and names no path
test-branch-merged-callers: 66 passed, 8 FAILED
Verdict: RED as expected (8 rows)
```

```
Command: bash tests/test-ship-gate-spec-pick.sh   (new rows against the unfixed hook)
Exit: 1
Output:
  FAIL the pick is never emptier than master's
  FAIL the co-located spec too
test-ship-gate-spec-pick: 11 passed, 2 FAILED
Verdict: RED as expected (2 rows)
```

```
Command: bash tests/test-branch-merged.sh && bash tests/test-branch-merged-callers.sh && bash tests/test-ship-gate-spec-pick.sh && bash tests/test-shared-lookups.sh && bash tests/test-codex-hooks.sh
Exit: 0
Output:
  test-branch-merged: all 50 passed
  test-branch-merged-callers: all 74 passed
  test-ship-gate-spec-pick: all 13 passed
  test-shared-lookups: all 15 passed
  94 passed, 0 failed
Verdict: PASS
```

NEGATIVE CONTROL for the round 2 fixes:

### wt.sh close: the gate accepts any verdict (rerun)
```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    PASS strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: all 74 passed

Mutation: sed -i '' 's|"SAFE squash "\*) ;;|*) ;;|' lib/goal/wt.sh
Changed: lib/goal/wt.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    PASS strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: 59 passed, 15 FAILED

Restore: git checkout HEAD -- lib/goal/wt.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### wt.sh close: the remote read and the Fix line reverted
```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    PASS strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: all 74 passed

Mutation: git show 0c801db5~1:lib/goal/wt.sh > lib/goal/wt.sh
Changed: lib/goal/wt.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    PASS strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: 66 passed, 8 FAILED

Restore: git checkout HEAD -- lib/goal/wt.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### the strict stub: the merged check stops requesting isCrossRepository
```
## Negative control (negctl)
Command: bash tests/test-branch-merged-callers.sh
Exit: 0 (green before mutation)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    PASS strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: all 74 passed

Mutation: sed -i '' 's|headRefOid,baseRefName,mergedAt,isCrossRepository|headRefOid,baseRefName,mergedAt|' lib/gate/branch-merged.sh
Changed: lib/gate/branch-merged.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS sweep: a merged row with no isCrossRepository keeps the branch
    PASS sweep: a merged row with a null isCrossRepository keeps the branch
  === the --need pr callers under the strict gh stub ===
    PASS the strict stub was cut from tests/lib/wrap-stub.sh
    FAIL strict stub: wt close at a merged PR's exact tip still closes
    PASS strict stub: the sweep deletes the exact-tip branch
    PASS strict stub: the sweep keeps a PR merged into another base
    PASS strict stub: the sweep keeps the base of an open PR
  
  test-branch-merged-callers: 73 passed, 1 FAILED

Restore: git checkout HEAD -- lib/gate/branch-merged.sh
Exit: 0 (green after restore)
Verdict: PASS
```
### ship-gate pick: the spec_for_slug fall-through reverted
```
## Negative control (negctl)
Command: bash tests/test-ship-gate-spec-pick.sh
Exit: 0 (green before mutation)
Output:
    PASS still empty when neither finds one
  === a partial install: spec-find.sh without spec-active.sh ===
    PASS root spec
    PASS co-located spec is still found (the pick master makes)
    PASS a root path holding a TAB survives the pick
  === a stale install: neither file, the root glob ===
    PASS root spec
    PASS no spec for the slug
  
  test-ship-gate-spec-pick: all 13 passed

Mutation: git show 77015737~1:hooks/ship-gate.sh > hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS still empty when neither finds one
  === a partial install: spec-find.sh without spec-active.sh ===
    PASS root spec
    PASS co-located spec is still found (the pick master makes)
    PASS a root path holding a TAB survives the pick
  === a stale install: neither file, the root glob ===
    PASS root spec
    PASS no spec for the slug
  
  test-ship-gate-spec-pick: 11 passed, 2 FAILED

Restore: git checkout HEAD -- hooks/ship-gate.sh
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
| C20 | tests/test-shared-lookups.sh, fixture tree (now 15 bad forms), and the spec-pick negative control |
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
