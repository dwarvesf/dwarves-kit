# Proof of done: writeback skips a blocked card instead of parking its git row

## What changed

`board writeback`'s reverse map sent a Hermes `blocked` card to the git state `parked`. The two
states do not mean the same thing. `blocked` says someone cannot proceed right now. `parked` says
deferred until a trigger, and a parked row leaves `board next` with no record of the blocker.
Writing one onto the other loses the reason and silently shrinks the cross-repo queue.

`lib/board/board-writeback.sh` now skips a card whose live status is `blocked`, in the diff loop,
after the snapshot comparison and before the reverse map, next to the create-state skip that
dwarves-kit #680 added. The row is counted and named in the skip output. No git row is written.

`_reverse_native` keeps returning `parked` for `blocked`: the forward map really does send `parked`
to `blocked`, so the declared inverse stays honest. The diff loop refuses to act on it before the
map is consulted.

## Gate table

| Claim | Evidence |
|---|---|
| a blocked card yields zero changes and one named skip | AC7, run table below |
| a card moved to a mapped column still yields one change | AC7, run table below |
| no row is ever written back to `parked` from a blocked card | AC7 assertion on the changeset NDJSON |
| the whole suite still holds | run table below |
| the guard is load-bearing | negative control below |
| the live dry-run drops the 5 blocked-card changes | live run below |

## Run table

```
Command: bash tests/test-board-writeback.sh
Exit: 0
TOTAL: 65   PASS: 64   FAIL: 0   SKIP: 1
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
run-all: 38 suites run, 0 skipped for missing tooling
Verdict: PASS
```

`docs/FEATURES.md` is a generated projection and was regenerated in the same commit
(`bash lib/registry/feature-registry.sh generate docs/FEATURES.md`), which is what
`test-meta.sh`'s freshness pin checks.

One pre-existing fixture moved: NC1 proved the row_hash rule using a card moved to `blocked`. The
blocked rule now skips earlier than the hash check, so that fixture would have proven nothing about
row_hash. NC1 now moves its card to `done`, a mapped column, and still exercises the hash path.

## Negative control

```
Command: bash lib/gate/negctl.sh <root> "bash tests/test-board-writeback.sh" "<remove the blocked guard>"
Exit: 0 (green before mutation)
Changed: lib/board/board-writeback.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/board/board-writeback.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The mutation deletes the four-line `if [ "$live_status" = "blocked" ]` guard, so the diff loop falls
through to the reverse map again.

## Live run

PENDING
