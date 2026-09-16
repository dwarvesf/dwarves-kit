# Proof of done: spec-next mints against open PR heads, not only the local listing

2026-09-16. Acceptance: `lib/spec/spec-next.sh next` folds an open PR's `docs/specs/`
listing into its max-number scan when `gh` is on PATH and authenticated, via the GitHub
contents API on the PR's head ref (no clone, no fetch). Falls back to the original
local-only scan (docs/specs/, local+remote branches, recent commit subjects) with one
stderr note when `gh` is missing, unauthenticated, or a bootstrap call fails.
Skippable via `SPEC_NEXT_NO_PR_SCAN=1`. No spec doc; override recorded via gate-ledger
(scoped in the dispatch prompt). Board: ID-904. Files: `lib/spec/spec-next.sh`,
`tests/test-spec-next-pr-scan.sh`.

## The failure this closes

`spec-next` only scanned `docs/specs/` filenames, local/remote branch names, and recent
commit subjects. None of those surfaces show a number an OPEN, unmerged PR already holds.
On 2026-09-16 three parallel workers each called `next` before any of them merged; two got
SPEC-289, the third had to move to 290, a fourth PR later collided at 291 with a PR holding
288. None of the workers called the existing `reserve` atomic-claim path either, so the
reservation ledger did not help.

## Green run

Command: `bash tests/test-spec-next-pr-scan.sh`
Exit: 0
Output:
```
=== T1: gh present + authed, one open PR holds SPEC-0450 -> next folds it in ===
  PASS T1 next is 451 (local max 449, PR head holds 450)
=== T2: gh present but NOT authenticated -> local-only fallback + stderr note ===
  PASS T2 next falls back to local max+1 (450)
  PASS T2 stderr carries the not-scanned note
=== T3: SPEC_NEXT_NO_PR_SCAN=1 skips the scan even with a working gh stub ===
  PASS T3 opt-out ignores the PR head (local max+1 = 450)
  PASS T3 stderr names the opt-out reason
=== T4: no gh on PATH at all -> local-only fallback + stderr note ===
  PASS T4 next falls back to local max+1 (450) with no gh
  PASS T4 stderr says gh not on PATH
Passed: 7 / 7
spec-next-pr-scan green.
```
Verdict: PASS. Covers the fold-in case (T1), an authenticated-but-degraded case (T2), the
test-only opt-out (T3), and the no-`gh` case (T4), each checking both the returned number
and the stderr note's presence/absence.

Command: `bash tests/test-spec-reserve.sh`
Exit: 0
Output: `Passed: 41 / 41`, `spec-reserve green.`
Verdict: PASS. The existing reservation-race suite is unaffected: it isolates its own
temp repos and sets `SPEC_RESERVE_FILE`, and none of its fixture repos have `gh` reachable
in a way that changes a `next`/`reserve` result (no open PRs against those throwaway repos).

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: all 152 suites passed, 0 skipped for missing tooling`
Verdict: PASS. First run failed on `docs/FEATURES.md is fresh (regenerate == committed,
SPEC-219)` because the new test file shifts per-command touched-file counts in that
generated projection; `bash lib/registry/feature-registry.sh generate` produced a
counts-only diff and the suite went green on the next run.

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-spec-next-pr-scan.sh" "sed -i '' 's/_scan_pr_numbers | grep -oE .[0-9]+.; /true; /' lib/spec/spec-next.sh"`
Exit (pre-mutation): 0 (green)
Mutation: nulls the `_scan_pr_numbers` fold in `_numbers()` so an open PR's SPEC number
is never counted.
Exit (post-mutation): 1 (RED, as expected: T1 expects 451 and gets 450 with the fold
disabled)
Restore: `git checkout HEAD -- lib/spec/spec-next.sh`, exit 0 (green again)
Verdict: PASS (negctl printed `Verdict: PASS`).

## Reproducible

Any operator can re-run `bash tests/test-spec-next-pr-scan.sh` or `bash tests/run-all.sh`
from a checkout of this branch; the new test stubs `gh` on `PATH` so it needs no live
GitHub credentials or network access.
