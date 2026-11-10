# ship draft arm and handoffs closed set

Delta note. No spec; two small fixes from a scout hypothesis.

## wrap ship, kind draft

- The scout was half right. `wrap ship` sent kind `draft` to the refusal branch.
- But `ship` can never reach it: `_ship_run` rejects `--draft` (exit 64) and builds `land` args from title, body-file and no-pull only. `_land_run` sets `draft=1` only from the `--draft` flag.
- So a `SHIP: draft PR opened` line would be dead code and a false promise. The arm is now explicit: `_ship_final` names the unexpected kind on stderr ("this is a bug") and returns 1. The final line is still `SHIP: refused (land:<step>, exit 1)`.
- The case moved into `_ship_final` so each kind is testable without a full ship run.

## handoffs closed set

- Closed = terminal rows of `lib/board/states.tsv` plus the archive words `done` and `resolved`. Same split as `ARCHIVED_CLOSED` in `lib/sync/sync_core.py`.
- Behavior today is identical: terminal is `shipped` and `dropped`.
- The read is one awk, in `_load_board` (main shell), so a missing table stops the scan with a message. It does not silently mark every row open.
- The test copies `handoffs.sh` and `states.tsv` into a scratch tree, because the table is found relative to the script. No new env variable.
