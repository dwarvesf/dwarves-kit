# Verification -- codex-repin-ship-gate

Repin hooks/codex-hooks.json after #1074 edited hooks/ship-gate.sh without rewriting its content-hash pin.

## Green run
```
Command: bash tests/test-codex-hooks.sh
Exit: 0
Output:
  PASS secret attempt from AWS-shaped working directory is blocked
  PASS working directory token fixture is absent from output and logs
  
  94 passed, 0 failed
Verdict: PASS (before the fix on origin/master: 92 passed, 2 failed)
```

```
Command: bash lib/codex/repin.sh check
Exit: 0
Output:
  repin: all pins fresh in hooks/codex-hooks.json
Verdict: PASS
```

## Negative control
```
## Negative control (negctl)
Command: bash tests/test-codex-hooks.sh
Exit: 0 (green before mutation)
Output:
  PASS anti-rationalization.sh fails closed without jq
  PASS anti-rationalization.sh names the missing dependency
  PASS token-shaped secret attempt is blocked
  PASS token fixture is absent from hook output and logs
  PASS AWS-shaped secret attempt is blocked
  PASS AWS fixture is absent from hook output and logs
  PASS secret attempt from AWS-shaped working directory is blocked
  PASS working directory token fixture is absent from output and logs

  94 passed, 0 failed

Mutation: git show 56d4fa6e~1:hooks/codex-hooks.json > hooks/codex-hooks.json; printf '\n# stale\n' >> hooks/ship-gate.sh
Changed: hooks/codex-hooks.json, hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  PASS anti-rationalization.sh fails closed without jq
  PASS anti-rationalization.sh names the missing dependency
  PASS token-shaped secret attempt is blocked
  PASS token fixture is absent from hook output and logs
  PASS AWS-shaped secret attempt is blocked
  PASS AWS fixture is absent from hook output and logs
  PASS secret attempt from AWS-shaped working directory is blocked
  PASS working directory token fixture is absent from output and logs

  92 passed, 2 failed

Restore: git checkout HEAD -- hooks/codex-hooks.json hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Mutation = prior pin plus an edited hooks/ship-gate.sh; both files restored by negctl.sh (tree clean).

## Not proven
- test-proof-negctl [39] failed once in the nightly and passed on 10 reruns here (4 serial, 6 under load); no code change, cause not isolated.

## Guard: ship-gate blocks a stale codex pin

The class fix for #1069, #1071 and #1074: a push that edits hooks/*.sh or hooks/codex-hooks.json runs `lib/codex/repin.sh check` against the pushed tree (hooks/ship-gate.sh:393, "Codex trust-pin gate").

### Green run
```
Command: bash tests/test-registry-freshness-guard.sh
Exit: 0
Output:
  ok - hook edited without a repin -> blocked, names the stale pin (exit 2)
  ok - hook edited and repinned -> pass (exit 0)
  PASS=22 FAIL=0
Verdict: PASS
```

Also green after the edit (repinned, `repin.sh check` exit 0): test-codex-hooks 94 passed, 0 failed; test-hooks, test-gate-outcome (25/25), test-gate-opt-in, test-gate-opt-out, and the test-ship-gate-* suites (fail-closed, default-push, refs-block, profiles, identities, command-words).

### Negative control
```
Command: bash tests/test-registry-freshness-guard.sh
Mutation: disable the guard (the `[ -f "$GATE_PIN" ]` precondition made false) in hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - a stale pin should block with the stale pin line (got 0)
  PASS=21 FAIL=1
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The control ran after the guard commit; the tree was clean afterwards.

## Review fixes: guard judges the pushed commit

hooks/ship-gate.sh:396-420 now (1) requires the lib/codex/repin.sh kit marker, (2) archives hooks/ from the pushed commit and checks that copy, (3) blocks only when repin names a stale pin (a pin-less manifest is an advisory), (4) reads the diff with `grep < <(git ...)`. Cases 20-23 in tests/test-registry-freshness-guard.sh pin it.

### Green run
```
Command: bash tests/test-registry-freshness-guard.sh
Exit: 0
Output:
  ok - hook edited without a repin -> blocked, names the stale pin (exit 2)
  ok - hook edited and repinned -> pass (exit 0)
  ok - non-kit repo with a pin-less manifest -> not blocked (exit 0)
  ok - pin-less manifest (repin cannot judge) -> advisory line, not blocked (exit 0)
  ok - committed stale pin + uncommitted repin -> still blocked (exit 2)
  ok - committed fresh pin + uncommitted hook edit -> not blocked (exit 0)
  PASS=26 FAIL=0
Verdict: PASS
```

Also green after the edit and repin (`repin.sh check` exit 0): test-codex-hooks 94 passed, 0 failed; test-ship-gate-fail-closed 12/12, default-push 37/37, refs-block 11/11, profiles (3 profiles x allow+block), identities 11/11, command-words 44/44; test-gate-opt-in and test-gate-opt-out all pass.

### Negative control (fix 2)
```
Command: bash tests/test-registry-freshness-guard.sh
Mutation: check the working tree again (`check "$PINTMP"` -> `check "$ROOT"`) in hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - an uncommitted repin must not satisfy the gate
  PASS=24 FAIL=2
  NOT ok - an uncommitted edit must not fail a fresh committed pin (got 2)
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The control ran after the fix commit; the tree was clean afterwards.

### Not proven
- `lib/codex/repin.sh` exits 1 with no output (not 2) on a manifest with no pins, because `set -e` fires inside the PINNED pipeline. The gate therefore keys the block on the "stale pin:" line; repin.sh itself is untouched.
