# Verification -- spec-next-empty-repo

`spec-next.sh reserve` now succeeds on a fresh repo with no spec numbers anywhere, and prints the first number (001).

## Change

- Root cause: `_scan_numbers` ends in `grep -oE '[0-9]+'`, which exits 1 on empty input. Under `set -euo pipefail` the function returned 1 on a repo with no specs, branches, or SPEC commit subjects. `_prune_reservations` calls `realized="$(_scan_numbers)"`, so `set -e` killed `reserve` after the ledger line was written and before the number was printed: rc=1, no stdout. `next` and `check` were not hit (their pipelines absorb it).
- Fix: the final `grep` in `_scan_numbers` is wrapped as `{ grep -oE '[0-9]+' || true; }`. One place, every caller covered.
- Not done: nested spec numbers in open PR heads (`_scan_pr_numbers` lists only root `docs/specs`). That needs a tree listing per head, not a small change.

## Green run

```
Command: /bin/bash tests/test-spec-reserve.sh   (macOS bash 3.2)
Exit: 0
Output:
PASS T25 first reserve on an empty repo prints 001 and exits 0
PASS T25 second reserve sees the first claim and prints 002
PASS T25 next on the empty repo reads the ledger (003)
PASS T25 the lock is released after the empty-repo reserve
Passed: 71 / 71
spec-reserve green.
Verdict: PASS
```

Neighbor suite: `bash tests/test-spec-next-pr-scan.sh` passed 8 / 8.

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "/bin/bash tests/test-spec-reserve.sh" "git show a31525d6:lib/spec/spec-next.sh > lib/spec/spec-next.sh"
Exit: 1 (under mutation, RED expected)
Output:
FAIL T25 first reserve on an empty repo prints 001 and exits 0 (got rc=1)
FAIL T25 second reserve sees the first claim and prints 002 (got rc=1)
Passed: 69 / 71
Restore: git checkout HEAD -- lib/spec/spec-next.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduction

Fresh `git init`, no `docs/specs`, `SPEC_NEXT_NO_PR_SCAN=1`, two `reserve` calls.

| Revision | Call 1 | Call 2 |
|---|---|---|
| before (master) | rc=1, no stdout | rc=1, no stdout |
| after (this branch) | `001`, rc=0 | `002`, rc=0 |
