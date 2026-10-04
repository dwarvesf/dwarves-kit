# Implementation notes: ledger-check-fast

Delta from `docs/specs/SPEC-391-ledger-check-fast.md` only: what the build learned that the spec did not say.

## The goal's 2.2 s did not reproduce

The goal cites about 2.2 s per `check`. On this host (load 25 to 45 from other sessions) master measures 220 to 250 ms for `check full` on a 12-gate ledger. The 2.2 s figure comes from `docs/verification/misfires-speed.md` (22 live spawns in 48 s, on a fully loaded host). Both are spawn latency: about 100 external processes per call. The after number is stated against master on the same host and load, never against 2.2 s.

## A plain `bash -x` trace shows almost none of the cost

`check` calls `required` inside `$(... 2>/dev/null)`, so xtrace output for the whole lane derivation goes to `/dev/null`. The first trace showed 18 `awk` and nothing else. `BASH_XTRACEFD=7 ... 7>| file` writes the trace to a separate descriptor and shows all 103 spawns.

## `normalize_phase` was the biggest single cost

48 of 103 spawns: four per phase (`tr`, `sed`, `tr`, `sed`) for twelve phases, to normalize names that `lane-data.sh` already validated against `^[a-z0-9][a-z0-9-]*$`. For an input that already matches that shape the pipeline returns it unchanged, so a regex test skips it. The class is `[[:lower:][:digit:]]`, not `[a-z0-9]`: a range can match uppercase under some collations, and the pipeline lowercases. Inputs with a space, a bracket, a newline or an uppercase letter take the unchanged pipeline.

## The 2 s write guard

The #863 key cannot see a same-size, same-inode rewrite inside one mtime second (`stat` on macOS gives whole seconds). `_shipped_incomplete` lives with that gap because it runs over old shipped ledgers. `check` runs right after a `record`, so the gap is real: record, check (fail), edit in place, check. An entry is therefore written only when the ledger's mtime is 2 s or more in the past. A ledger recorded and checked in one breath is never cached; the next check after it ages is. Cost: a few more full checks right after a record, which is when the lane derivation was always paid anyway.

## Helpers moved, not copied

`_lane_fp` and `_file_id` moved to `lib/gate/ledger-key.sh` and `lane-telemetry.sh` sources them. This edits `lib/telemetry/lane-telemetry.sh`, outside the sub-goal's `Touches`. The alternative, two copies of the fingerprint, lets the two caches key differently without any test noticing. `tests/test-lane-telemetry.sh` covers the moved helpers unchanged (it drives the cache through the real `misfires` verb).

## What the cache does not do

- It does not cache an absent ledger. `stat` fails, there is no identity, and `check` then fails every gate on the full path.
- A directory sitting at the cache path: `mv` moves the temp file into it. The answer stays correct and no temp file is left in the log dir, but the directory gains one stray file. Not guarded; nothing creates that state.
- The pre-existing 12-spawn double resolve of the log dir (`kit_migrate_log_dir` then `kit_resolve_log_dir`, each reading three `kit.toml` layers) stays. It is part of the 72 ms startup floor.
