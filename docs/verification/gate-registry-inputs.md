# Verification -- gate-registry-inputs

The pre-push registry-freshness arm in `hooks/ship-gate.sh` now takes its trigger from `feature-registry.sh input-pattern` instead of a hardcoded regex. The old regex omitted `lib/**/tests/*`, `tests/*.sh` helpers and `# kit-verb:` lib scripts, all of which the generator reads, so a recall test edit pushed with a stale `docs/reference/FEATURES.md`.

| Trigger | Before | After |
|---|---|---|
| `tests/test-*.sh` | yes | yes |
| `tests/*.sh` other names | no | yes |
| `lib/**/tests/*.sh`, `*.py` | no | yes |
| other `lib/**/*.sh`, `*.py` (kit-verb markers) | no | yes |
| commands, agents, skills, hooks, `hooks.json`, `settings.json`, specs | yes | yes |

## Green run
```
Command: bash tests/test-registry-freshness-guard.sh
Exit: 0
Output:
  ok - lib/**/tests-only diff that moves a Tests column -> blocked (exit 2)
  ok - tests/*.sh helper that moves a Tests column -> blocked (exit 2)
  ok - input-pattern matches a lib test and rejects a non-input
  PASS=19 FAIL=0
Verdict: green. Also green: test-meta-docs-registry, test-registry-verbs, test-registry-one-pass, test-ship-gate-fail-closed, test-ship-gate-default-push, test-ship-gate-refs-block (all exit 0).
```

## Negative control
```
Command: git checkout 1e5bd895 -- hooks/ship-gate.sh && bash tests/test-registry-freshness-guard.sh
Exit: 1
Output:
  NOT ok - a lib/**/tests-only stale push should block (got 0)
  NOT ok - a tests/ helper stale push should block (got 0)
  PASS=17 FAIL=2
Verdict: red with the old gate; the new gate was restored with `git checkout HEAD -- hooks/ship-gate.sh`.
```

## Not proven
- The arm now also runs the ~4s regen on any non-generator lib script edit, because the marker needs a content read to detect. That is cost, not a miss.
- An older kit install without `input-pattern` skips the arm with the existing advisory note; not exercised beyond the shared too-old-install path (case 13).
