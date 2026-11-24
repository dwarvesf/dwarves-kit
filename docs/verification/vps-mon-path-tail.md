# Verification -- vps-mon-path-tail

The session-report docstring, the test-vps-report comment, the devops-triage agent text and the deploy README no longer name the retired `tools/vps-mon` path. No code path changes: `session-report` is a Python script and only its module docstring moved.

| Claim | Evidence |
|---|---|
| The four live files name no `tools/vps-mon` path | Green run, the grep guard |
| `session-report` still parses and its signing test is unchanged | Green run, `test-vps-report.sh` |
| The agent definition still parses and passes the meta checks | Green run, `test-meta-review-verifiers.sh` |
| The guard depends on the edit | Negative control |

## Green run

```
Command: bash lib/session/observe/tests/test-vps-report.sh
Exit: 0
Output:
[10] host id: config key wins, else the local hostname
  ok: host_id from config
  ok: host_id defaults to the short hostname
[11] a failing token command reports itself and degrades, no crash
  ok: failing command named, exit 2
vps-report: all 14 passed
Verdict: PASS
```

```
Command: bash tests/test-meta-review-verifiers.sh
Exit: 0
Output:
=== Results ===
Passed: 210 / 210
All meta tests passed.
Verdict: PASS
```

Command: bash lib/session/observe/tests/test-vps-report.sh | tail -1; if grep -E 'tools/vps-mon($|[^-[:alnum:]_])' lib/session/observe/bin/session-report lib/session/observe/tests/test-vps-report.sh agents/devops-triage.md lib/sync/deploy/macos/README.md; then echo 'FAIL: old path still named'; exit 1; fi; echo 'live files clean'
Exit: 0 (green before mutation)
Output:
  vps-report: all 14 passed
  live files clean

Mutation: git show origin/master:lib/session/observe/bin/session-report >| lib/session/observe/bin/session-report
Changed: lib/session/observe/bin/session-report
Exit: 1 (under mutation, RED expected)
Output:
  vps-report: all 14 passed
  lib/session/observe/bin/session-report:  tools/vps-mon/worker/src/prober.ts) fires CRIT for ANY host whose last_seen
  lib/session/observe/bin/session-report:Signing contract (confirmed by reading tools/vps-mon/worker/src/hmac.ts +
  FAIL: old path still named

Restore: git checkout HEAD -- lib/session/observe/bin/session-report
Exit: 0 (green after restore)
Verdict: PASS

The mutation put the old `session-report` back. The guard named both stale lines and went red, and the restore turned it green again.

## Not proven

- Live behavior of `session-report`. Only comments and the docstring changed, so the heartbeat and snapshot paths run the same bytes as before.
- The records that still name the old path (`docs/specs`, `proof-of-done.md` files) and the two test fixtures that use it as sample data. They are left on purpose.
