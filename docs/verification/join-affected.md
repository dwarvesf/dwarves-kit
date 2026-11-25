# Verification: join-affected

The tiered mega join (`[mega] verify = "tiered"`) no longer runs the base tree: `[test] join_cmd` runs once on the merged tree with `KIT_JOIN_BASE` set to the base commit, so it runs the affected selection of the union of heads, and a red run is judged against the committed known-failures list. The serial level join passes the base pinned before the first dispatch as `KIT_JOIN_BASE`.

## Green run
```
Command: bash tests/test-orchestrate-tiered.sh; bash tests/test-orchestrate-serial-join.sh; bash tests/test-known-failures.sh
Exit: 0 for each
Output:
PASS C6: the only run is the merged tree; no base tree run
PASS C6: join_cmd gets KIT_JOIN_BASE = the base commit, so it selects the tests the union of heads touches
All tiered orchestrate tests passed.
All serial join tests passed.
All known-failures tests passed.
Verdict: PASS
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-orchestrate-tiered.sh" "sed -i '' 's/ KIT_JOIN_BASE=\"\$jbase\"//' lib/queue/orchestrate.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
Exit: 1 (under mutation, RED expected)
Verdict: PASS
```
Dropping `KIT_JOIN_BASE` from the join command turns the joinbase case red; negctl restored the file.

## Not proven
- The executed count floor against the base run is gone with the base run; a wave that deletes tests is caught only by the known-failures classify, not by a count drop.
- No live tiered mega run on a real repo.
