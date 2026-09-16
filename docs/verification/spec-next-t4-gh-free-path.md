# Proof of done: T4's no-gh PATH is provably gh-free everywhere

2026-09-16. Fix-forward for PR #661's CI failure: `tests/test-spec-next-pr-scan.sh` T4
built its "no gh on PATH" case as `NOGH_BIN:/usr/bin:/bin:/usr/sbin:/sbin`, assuming
those four dirs never hold `gh`. True on the author's Mac (Homebrew `gh` lives elsewhere)
but false on GitHub's ubuntu runners, where `gh` is preinstalled at `/usr/bin/gh`. T4 then
silently ran the wrong branch: `gh` was reachable, so `gh auth status` failed unauthenticated
and the stderr note read "not authenticated" instead of the asserted "not on PATH". CI red,
local green. No spec doc; override recorded via gate-ledger (scoped by the coordinator's
fix-forward message). Files: `tests/test-spec-next-pr-scan.sh`.

## The failure this closes

Fixed-directory-list PATH construction cannot be portable across machines with different
package-manager layouts. `tests/test-spec-next-pr-scan.sh` T4 is rewritten to filter the
REAL `$PATH`'s directories, dropping any directory that itself contains an executable
named `gh`, then asserts `command -v gh` fails on the resulting PATH before running the
case. The assertion is a real test, not a comment: if the filter is later broken, T4 fails
loudly instead of silently drifting onto the wrong code path again.

## Green run

Command: `bash tests/test-spec-next-pr-scan.sh` (gh present on the ambient PATH)
Exit: 0
Output: `Passed: 8 / 8`, `spec-next-pr-scan green.` (includes the new "T4 setup: gh is
provably absent from the built PATH" assertion)
Verdict: PASS.

Command: `PATH=/usr/bin:/bin bash tests/test-spec-next-pr-scan.sh` (simulating an
environment with no `gh` reachable at all, per the coordinator's reproduction ask)
Exit: 0
Output: `Passed: 8 / 8`, `spec-next-pr-scan green.`
Verdict: PASS. Same result with or without `gh` ambiently present, because T4 now builds
its own filtered PATH rather than trusting the ambient one.

Command: `bash tests/run-all.sh`
Exit: 0
Output: `run-all: all 152 suites passed, 0 skipped for missing tooling`
Verdict: PASS.

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-spec-next-pr-scan.sh" "sed -i '' 's/\[ -x \"\$_d\/gh\" \] && continue/false && continue/' tests/test-spec-next-pr-scan.sh"`
Exit (pre-mutation): 0 (green)
Mutation: disables the per-directory `gh`-exclusion filter, letting a `gh`-holding
directory back onto the built PATH (reproducing the exact CI bug).
Exit (post-mutation): 1 (RED, as expected)
Restore: `git checkout HEAD -- tests/test-spec-next-pr-scan.sh`, exit 0 (green again)
Verdict: PASS (negctl printed `Verdict: PASS`).

## Reproducible

`bash tests/test-spec-next-pr-scan.sh` and `PATH=/usr/bin:/bin bash tests/test-spec-next-pr-scan.sh`
both need only `bash` and `git`; no network, no live GitHub credentials.
