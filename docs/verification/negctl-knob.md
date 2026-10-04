# negctl-knob: proof of done

Change: new `[gate] negative_control` key (`always` default, `full`), read by `lib/gate/proof-ledger.sh` `check`. Test: case [38] in `tests/test-proof-negctl.sh`.

## NEGATIVE CONTROL

Reverted `lib/gate/proof-ledger.sh` to its pre-change copy (`git show HEAD~1:lib/gate/proof-ledger.sh`), ran the same test file once, then restored the file with `git checkout --`.

Command: `bash tests/test-proof-negctl.sh` (knob logic reverted)
Exit: 1
Result: RED as expected
Excerpt: `FAIL: full/small=1 always/small=1 full/hard-path=1 (want 0 1 1)` then `test-proof-negctl: 38 passed, 1 FAILED`

## Green run

Command: `bash tests/test-proof-negctl.sh`
Exit: 0
Tail: `ok: small diff: full passes (0), always blocks (1); hard-path diff under full blocks (1)` then `test-proof-negctl: all 39 passed`
Verdict: PASS
