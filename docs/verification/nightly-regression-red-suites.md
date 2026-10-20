# Proof of done: the nightly regression's red suites

## What changed

The Mac Mini job `mini.kit-nightly-regression` runs `tests/run-all.sh --all` on a fresh clone of master each night. It went red on 10-17, 10-19 and 10-20. Each failing suite was rerun on current master (4c3fdc07) and classified.

| Suite | Night | Class | Cause | Status |
|---|---|---|---|---|
| `test-codex-hooks` | 10-20 | real bug | #1002 edited `hooks/ship-gate.sh` without a repin, so the Codex trust command in `hooks/codex-hooks.json` pinned a stale sha256. Both failing rows share that cause. Red on master since #1002 | fixed here: `bash lib/codex/repin.sh` |
| `test-kit-foldin-hooks` row 4i | 10-19 | flaky under load | The test slept 0.3s once, then looked for the detached extractor. The detached child runs python3 and jq before it execs the extractor, which takes longer than 0.3s on a loaded host | fixed here: poll up to 5s |
| `test-mktemp-template-guard` | 10-17, 10-19 | real bug | New code landed with unguarded `mktemp` calls | already fixed on master (#983 for 10-17, #1005 for 10-19). It recurs: the guard is right, new code keeps landing without the `|| exit` form |
| `test-outcome-emit-sweep` | 10-19 | real bug | Orphan `record ... ran` sites in `commands/*.md` at 83083b1 | already fixed on master (in 83083b1..4c3fdc07) |
| `test-gate-vocab-recording` | 10-19 | real bug | The bug-lane fixture recorded no review gate once gates default on | already fixed on master (#1012) |
| `test-proof-negctl`, `test-ship-gate-impl-notes`, `test-wrap-merge` | 10-19 | host load | Per-suite ceiling hits, no assertion failed. That night the job waited about 40 min on the host test lock behind an interactive `run-all --changed`, then ran on a host near load 20 | no change: each passes well under its ceiling on a normal host |

## Gate table

| Claim | Evidence |
|---|---|
| The Codex trust pins are fresh again | `test-codex-hooks` green run below |
| The repin is load-bearing | Codex negative control below |
| Row 4i survives a slow detached spawn | 4i negative control below |
| The whole suite is green in the nightly job's environment | full run below |

## Green runs

```
Command: bash tests/test-codex-hooks.sh
Exit: 0
Output:
94 passed, 0 failed
Verdict: PASS
```

Full run in the environment the launcher builds: credential-shaped variables dropped, provider tokens pinned to placeholders, an empty `KIT_CONFIG_OPERATOR`, and `KIT_RUN_ALL=1`.

```
Command: env -u <credential-shaped vars> KIT_CONFIG_OPERATOR=<empty toml> KIT_RUN_ALL=1 <placeholder tokens> bash tests/run-all.sh --all --time
Exit: 0
Output:
test-codex-hooks                               ok (8s)
test-gate-vocab-recording                      ok (5s)
test-kit-foldin-hooks                          ok (34s)
test-mktemp-template-guard                     ok (17s)
test-outcome-emit-sweep                        ok (4s)
test-proof-negctl                              ok (12s)
test-ship-gate-impl-notes                      ok (42s)
test-wrap-merge                                ok (94s)
run-all: all 254 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative controls

Codex pin: restore the stale `hooks/codex-hooks.json` from origin/master, rerun, restore HEAD.

```
Command: git checkout origin/master -- hooks/codex-hooks.json && bash tests/test-codex-hooks.sh; git checkout HEAD -- hooks/codex-hooks.json
Exit: 1
Output:
FAIL ship-gate.sh trust command pins its content hash: expected 1, got 0
FAIL repin check passes on a fresh fixture: expected 0, got 1
92 passed, 2 failed
Verdict: FAIL as intended, the same two rows the 10-20 night reported
```

Row 4i: a `python3` shim that sleeps 1s first on PATH makes the detached child slow to reach the extractor, the shape host load produces. The fixed test passes. The origin/master test fails with the 10-19 message.

```
Command: PATH=<slow python3 shim>:$PATH bash tests/test-kit-foldin-hooks.sh (HEAD, then origin/master's copy of the test)
Exit: 0, then 1
Output:
== fixed test (HEAD 14f5ead2), slow spawn
  PASS row 4i: detached child (pgid=8506) is in a DIFFERENT process group than the invoker (pgid=82407) -- would survive the invoker's group being torn down
  PASS row 4i: ledger entry still lands after the pgid check
== old test (origin/master), slow spawn
  FAIL row 4i: could not find the detached extractor process to inspect (already finished or never spawned)
  PASS row 4i: ledger entry still lands after the pgid check
== tree after restore: 0 dirty paths
Verdict: PASS for the fix, FAIL as intended for the old test
```

## Rollback

Revert the two commits. The repin is data only, and the 4i change is test-only. Neither touches a runtime path.
