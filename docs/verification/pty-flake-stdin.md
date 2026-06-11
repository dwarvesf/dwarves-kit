# Proof of done: hooks-suite PTY flake fix (ID-081)

## Claim

The "colors: PTY progress emits escape bytes" test passes deterministically in
every harness (TTY, socket-stdin agent runner, CI), and still fails when the
color gate is genuinely broken. Metric: suite pass count; threshold: 6/6
consecutive green + NC flips exactly 1 RED.

## Root cause (diagnosed, not guessed)

Instrumentation inside the failing suite run captured `script: tcgetattr/ioctl:
Operation not supported on socket`. BSD `script(1)` copies terminal attributes
from its OWN stdin; a socket stdin (agent harness) fails that ioctl and script
exits 1 before running the child, producing an empty capture. Two earlier
hypotheses (load race; stdout drain) were disproved: isolated probes were
stable 12 escapes x25, and a bounded-retry build still failed 4/4 and then 5/5.

## Fix

`tests/test-hooks.sh`: feed `script` an explicit `</dev/null` stdin (handled
gracefully) on both the BSD and util-linux branches, and read the typescript
FILE (flushed at exit) instead of capturing script's stdout.

## Confirmation runs

| Run | Command | Result |
|---|---|---|
| reproduce | suite under socket-stdin harness, typescript-file build pre-stdin-fix | Failed: 1, same test, 5/5 deterministic |
| green | `bash tests/test-hooks.sh` x6 consecutive post-fix | 426/426 every run |
| negative control | `[ -t 1 ] && [ -z NO_COLOR ]` gate in lib/gate-ledger.sh forced false | exactly 1 RED (this test), restored, 426/426 |

Verdict: PASS.

## Reproduce

```
bash tests/test-hooks.sh          # the test: grep -n 'ID-081' tests/test-hooks.sh
docs/research/2026-06-11-id081-flake-capture.txt   # sighting capture (pre-fix)
```
