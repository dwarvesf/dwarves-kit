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
