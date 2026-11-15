# Verification -- redact-keep-inode

`_redact_secrets_file` rewrites a stream file in place (same inode) and skips a path a newer run owns.

## Green run
```
Command: bash tests/test-orchestrate-redact-inode.sh
Exit: 0
Output:
PASS (a) inode unchanged across redaction
PASS (a) secret redacted in place
PASS (a) the live writer's appends all reached the path (11 ticks)
PASS (b1) re-truncated path left alone by the old run
PASS (b1) one-line stderr note emitted
PASS (b1) the current owner still redacts
PASS (b2) replaced inode skipped with a note
PASS (b3) unclaimed call still redacts
PASS (c) token, slack, AWS and bearer shapes redacted; plain line kept
PASS clean file left byte-identical
=== 0 failure(s) ===
Verdict: PASS. tests/test-orchestrate-hardening.sh (end-to-end redaction through `orchestrate.sh run`) is still 13/13, and `bash tests/run-all.sh --changed origin/master` passed all 38 suites.
```

## Negative control
```
Command: KIT_REDACT_OLD_MV=1 bash tests/test-orchestrate-redact-inode.sh
Exit: 1
Output:
FAIL (a) inode changed 744386888 -> 744386945 (a live writer is now detached)
FAIL (b1) old run redacted a path the new run owns
FAIL (b2) a replaced path was redacted by a non-owner
=== 5 failure(s) ===
Verdict: red as required. The env switch swaps in the pre-fix `mv -f` body inside the test only; production code was not modified, so nothing to restore.
```

## Not proven
- A real orchestrator restart mid-wave; the old-run race is modelled with two claims on one path.
- The check-then-write window in `_redact_secrets_file` is not atomic; a new run truncating inside that window is still possible.
- A kill mid-way through the in-place `cat` (only reachable when the content changed) can leave a partial file.
