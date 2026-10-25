# Proof of done: codex-hook-repin

`hooks/codex-hooks.json` pins the sha256 of each hook it runs. #1023 and #1031 edited `hooks/secrets-guard.sh` and `hooks/ship-gate.sh` without refreshing the pins, so `tests/test-codex-hooks.sh` went red on master. This branch reruns `lib/codex/repin.sh`, the committed verb for that rewrite.

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-codex-hooks.sh` | 0 | PASS (94 passed, 0 failed) |

```
Command: bash tests/test-codex-hooks.sh
Exit: 0
Output:
PASS secret attempt from AWS-shaped working directory is blocked
PASS working directory token fixture is absent from output and logs

94 passed, 0 failed
Verdict: PASS
```

## Negative control

Mutation: `git show origin/master:hooks/codex-hooks.json > hooks/codex-hooks.json` (the stale pins).

- With the stale pins: 91 passed, 3 failed (`secrets-guard.sh trust command pins its content hash`, `ship-gate.sh trust command pins its content hash`, `repin check passes on a fresh fixture`).
- Restore: `git checkout HEAD -- hooks/codex-hooks.json`, then green again.

Run by `lib/gate/negctl.sh`. Exit: 0 (green after restore).

## Rollback

Revert the squash commit. The pins go back to the stale hashes, and Codex then refuses to trust the two edited hooks, which is the state master was in before this change.

Verdict: PASS
