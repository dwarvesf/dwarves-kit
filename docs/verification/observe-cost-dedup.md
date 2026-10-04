# Verification -- observe-cost-dedup

`session-observe` cost and burn dedup one API message split across transcript records by message id, keep the record with the largest output_tokens, and skip `<synthetic>` records.

## Green run
```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0
Verdict: PASS
  [111] cost + burn dedup one API message split across records, keep the final chunk, skip <synthetic> (in 30 / out 800 / cache-rd 3000 / cache-wr 50)
    ok: cost and burn both report 2 messages, output 800 (100 + 700), no synthetic
  smoke: all 112 passed
```

Real session, `session-observe cost --file <finished 28 MB main transcript> --json` (before = master, after = this branch):

| Run | input | output | cache_read | cache_create | est USD |
|---|---|---|---|---|---|
| before | 1426 | 951560 | 298780969 | 1797423 | 553.26 |
| after | 612 | 352544 | 129986134 | 726112 | 235.04 |

## Negative control
```
Command: bash lib/session/observe/tests/smoke.sh   (keep_best_usage key forced to object(): no dedup)
Exit: 1
Result: RED as expected
  FAIL: session A reqs wrong
  FAIL: session A rollup wrong
  FAIL: dedup wrong   (cost output 1308 / cache_read 9000, expected 800 / 3000; burn reqs 6, expected 2)
  smoke: 109 passed, 3 FAILED
```
The key line in `keep_best_usage` was replaced with `key = object()`, the run went RED (new test plus two existing burn dedup cases), then `git checkout --` restored it.

Restored run:
```
Command: bash lib/session/observe/tests/smoke.sh
Exit: 0
Verdict: PASS
  smoke: all 112 passed
```

## Not proven
- Only `cost` and `burn` read through `keep_best_usage`; the entry-fee scan reads one message and only gains the synthetic skip.
- The real-session numbers come from one file (`--file` reads the main transcript, not its subagents/ directory); the subagent 8 -> 700 case is proven on the synthetic fixture only.
- Dedup is per transcript file in `cost`, per session (main + subagent files) in `burn`; a message id repeated across two separate files in `cost` is still counted twice.
