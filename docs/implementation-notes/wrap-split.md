# Implementation notes: wrap split

Delta from `docs/specs/SPEC-374-wrap-split.md` only: decisions the spec did not
make, deviations, and tradeoffs. The spec is the contract; this log is what the
build itself learned.

## Step 0: spec fold

Folded the round-2 lead decisions and flipped `Status:` to VALIDATED:

- `bin/test-affected` maps `lib/wrap/wrap.sh` and `lib/wrap/wrap-common.sh` to
  every `tests/test-wrap-*.sh` suite, never the runner. `tests/run-all.sh` skips
  a `# runner:` file, so a runner mapping would make `run-all --changed` run no
  wrap suite at all, and the runner takes about 7m40s, over test-affected's 300s
  timeout. Folded into the Picture, the Design paragraph, T3's Done-when, and
  the Verification comment.
- Picture now says the suites cover 11 of 12 modules plus report-lint and cli:
  there is no `test-wrap-common.sh`.
- The `chk_no` red proof in T2 now breaks the code under test so it prints the
  forbidden string; a `chk_no` fails only when the string appears, so breaking
  seed state alone cannot turn it red.
- Verification order: the T1 commit lands before any `git checkout --` restore
  in the cache sequence or the negative control, because a restore fails on an
  untracked module file. The negative control asserts the named rebase assert
  goes red; the runner's exit code does not discriminate since the baseline
  already carries 2 FAILs.
- The Sourcing paragraph now states the reason plainly: the fixed order is a
  determinism pick, safe because module top-levels carry no inter-assignment
  dependency.

## T1: code split

(below as the work runs)
