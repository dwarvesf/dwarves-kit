# Verification log -- generated proof-table (SPEC-132)

Proof of done = green (captured) + negative control (it goes RED when reverted) +
reproducible. Shape: `docs/verification/README.md`. These entries were produced by
running the real check locally, and by performing the negative control in a throwaway
`git worktree` (not the shared checkout). Re-run any `Command:` line to reproduce.

## 2026-07-04 03:10 PASS -- SPEC-132 [generator + tests]
- Command: `bash tests/test-proof-table-gen.sh`
- Exit: 0
- Output (excerpt):
  ```
  === Results ===
  Passed: 23 / 23
  proof-table-gen green.
  ```
- Verdict: PASS
- Note: green, captured from a real run against the fixture ledgers embedded in the
  test file (round-trip, both additive-tolerance grains, the not-canonical hard block,
  coverage-delta known/unknown lane, and the fully-empty-ledger case).

## 2026-07-04 03:11 NEGATIVE CONTROL -- SPEC-132 [generator + tests]
- Command: `git worktree add --detach /tmp/kri05-negctl HEAD && cd /tmp/kri05-negctl && git rm -q lib/proof-table-gen.sh lib/proof-table-gen.py && bash tests/test-proof-table-gen.sh` (throwaway worktree; removed after, shared checkout untouched)
- Exit: 1
- Output (excerpt):
  ```
  FAIL T7: coverage-delta uncovered degrades to lane-unknown text (missing ...)
  FAIL T8: generator exits 0 on a rid with no ledger file (expected '0', got '127')
  FAIL T8: empty-ledger table is still well-formed (no-crash marker row) (missing ...)
  FAIL T8: empty-ledger still names the (n/a) acceptance criterion (missing ...)

  === Results ===
  Passed: 3 / 23
  20 assertions failed.
  ```
- Verdict: RED-as-expected (removing `lib/proof-table-gen.{sh,py}` drops 20 of 23
  assertions -- exit 127 "command not found" on every invocation once the generator
  itself is gone; the 3 survivors are the fixture-setup lines that ran before the
  first `bash "$GEN"` call, not real passes of the generator's behavior).
- Note: the negative control. Proves the green above is not trivially green -- the
  proof-table generator's own tests fail hard once the generator is removed. After
  the run the worktree was removed and the shared checkout re-confirmed GREEN
  (`bash tests/test-proof-table-gen.sh` -> `Passed: 23 / 23`), so the negative
  control left no trace.

## Provenance
- Produced by: the SPEC-132 worker session, driving the flow end-to-end (real test
  run + a real throwaway-worktree revert), transcribing the captured output above.
  Not hand-authored numbers.
- Behavioral, not structural: the command/exit/excerpt come from real executions;
  the negative control genuinely removed the generator files in an isolated worktree.
- Reproduce: `bash tests/test-proof-table-gen.sh` (GREEN, 23/23); for the negative
  control, `git worktree add --detach <tmp> HEAD`, `git rm lib/proof-table-gen.{sh,py}`
  inside it, re-run the same command (RED), then `git worktree remove --force <tmp>`.
