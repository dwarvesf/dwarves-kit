# Verification -- wrap merge --pr N

`bin/wrap merge --apply --pr N <repo>` targets exactly one own, open PR: it marks a
draft ready first when named, then runs the existing eligibility, union re-merge and
tree-verification path unchanged. Without `--pr`, `merge` behaves exactly as before.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS (601/601 assertions, including the 20 new `merge --pr` cases: draft
  ready-then-merge pinned to the full head sha, plain `merge` still skips the same
  draft, a PR not authored by the operator refuses and writes nothing, dry run marks
  nothing ready)
```
```
Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: PASS (9/9 suites: test-bin-forwarders, test-boundary-lint,
  test-config-registry, test-gitattributes-union, test-kit-contract, test-meta,
  test-no-personal-paths, test-no-scattered-ids, test-wrap)
```

## NEGATIVE CONTROL
```
Command: (in lib/wrap/wrap.sh, commented out the draft-ready block inside the
  --pr branch of cmd_merge, replacing it with `: NEGATIVE-CONTROL-DISABLED`)
  bash tests/test-wrap.sh
Exit: 1
Verdict: FAIL as expected -- 7 of the new `merge --pr` assertions failed
  (marks the draft ready / re-gates after readying / reports the merge, tree
  verified / called gh pr ready / calls ready before merge / pinned the full
  head sha / dry run notes the draft), 594/601 passed
```
Restored the block verbatim (`git diff` against the commit showed no diff).

## Restore run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: PASS (601/601, same as the Green run above; confirms the restore was exact)
```

## Not proven
- No live GitHub call: `gh` is a stub throughout, driven by env vars recorded per
  invocation (`GH_STUB_CALLS`), the same harness the rest of `test-wrap.sh` uses.
- The dependents-open gate (another open PR whose base is this PR's branch) is not
  re-checked once `--pr` narrows `numbers` to a single PR; unchanged from the plain
  verb's existing single-PR-per-call contract, just not exercised under `--pr` here.
