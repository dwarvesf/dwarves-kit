# Verification -- sync-ntn-retry

The three Notion sources shared no code: each had its own `_run_ntn`, none retried, and one transient Notion error ended the whole sync run (taskboard-pull intake: a bare `Failed to execute public API request` on two ticks of one day, a 502 on another). They now call one runner, `lib/sync/sources/ntn.py`, which retries only calls that are safe to repeat.

## Which calls retry

| Call | Example | Retried on |
|---|---|---|
| read: GET, `datasources resolve`, POST to a `/query` path | `api v1/data_sources/<id>`, `api v1/data_sources/<id>/query -X POST`, `api v1/blocks/<id>/children` | bare error, 429, 500-504, timeout, dropped connection |
| write: every other POST, PATCH | `api v1/pages -X POST` (create), `api v1/pages/<id> -X PATCH`, `api v1/databases -X POST` | 429 only (refused before processing) |
| any call | 401, 403, 404, 400 | never, fails at once |

A bare error or a timeout on a write may follow a write that landed, so a retry would duplicate a created page. Backoff 5s then 20s, 2 retries, as in the foundation-ops status-return retry. A final failure raises `SystemExit("ntn <args[:3]> failed: <stderr>")`, the same message as before.

## Green run

```
Command: bash tests/test-sync.sh
Exit: 0
Output:
  326 passed in 0.87s
Verdict: PASS
```

271 of those were green before this change; 55 are new in `lib/sync/tests/test_ntn.py` (retry on a transient read, give up after 2 retries with the old message, 401 and 404 fail at once, no retry for a create/PATCH/database create on a bare error, 500, 502 or timeout, retry of a write on 429, call classification, all three sources share the one runner). The existing stdin test (`a read call never inherits stdin`) stays green against the shared runner.

```
Command: bin/test-affected --base origin/master --no-cache
Exit: 0
Output:
  PASS tests/test-sync.sh
  PASS tests/test-sync-dispatch.sh
  PASS tests/test-sync-cron-install.sh
  PASS tests/test-sync-cron-launcher.sh
  PASS tests/test-meta-docs-registry.sh   (after regenerating docs/reference/FEATURES.md, one count in the /kit:execute row)
  ... 9 more suites (registry, wrap, precedent, meta), all PASS
  test-affected: 14 selected, 14 pass, 0 cached, 0 fail, 0 timeout, 1 uncovered
Verdict: PASS
```

## Negative control

Run on the committed branch, each mutation to `lib/sync/sources/ntn.py` restored with `git checkout` and the suite green again afterwards:

```
Command: bash tests/test-sync.sh   (once per mutation)
Exit: 1 under every mutation (RED expected)
Output:
  retry off (ATTEMPTS = 1):                       23 failed, 303 passed
  every call classified as a read:                16 failed, 310 passed
  no call classified as a read:                   23 failed, 303 passed
  401 added to the transient statuses:             2 failed, 324 passed
  restored:                                       326 passed
Verdict: PASS (four controls RED, restored green)
```

The "every call is a read" control is the one that matters most: it turns a create into a retried call, and the no-retry-for-a-create tests go red.

## Not proven
- No live Notion call: the suite fakes `subprocess.run`. The 502 and bare-error spellings in the tests are copied from the real tick log lines.
- The deployed job runs a pinned kit commit; this change reaches `foundation.d.notion-taskboard-pull` only after its `KIT_REF` is bumped and the job redeployed.
- A write that times out is still not retried and still fails the run, by design.

## Rollback
Revert the commit: the three `_run_ntn` bodies come back unchanged. No state is written by the runner itself.
