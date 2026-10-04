# Proof of done: registry Tests column reads lib tests and hook callers

The FEATURES.md Tests column scanned only `tests/*.sh`. A verb tested from `lib/*/tests/**`, or through a hook that calls its script, showed `-`. The scan now reads both, and `test-registry-verbs.sh` cases 8 and 9 pin it with negative controls (9b: a test of a hook that does not call the verb earns no credit).

Run on branch `feat/registry-test-scan` at `10b30e83`, after merging `origin/master` and regenerating FEATURES.md.

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-registry-verbs.sh` | 0 | PASS |
| `bash tests/test-registry-freshness-guard.sh` | 0 | PASS |
| `bash tests/test-config-registry.sh` | 0 | PASS |
| `bash lib/registry/feature-registry.sh check` | 0 | PASS |

Command: `bash tests/test-registry-verbs.sh`
Exit: 0
Output:
```
ok - 9a test naming a calling hook is credited
ok - 9b negative control: test of a non-calling hook is not credited
---
PASS=11 FAIL=0
```
Verdict: PASS

Command: `bash lib/registry/feature-registry.sh check`
Exit: 0
Output:
```
feature-registry: docs/FEATURES.md is fresh
```
Verdict: PASS
