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
