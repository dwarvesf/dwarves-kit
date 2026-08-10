# Proof of done: `queue wait <slug>` verb (ID-470)

Change: add a `bin/queue wait <slug> [--timeout S]` verb that blocks until a
run reaches a terminal state, replacing the hand-rolled poll loops every live
`#auto` run re-wrote (re-making two bugs each time: `grep -c` newline
handling, window-gone-vs-verdict race). Read-only over the journal + mux +
sidecars.

Exit contract: 0 a terminal journal row landed (printed to stdout) or the slug
was already terminal; 1 the window died with no terminal row (residue to
stderr); 2 timeout.

## Green run

| Field | Value |
|---|---|
| Command | `bats tests/test-queue.bats` |
| Exit | 0 |
| Verdict | PASS (24/24; 19 pre-existing + 5 new) |

```
ok 20 W1 wait already-terminal -> exit 0 prints the row
ok 21 W2 wait new-row -> exit 0
ok 22 W3 wait window-died-no-verdict -> exit 1
ok 23 W4 wait timeout -> exit 2
ok 24 W5 wait bad-slug and missing-slug -> exit 64
```

The five cases drive each exit path through the fake-mux `.dead` seam (window
alive vs gone) and a preseeded/appended journal. W2 appends a terminal row
mid-wait from a background subshell to prove the live "new row lands" path,
not just a static read.

## Negative control (revert -> RED -> restore)

Removed the `wait) cmd_wait "$@" ;;` dispatch line (the verb falls through to
the usage default), re-ran the wait cases:

```
not ok 1 W1 wait already-terminal -> exit 0 prints the row
not ok 2 W2 wait new-row -> exit 0
not ok 3 W3 wait window-died-no-verdict -> exit 1
not ok 4 W4 wait timeout -> exit 2
```

Restored via `git checkout -- lib/queue/queue.sh` (from the feature commit):
all 5 W tests green again.

## Static checks

- `shellcheck -S warning lib/queue/queue.sh bin/queue`: clean (exit 0).
- Full `test-queue.bats`: 24/24, no regression in the 19 pre-existing cases.
