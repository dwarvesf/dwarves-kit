# Verification -- board health digest

`board sweep` told an operator what changed, never whether the boards and sync legs were healthy. This change adds `lib/sync/sweep/board-health` (verbs `board health run|record`, sweep flag `--health`): per cluster, the active, parked, and stale rows of each hub, the open, stale, and archived-since-last-run cards of each kanban board, and sync health per spoke from records the sweep takes every tick. It posts through the existing `--poster` with `kind: "health"`.

## Gate table

| Claim | Evidence |
|---|---|
| `record` keeps spokes, rc, and error lines, and only keeps errors on a failure | green run, case record |
| hubs count active, parked, and stale rows from the origin copy, not the working tree | green run, case hubs; negative control 1 |
| the kanban reader yields open, stale, and archived-since-last-run | green run, case kanban |
| the cadence holds: due once, quiet after, `--force`, `--dry-run` and `--no-state` stamp nothing | green run, case cadence |
| a quiet cluster stays silent only while clean | green run, case quiet; negative control 2 |
| a failed post stays due, carries its redacted reason, clears on delivery | green run, case failed post |
| the sweep records every leg, runs the health leg only with `--health`, and a dry run leaves real state alone | green run, case sweep |
| the existing sweep, post, and digest suites did not regress | green run, existing suites |

## Green run

```
Command: bash tests/test-board-health.sh
Exit: 0
Output:
  ok   board health run --help

board-health: 75 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-board-sweep.sh      -> PASS=55 FAIL=0
Command: bash tests/test-board-sweep-post.sh -> PASS=32 FAIL=0
Command: bash tests/test-board-digest.sh     -> PASS=63 FAIL=0
```

`tests/test-board-sweep-mirror.sh` was not run in the authoring session: the branch-guard hook refuses any script that runs `git push`, and that suite pushes to a scratch remote. The change to the mirror leg is one record call after it.

## Negative controls

Each mutation was applied to `lib/sync/sweep/board-health` on a committed tree and reverted with `git checkout --`.

```
Control 1: stale cutoff inverted (`t < cutoff` became `t > cutoff`)
Command: bash tests/test-board-health.sh
Exit: 1
Output:
  FAIL one active row is stale (got '2', want '1')
  FAIL hubs line reads open and stale (got '⚠️ hubs: crew 3 open (2 stale) · 1 parked', want '⚠️ hubs: crew 3 open (1 stale) · 1 parked')
  FAIL a hub with no origin falls back to the working copy (got '[1,0]', want '[1,1]')
board-health: 72 passed, 3 failed
```

```
Control 2: quiet cluster ignores attention (`if not payload["attention"] and cluster in quiet` became `if cluster in quiet`)
Command: bash tests/test-board-health.sh
Exit: 1
Output:
  FAIL a failed sync needs attention, so it posts (got '0', want '1')
  FAIL flapping makes a quiet cluster post (got '0', want '1')
  FAIL carried digest error is attention too (got '', want '⚠️ last change digest failed to post: post failed last sweep')
board-health: 67 passed, 8 failed
```

## Reproduce

```
bash tests/test-board-health.sh
```
