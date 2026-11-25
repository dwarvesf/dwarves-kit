# Verification -- freshness-test-hooks

`tests/test-registry-freshness-guard.sh` builds fixture repos and commits a `hooks/codex-hooks.json` that holds a 64-hex SHA-256 pin. On a host whose operator sets a global `core.hooksPath` with a secret-scanning pre-commit, that hook rejected the fixture commit and two cases failed. The fixture now pins `core.hooksPath` to its own `.git/hooks`, the same way `tests/test-wrap-ship.sh` does.

| Check | Result |
|---|---|
| Suite with the fix, on a host with a global secret-scanning pre-commit | 26 passed, 0 failed |
| Same suite without the fix, same host (negative control) | 24 passed, 2 failed |

## Green run

```
Command: bash tests/test-registry-freshness-guard.sh
Exit: 0
Output:
  ok - committed fresh pin + uncommitted hook edit -> not blocked (exit 0)
  ---
  PASS=26 FAIL=0
Verdict: PASS
```

## Negative control

The same command on the tree before the fix (the pin line absent), on the same host with `git config --global core.hooksPath` set to a hooks directory whose pre-commit blocks secret-shaped content:

```
Command: bash tests/test-registry-freshness-guard.sh
Exit: 1 (RED expected)
Output:
  git pre-commit: secret-shaped content staged, commit blocked:
    hooks/codex-hooks.json: Hex private key (64 hex chars ...): e742... (64 chars)
  ok - committed fresh pin + uncommitted hook edit -> not blocked (exit 0)
  ---
  PASS=24 FAIL=2
Verdict: RED as expected
```

Restoring the pin line returns the suite to 26 passed.

## Reproduce

```
git config --global --get core.hooksPath      # a non-empty value reproduces the failure before the fix
bash tests/test-registry-freshness-guard.sh
```

On a host with no global `core.hooksPath` the suite passed before and passes after; the change only removes the dependence on operator git config.
