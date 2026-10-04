# Implementation notes: ledger-check-fast

Delta from `docs/specs/SPEC-391-ledger-check-fast.md` only: what the build learned that the spec did not say.

## The goal's 2.2 s did not reproduce

The goal cites about 2.2 s per `check`. On this host (load 25 to 45 from other sessions) master measures 220 to 250 ms for `check full` on a 12-gate ledger. The 2.2 s figure comes from `docs/verification/misfires-speed.md` (22 live spawns in 48 s, on a fully loaded host). Both are spawn latency: about 100 external processes per call. The after number is stated against master on the same host and load, never against 2.2 s.

## A plain `bash -x` trace shows almost none of the cost

`check` calls `required` inside `$(... 2>/dev/null)`, so xtrace output for the whole lane derivation goes to `/dev/null`. The first trace showed 18 `awk` and nothing else. `BASH_XTRACEFD=7 ... 7>| file` writes the trace to a separate descriptor and shows all 103 spawns.

## `normalize_phase` was the biggest single cost

48 of 103 spawns: four per phase (`tr`, `sed`, `tr`, `sed`) for twelve phases, to normalize names that `lane-data.sh` already validated against `^[a-z0-9][a-z0-9-]*$`. For an input that already matches that shape the pipeline returns it unchanged, so a regex test skips it. The class is `[[:lower:][:digit:]]`, not `[a-z0-9]`: a range can match uppercase under some collations, and the pipeline lowercases. Inputs with a space, a bracket, a newline or an uppercase letter take the unchanged pipeline.

## The 2 s write guard (and ctime)

The #863 key cannot see a same-size, same-inode rewrite inside one mtime second (`stat` on macOS gives whole seconds). `_shipped_incomplete` lives with that gap because it runs over old shipped ledgers. `check` runs right after a `record`, so the gap is real: record, check (fail), edit in place, check. An entry is therefore written only when the ledger's ctime is 2 s or more in the past. The advisor review moved the guard and the key from mtime to ctime: a user can set mtime (`touch -r`, `cp -p`) but not ctime, so a same-size rewrite that restores size, mtime and inode still moves ctime. `_file_id` is now `size mtime inode ctime` for both caches (an old `.shipped-incomplete.cache` entry simply misses once). An unreadable ledger is also never cached: master answers FAIL for it and PASS after `chmod 644`, so caching the failure would outlive the fix. A ledger recorded and checked in one breath is never cached; the next check after it ages is. Cost: a few more full checks right after a record, which is when the lane derivation was always paid anyway.

## Helpers moved, not copied

`_lane_fp` and `_file_id` moved to `lib/gate/ledger-key.sh` and `lane-telemetry.sh` sources them. This edits `lib/telemetry/lane-telemetry.sh`, outside the sub-goal's `Touches`. The alternative, two copies of the fingerprint, lets the two caches key differently without any test noticing. `tests/test-lane-telemetry.sh` covers the moved helpers unchanged (it drives the cache through the real `misfires` verb).

## What the cache does not do

- It does not cache an absent ledger. `stat` fails, there is no identity, and `check` then fails every gate on the full path.
- A directory sitting at the cache path: `mv` moves the temp file into it. The answer stays correct and no temp file is left in the log dir, but the directory gains one stray file. Not guarded; nothing creates that state.
- The pre-existing 12-spawn double resolve of the log dir (`kit_migrate_log_dir` then `kit_resolve_log_dir`, each reading three `kit.toml` layers) stays. It is part of the 72 ms startup floor.

## Fingerprint: per-file hashes in one process

Concatenating the lane files into one `cksum` let bytes move between the operator and project `kit.toml` without changing the hash. `_lane_fp` now runs one `cksum` over all the files (one line each: crc, size, path), rewrites each path to a role label (`operator`, `project`, the `lib`-relative name), and hashes that list. A loop with one `cksum` per file would add about 30 spawns to every warm call. Paths are labelled, not hashed raw, so two worktrees with the same lib share the cache entries. It also calls `kit_config_project`, `kit_config_operator` and `kit_config_tracked_clean` from `kit-config.sh` instead of re-implementing them; `kit_config_tracked_clean` adds one `git rev-parse` spawn when a project `.kit.toml` exists.

## Coarse-timestamp filesystems

The 2 s guard assumes timestamps of 1 s or 2 s resolution. On a filesystem with coarser timestamps a same-size rewrite inside the timestamp window can still serve a stale entry. The ledger root is the user's local state directory, so this is documented in the spec's Out of Scope and not guarded.
