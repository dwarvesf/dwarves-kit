# Verification -- repin-codex-hooks

`hooks/codex-hooks.json` carries a stale sha256 pin for `hooks/ship-gate.sh` after the ship-gate edit in #935. `lib/codex/repin.sh` refreshed the one pin; no hash was hand-edited.

## Green run
```
Command: bash tests/test-codex-hooks.sh
Exit: 0
Output:
94 passed, 0 failed
Verdict: PASS
```

## Negative control
```
Command: git checkout HEAD~1 -- hooks/codex-hooks.json && bash tests/test-codex-hooks.sh
Exit: 1
Output:
FAIL ship-gate.sh trust command pins its content hash: expected 1, got 0
FAIL repin check passes on a fresh fixture: expected 0, got 1
92 passed, 2 failed
Verdict: PASS (the suite goes RED on the stale pin, as the nightly did)
```
Broke the file by restoring the pre-repin `hooks/codex-hooks.json`, confirmed the two failures, then restored the repinned file with `git checkout HEAD -- hooks/codex-hooks.json` (clean tree after).

## Not proven
- Other suites were not run; only `hooks/codex-hooks.json` changed, and only `tests/test-codex-hooks.sh` reads it.
