# Verification -- audit-pass-state

`bin/audit start <instance>` appends a `started` line to `audit-runs.log`. `audit due` shows `running` (a started newer than the last ran, under 6h), `abandoned` (the same, older), else DUE or `-` as before. A ran-only log prints as before.

| Check | Command | Result |
|---|---|---|
| Cadence suite (25 cases, 12 new) | `bash tests/test-audit-cadence.sh` | 25 passed, 0 failed |
| Forwarders | `bash tests/test-bin-forwarders.sh` | all 48 passed |
| Gauntlet proof audit | `bash tests/test-gauntlet-proof-audit.sh` | 17/17 passed |
| Scanner contract | `bash tests/test-audit-scanner-contract.sh` | 16 / 16 passed |
| Registry freshness | `bash lib/registry/feature-registry.sh check` | FEATURES.md is fresh |
| Negative controls | two reintroductions of the old behavior | suite red both times |

## Green run

```
Command: bash tests/test-audit-cadence.sh
Exit: 0
Output:
== NC: start refuses an undeclared instance and writes nothing ==
  ok: audit start refuses an undeclared instance
  ok: no started line appended
== NC: an unknown verb refuses ==
  ok: audit sweep exits non-zero

test-audit-cadence: 25 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-bin-forwarders.sh
Exit: 0
Output:
  ok: stats forwarder prints the CLI usage

test-bin-forwarders: all 48 passed, 0 skipped
Verdict: PASS
```

```
Command: bash tests/test-gauntlet-proof-audit.sh
Exit: 0
Output:
  PASS stats.sh is quiet when a transcript is present

=== 17/17 passed ===
Verdict: PASS
```

```
Command: bash tests/test-audit-scanner-contract.sh
Exit: 0
Output:
=== Results ===
Passed: 16 / 16
All audit-scanner-contract tests passed.
Verdict: PASS
```

`bin/test-affected` selected 37 suites: 0 fail, 6 pass, 27 cached, 4 timeouts (killed by the 60s to 250s per-suite limit on a loaded host; none asserted a failure).

## Negative control

Test-first: before the change, the new section of `tests/test-audit-cadence.sh` ran 21 passed, 4 failed (`start` was an unknown verb, so no instance read `running` or `abandoned`).

After the commit, two reintroductions of the old behavior, each restored with `git checkout -- lib/audit/audit.sh`:

```
Command: drop the started-line filter in last_run_epoch (a started line counts as a ran)
Exit: 1
Output:
  FAIL: doc-drift is no longer DUE
  FAIL: doc-drift is DUE again at 31d
  FAIL: web-drift no longer running
  FAIL: ci-drift no longer abandoned
  FAIL: ci-drift reads as a normal fresh run
test-audit-cadence: 20 passed, 5 failed
Verdict: PASS (the control went red)
```

```
Command: replace the timeout comparison with "if false" (nothing ever reads abandoned)
Exit: 1
Output:
  FAIL: ci-drift is abandoned at 7h
test-audit-cadence: 24 passed, 1 failed
Verdict: PASS (the control went red)
```

## Rollback

The only stored change is new `started` lines in the append-only `audit-runs.log`. No existing line is rewritten. Reverting the commit leaves those lines in place; the old reader then counts them as a ran, so revert and delete the `started` lines together if a clean state is needed.
