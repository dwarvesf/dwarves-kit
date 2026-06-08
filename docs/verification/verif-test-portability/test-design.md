# Test design -- verif-test-portability
Profile: feature
Proof class: behavioral

## Hypothesis / assumptions
- Hypothesis: a test's negative control must not read the "pre-change" lib from git history.
  `test-proof-dir-layout.sh` and `test-classify-md-inert.sh` did exactly that (merge-base /
  HEAD `:lib/proof-ledger.sh`), so they passed pre-merge but went RED once the feature merged
  to master (master then HAS the change, so there is no pre-change version to fetch).
- Fix: construct the pre-change lib from the CURRENT one by stripping the feature block (awk),
  so the negative control holds regardless of git state.

## Test design
- AC1: both tests pass on master after the fix (the strip-based negative control resolves).
- AC2: the strip genuinely reproduces the bug , the set-wise-stripped lib BLOCKS the split
  layout, and the inert-FIRST-stripped lib classifies a markdown-only "migrate" diff as stateful.
- Negative control: the pre-fix tests (git-history negative control) exit non-zero on master.

## How to re-run
- `bash tests/test-proof-dir-layout.sh && bash tests/test-classify-md-inert.sh` (both exit 0).
