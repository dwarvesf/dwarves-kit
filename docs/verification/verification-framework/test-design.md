# Test design -- verification-framework
Profile: feature
Proof class: behavioral

## Hypothesis / assumptions
- Hypothesis: the proof-of-done gate can validate the `docs/verification/<slug>/` directory
  layout SET-WISE, so a green run in one `runs/` file and a negative control in another
  `runs/` file under the same `<slug>/` dir together satisfy the gate, without breaking the
  per-file path for the flat `<slug>.md` / co-located `proof-of-done.md` shapes.
- Assumption: `_fresh_proof_files` already matches `docs/verification/.+\.md`, so files under
  `runs/` are picked up; only `check()` needed to move from per-file to set-wise.
- Falsifiable by: if the set-wise code were absent or wrong, the split layout would be
  rejected (BLOCK) even though it carries a complete proof.

## Test design
- AC1: a fixture with green + negative control in two separate `runs/` files under one
  `<slug>/` dir is ACCEPTED (exit 0) by the current lib.
- AC2 (negative control A): the same fixture with the negative-control run removed is BLOCKED
  (exit 1) , the gate is not trivially green.
- AC3 (negative control B): the pre-change lib (`HEAD:lib/proof-ledger.sh`) BLOCKS the split
  fixture (exit 1) , the set-wise code is load-bearing, not decorative.
- Expected negative control: revert the set-wise block in `check()` -> AC1 flips to BLOCK
  and `tests/test-proof-dir-layout.sh` exits non-zero.

## How to re-run
- `bash tests/test-proof-dir-layout.sh` (self-contained; builds throwaway git fixtures in
  /tmp, asserts AC1-AC3, exits 0 on ALL PASS).
