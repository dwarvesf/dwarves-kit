# Proof of done: visible LLM egress, waived gates, per-session marker

Verdict: PASS

Lane: normal. Resolves three ranked risks in `docs/SYSTEM-DESIGN.md`: "LLM egress fails silently", "Two meanings of debt", "Machine-global session marker". Choices the brief left open are in `docs/implementation-notes/egress-visible.md`.

## What was proven

| Claim | Evidence |
|---|---|
| A failing or empty model command in harvest, backlog-stage, skill-review, session-audit and reflect propose appends one `ts \| source \| reason` line to `egress-failures.log` and the caller still exits 0 | `tests/test-egress-visible.sh` (31 cases); negative control below |
| A healthy extractor that prints a valid `[]` adds no line | same suite |
| `egress-fail.sh summary` prints one line per window, counts per source, ignores entries older than 7 days, and prints nothing when the ledger is empty | same suite |
| `/kit:start` calls the summary | same suite (wiring case) |
| The stats metric is `waived_gates` (key, threshold, title, metric string); `| DEBT |` lines stay understanding debt | `lib/stats/tests/test-feedback.sh` 47/47; negative control below |
| Two sessions get two markers; a marker over a day old is swept; a live marker survives | `tests/test-egress-visible.sh` slop cases; negative control below |

## Green runs

Command: `bash tests/test-egress-visible.sh`
Exit: 0
Output: `egress-visible: 31 passed, 0 failed`

Command: the suites this change touches, one at a time (host load average above 100 from other sessions' runs)
Exit: 0 for each
Output:

```
tests/test-reflect-propose.sh            57 run, 57 passed, 0 failed
tests/test-hooks.sh                      Passed: 813 / 813 (includes the slop-cleaner cases)
tests/test-harvest-parity.sh             harvest parity: 171 passed, 0 failed
tests/test-backlog-stage-parity.sh       backlog-stage parity: 204 passed, 0 failed
tests/test-staging-one-writer.sh         38 run, 38 passed, 0 failed
tests/test-intake-sweep.sh               intake-sweep: 31 passed, 0 failed
tests/test-bin-forwarders.sh             all 48 passed, 0 skipped
tests/test-kit-contract.sh               kit-contract: 25 passed, 0 failed
tests/test-config-registry.sh            60/60 passed
tests/test-docs-wiring.sh                25/25 passed
tests/test-reserved-config-guard.sh      9 run, 9 passed, 0 failed
tests/test-meta-docs-registry.sh         Passed: 120 / 120
lib/session/audit/tests/smoke.sh         smoke: 24 passed, 0 failed
lib/skill-curator/tests (6 suites)       async 2, hook-async 4, reentrancy 3, reviewer 10, signal-gate 12, staging-gate 5: all passed
lib/stats/tests/test-feedback.sh         47 passed, 0 failed
lib/stats/tests/test-anomalies-advisor   36 passed, 0 failed
lib/stats/tests/test-render-skill.sh     30 passed, 0 failed
lib/stats/tests/test-docs-wiring.sh      PASS=18 FAIL=0
```

`test-meta-docs-registry` first failed with `docs/FEATURES.md is fresh` because the generated file counts the new suite; after `feature-registry.sh check --fix docs/FEATURES.md` (its own commit) it is 120/120. The first harvest parity run failed 4 cases for a real reason: the hook now wrote `egress-failures.log` inside the case's fake HOME, which the goldens list as a stray file. The parity harness now passes a caller-exported `KIT_LEDGER_DIR` through `env -i`, and both parity wrappers point it at a temp dir.

## Negative controls

Each mutation was committed-clean first, run RED, restored, and shown green again (`lib/gate/negctl.sh`).

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-egress-visible.sh" "sed -i '' 's/egress_fail harvest \"extractor exit \$rc\"/:/' hooks/harvest.sh"`
Exit: 1 (under mutation, RED expected)
Output:

```
Changed: hooks/harvest.sh
  egress-visible: 30 passed, 1 failed
Restore: git checkout HEAD -- hooks/harvest.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Command: the slop-cleaner marker keyed by session id replaced with the old shared path (`MARKER="$MARKER_PREFIX"`), same suite
Exit: 1 (under mutation, RED expected)
Output:

```
Changed: hooks/slop-cleaner.sh
    FAIL  session A gets its own marker
    FAIL  session B gets a separate marker
    FAIL  session B's start left session A's marker alone
    FAIL  the live session's marker survives the sweep
  egress-visible: 27 passed, 4 failed
Restore: git checkout HEAD -- hooks/slop-cleaner.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Command: the detector key reverted (`key="waived_gates"` to `key="debt"`), `bash lib/stats/tests/test-feedback.sh`
Exit: 1 (under mutation, RED expected)
Output:

```
Changed: lib/stats/src/stats/anomalies.py
  == 45 passed, 2 failed ==
Restore: git checkout HEAD -- lib/stats/src/stats/anomalies.py
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- The real `claude -p` binary was not driven; every model call is a stub command, as in the existing suites.
- `/kit:start` is a prompt: the suite proves the command text names the summary and the summary prints the line, not that a model renders it.
- The skill-review hook entry (`hooks/skill-review.sh`) is unchanged; the failure is ledgered one level down in `reviewer-run.sh`, the file that calls the model.

## Rollback

`git revert` the commits on `fix/egress-visible`. No data migration: `egress-failures.log` is a new append-only stream nothing else reads, and the `gates_ovr` column keeps its name.
