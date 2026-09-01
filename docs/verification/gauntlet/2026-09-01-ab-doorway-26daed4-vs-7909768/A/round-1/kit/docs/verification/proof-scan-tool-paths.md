# Proof of done: proof-scan-tool-paths (ID-478)

Class: behavioral. Widens `lib/gate/proof-ledger.sh` `_fresh_proof_files()` and the
set-wise directory-grouping in `check()` to also accept a proof co-located at
`tools/<name>/docs/verification/<slug>.md` (a monorepo's per-tool convention),
alongside the existing repo-root `docs/verification/<slug>.md` and
`.../proof-of-done.md` shapes.

## GREEN (real run)

New regression test, `tests/test-proof-tool-verification-path.sh`, against a
fixture with a fresh proof at `tools/x/docs/verification/vf-tool.md`:

Command: `bash tests/test-proof-tool-verification-path.sh`
Exit: 0
Verdict: PASS
Output:

```
PASS tools/<name>/docs/verification/<slug>.md proof satisfies the gate
ALL PASS (1/1)
```

Full gate-related suite (every `tests/test-proof-*.sh` plus adjacent proof-ledger
consumers), all green except two pre-existing failures confirmed unrelated to
this change (see NEGATIVE CONTROL below):

Command: `bash tests/test-proof-dir-layout.sh && bash tests/test-proof-visual-evidence.sh && bash tests/test-deployable-done.sh && bash tests/test-delivery-ratio.sh`
Exit: 0
Verdict: PASS (3/3, 4/4, 17/17, 8/8 respectively)

The full hook regression suite also passes clean:

Command: `bash tests/test-hooks.sh`
Exit: 0
Verdict: PASS
Output tail:

```
=== Results ===
Passed: 492 / 492
All tests passed.
```

## NEGATIVE CONTROL

Reverted `lib/gate/proof-ledger.sh` to its pre-fix content (`git show HEAD^:...`)
and re-ran the new test: it goes RED (the co-located tool-path proof is invisible
to the pre-fix scan, reproducing the bug), then the fix was restored
(`git checkout -- lib/gate/proof-ledger.sh`) and the test goes GREEN again.

Command: `bash tests/test-proof-tool-verification-path.sh` (pre-fix lib)
Exit: 1
Output: `FAIL co-located tool verification proof should ACCEPT but the gate BLOCKED`

Command: `bash tests/test-proof-tool-verification-path.sh` (fix restored)
Exit: 0
Output: `PASS tools/<name>/docs/verification/<slug>.md proof satisfies the gate`

## Pre-existing unrelated failures (documented, not caused by this change)

Two tests fail identically on a pristine checkout with NO uncommitted diff to
`lib/gate/proof-ledger.sh` (verified by stashing this branch's diff and re-running
each in isolation), so neither is a regression from this fix:

- `tests/test-proof-override-order.sh`: its own negative-control step (step 6)
  assumes the SOLE uncommitted diff to `lib/gate/proof-ledger.sh` is the
  override-order fix it guards, and stashes whatever diff is present to simulate
  reverting it. With this branch's unrelated diff present, stashing it reverts to
  `HEAD` (which already carries the override-order fix, committed separately), so
  the expected re-block never reproduces. On a clean checkout it instead prints
  `[NO EXECUTABLE CHECK: ... no uncommitted diff to revert]` and still counts as a
  fail. Confirmed failing the same way with this branch's diff stashed away.
- `tests/test-classify-md-inert.sh`: its "strip lib" construction resolves a
  relative path (`//telemetry/kit-log-dir.sh`) that does not exist from the
  temp file's location, independent of any content in `proof-ledger.sh`.
  Confirmed failing identically with this branch's diff stashed away.

## Reproducibility

Command: `bash tests/test-proof-tool-verification-path.sh`
Rerun twice, same result both times: `ALL PASS (1/1)`, exit 0.
