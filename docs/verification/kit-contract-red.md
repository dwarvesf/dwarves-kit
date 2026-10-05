# Proof of done: kit-contract-red

`tests/test-kit-contract.sh` failed 2 of 25 on the Mini's master checkout:

- C6: `lib/gate/ship-rules.sh` (added by #931) hardcoded the pre-SPEC-097 log root in its audit logger. The helper no longer names a log path: the hook, which owns `ship-gate.log`, passes its own dir in `SHIP_RULES_LOG_DIR`, so every line still lands in the one live `ship-gate.log`. The mega gate never sets it and logs nothing, as before.
- C2: the check walked the filesystem and flagged `lib/prose-rag/bin/prose-rag-rs`, a gitignored local Rust build. CI never sees it. The loop now skips a gitignored executable.

## Recorded run

Command: `bash tests/test-kit-contract.sh` with a planted gitignored executable `lib/prose-rag/bin/probe-rs`
Exit: 0
Verdict: PASS, 25/25.

Command: `bash tests/test-hooks.sh; bash tests/test-mega-gate-parity.sh; bash tests/test-ship-gate-fail-closed.sh; bash tests/test-ship-gate-coverage-map.sh; bash tests/test-config-registry.sh`
Exit: 0
Verdict: PASS on each; hook audit lines unchanged.

## Recorded run (negative control)

Command: pre-fix `tests/test-kit-contract.sh` and `lib/gate/ship-rules.sh` restored from git, planted artifact present, `bash tests/test-kit-contract.sh`
Exit: 1
Verdict: NEGATIVE CONTROL red as expected: C2 names `lib/prose-rag/bin/probe-rs`, C6 names `lib/gate/ship-rules.sh`.

Command: fixed files copied back with `command cp -f`, `bash tests/test-kit-contract.sh`
Exit: 0
Verdict: PASS, 25/25, tree clean.
