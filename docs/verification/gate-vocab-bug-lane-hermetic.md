# Verification -- gate-vocab-bug-lane-hermetic

tests/test-gate-vocab-recording.sh AC9 assumed the operator overlay's relaxed bug lane (review optional). The kit's own bug lane requires build, review and debug, so a hermetic run (the nightly pins an empty operator config) failed AC9 on master.

## Green run
```
Command: KIT_CONFIG_OPERATOR=<empty toml> bash tests/test-gate-vocab-recording.sh
Exit: 0
Output:
  PASS the check names 'debug' as the missing gate
  PASS check bug passes once debug ran is recorded (exit 0)
=== Summary: 31/31 passed ===
Verdict: PASS
```
The same suite also passes with the default operator overlay (exit 0).

## Negative control
```
Command: restore the pre-fix test (git show HEAD~1:tests/test-gate-vocab-recording.sh), then KIT_CONFIG_OPERATOR=<empty toml> bash tests/test-gate-vocab-recording.sh
Exit: 1
Output:
  FAIL check bug passes once debug ran is recorded (exit 0) -- MISSING-GATE: review (required for lane 'bug'; no ran/override entry in the ledger)
=== Summary: 30/31 passed ===
Verdict: RED as expected
```
The fixed test was restored after the run (working tree clean against the commit).

## Not proven
- The full suite (`run-all.sh --all`) was not run; only this suite, under both operator configs.
