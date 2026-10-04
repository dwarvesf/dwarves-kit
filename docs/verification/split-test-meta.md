# Verification: split-test-meta

Proof of done for the test-meta.sh split (SPEC-389). Baseline is the same file
on `master` (58918928), run in a detached worktree at
`/private/tmp/claude-501/sg02/base`.

## Recorded run

Command: `B=/private/tmp/claude-501/sg02/base; git worktree add --detach "$B" master && bash "$B"/tests/test-meta.sh > before.out 2>&1`
Exit: 0
Verdict: baseline green; final line `Passed: 902 / 902`, `All meta tests passed.`

## Recorded run

Command: `bash tests/test-meta.sh > after.out 2>&1; echo $?`
Exit: 0
Verdict: runner green in 152s (baseline serial run ~330s); final line `Passed: 902 / 902`, `All meta tests passed.`

## Recorded run

Command: `P='^  .\[0;3[12]m(PASS|FAIL)'; diff <(grep -aE "$P" before.out | sort) <(grep -aE "$P" after.out | sort); echo $?`
Exit: 0
Verdict: label parity holds; the PASS/FAIL line diff is empty both ways (902 lines each side, identical set).

## Recorded run

Command: `for a in plugin-hooks contract agents-commands spec-depth review-verifiers vmodel-dispatch goal-ledger docs-registry; do bash tests/test-meta-$a.sh; done` (each run standalone, sequentially, timing via $SECONDS)
Exit: 0 (every suite)
Verdict: each area suite passes standalone. Per-suite results (SG-03 consumes the wall times):

| Suite | Asserts | Wall time |
|---|---|---|
| test-meta-plugin-hooks.sh | 49 | 4s |
| test-meta-contract.sh | 47 | 2s |
| test-meta-agents-commands.sh | 266 | 1s |
| test-meta-spec-depth.sh | 96 | <1s |
| test-meta-review-verifiers.sh | 209 | 1s |
| test-meta-vmodel-dispatch.sh | 75 | 1s |
| test-meta-goal-ledger.sh | 40 | <1s |
| test-meta-docs-registry.sh | 120 | 159s |
| **total** | **902** | |

docs-registry is the long pole: the FEATURES.md freshness pin regenerates the
registry twice and the verification-log section scans docs/verification/*.
The runner schedules it first (largest file) so the parallel total is ~152s.

## Recorded run

Command: `bash lib/gate/verify-counts.sh`
Exit: 0
Verdict: `wrote docs/verification/COUNTS.md (meta=902/902, hooks=826/826)`; the meta row still resolves through the runner's `Passed:` line. (Regenerated COUNTS.md is committed; the committed copy had drifted to 717/717 on master.)

## Recorded run

Command: `EX=$(mktemp -d); git archive HEAD | tar -x -C "$EX"; cd "$EX" && bash tests/test-meta.sh; echo $?`
Exit: 0
Verdict: runner green on a clean `git archive HEAD` export (no .git): `Passed: 902 / 902`. Caveat, unchanged from the monolith: the namespace-guard section scans `git ls-files` output, which is empty on an export, so its absence-assert passes vacuously there; it is exercised for real in the worktree and CI runs (same pre-existing behavior as the monolith, not a split regression).

## Recorded run

Command: `bash tests/test-break-it.sh; bash tests/test-run-all-timeout.sh; bash tests/test-test-affected.sh`
Exit: 0 / 0 / 0
Verdict: caller suites green: 68/68 (axis extraction now reads test-meta-review-verifiers.sh), 7/7 (test-meta* timeout arm still 900), 35/35.

## Recorded run (negative control)

Command: `command cp -f tests/test-meta-agents-commands.sh /tmp/...saved; sed -i '' 's|commands/design.md" ]|commands/design-BROKEN.md" ]|' tests/test-meta-agents-commands.sh; bash tests/test-meta-agents-commands.sh`
Exit: 1
Verdict: broken suite red, exactly one FAIL (`commands/design.md missing`).

## Recorded run (negative control)

Command: `bash tests/test-meta.sh` (with the break in place)
Exit: 1
Verdict: runner red: `Passed: 901 / 902`, `Failed: 1`, relays the one broken assert.

## Recorded run (negative control)

Command: `bash tests/test-meta-plugin-hooks.sh; bash tests/test-meta-contract.sh` (with the break in place)
Exit: 0 / 0
Verdict: sibling suites unaffected by the break.

## Recorded run (negative control)

Command: `command cp -f /tmp/...saved tests/test-meta-agents-commands.sh; bash tests/test-meta-agents-commands.sh && bash tests/test-meta.sh`
Exit: 0
Verdict: restored byte-identical file (git diff clean), suite green, runner green (`Passed: 902 / 902`).

## Recorded run

Command: `bin/test-affected --base origin/master --list | grep test-meta`
Exit: 0
Verdict: the branch's own diff already demonstrates the pick path: meta_input changes (docs/*.md) pick `tests/test-meta.sh` (the runner), and run-all's runner-suites expansion maps it to the eight area suites; area suites are also picked directly via `tests/lib/meta-stub.sh` references and self-matches. No suite is scheduled twice (the `# runner:` file is skipped in the glob loop).
