# Proof of done: bridge readers tolerate a 4th registry column

`cmd_status`/`cmd_mirror` read `boards.txt` via `read -r name path bridge`, slurping trailing tokens into `bridge`; a row with both `on` and SPEC-128's `rail=` column silently left the mirror's opt-in set (ops-toolkit ID-633, hit live when its row gained `rail=personal`). Fix: positional read with `_rest`, matching `board-writeback.sh`. The test fixture's opted-in row now carries the 4th column so every case exercises the shape.

## Green run

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-board-mirror.sh` (fixture opted-in row = `on rail=personal`) | 0 | PASS 72/72 |

## Negative control

Fault injected: reverted both readers to the bare 3-field `read`. Result: 14/72 FAIL (the opted-in repo vanishes from every mirror/status plan). Restored from the commit; 72/72 (run #1).

## Reproduce

```bash
bash tests/test-board-mirror.sh
```
