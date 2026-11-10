# Verification -- nightly-suites-red

The 2026-11-10 nightly went red on `test-codex-hooks` and `test-mktemp-template-guard` at master 028b3e2. Both are deterministic, not load flakes. Both trace to #1124.

| Suite | Cause | Fix |
|---|---|---|
| test-codex-hooks | #1124 edited `hooks/ship-gate.sh` and left its sha256 pin in `hooks/codex-hooks.json` stale | `lib/codex/repin.sh` rewrote the one pin |
| test-mktemp-template-guard | #1124 added `tests/test-lane-effective.sh` with six `VAR=$(mktemp ...)` lines lacking `\|\| exit 1` (rule R3) | appended `\|\| exit 1` to each |

## Green run

```
Command: bash tests/test-mktemp-template-guard.sh; bash tests/test-codex-hooks.sh; bash tests/test-lane-effective.sh
Exit: 0
Output:
  === 11 passed, 0 failed ===
  94 passed, 0 failed
  PASS=64 FAIL=0
Verdict: PASS
```

## Negative control

Reverting both files to master (`git checkout 028b3e2 -- hooks/codex-hooks.json tests/test-lane-effective.sh`) turns the suites red again:

```
  FAIL violations:
  === 10 passed, 1 failed ===
  FAIL ship-gate.sh trust command pins its content hash: expected 1, got 0
  FAIL repin check passes on a fresh fixture: expected 0, got 1
  92 passed, 2 failed
```

Restoring the fix returns both to green.
