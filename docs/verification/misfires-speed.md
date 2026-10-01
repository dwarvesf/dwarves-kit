# Proof of done: lane-telemetry misfires speed

## What changed

`lane-telemetry.sh misfires` took about 93 s over 197 run ledgers, and `/kit:retro` and `/kit:wrap` call it every time. It now reads the run rows once with one awk process, caches each `gate-ledger.sh check` verdict, and filters `_boardless` candidates with one grep. Output lines and order are unchanged.

## Timings

Measured from the ops-toolkit checkout against the real runs dir (198 ledgers at measurement time), `NO_COLOR=1`, one run each.

| Version | Cache | Seconds |
|---|---|---|
| origin/master | none (run 1) | 92.09 |
| origin/master | none (run 2) | 99.99 |
| this branch | cold (no cache file) | 49.69 |
| this branch | warm | 3.38 |

Cold is bound by the 22 live `gate-ledger.sh check` spawns (about 2.2 s each). Per function on the warm run: `_rows` under 1 s, `_shipped_incomplete` 2 s, `_boardless` 1 s (was 12 s).

## Gate table

| Claim | Evidence |
|---|---|
| `_rows` output is byte-identical to the per-file loop | `cmp` of master's `_rows` against this branch over the real runs dir (199 rows): identical. Same over a second odd fixture with an empty ledger and a pipe-less line: identical. In-suite oracle: `tests/test-lane-telemetry.sh` |
| `misfires` output is byte-identical | `cmp` of master's `misfires` against this branch, cold and warm, over the real runs dir: identical (28 lines) |
| `_boardless` output is identical | `cmp` of master's `_boardless` against this branch over the real runs dir: identical (9 runs) |
| a cache hit skips the gate-ledger call | `tests/test-lane-telemetry.sh`: warm run adds 0 calls, output equals cold |
| a touched ledger re-checks only itself | append (size change) and `touch -t` (mtime only) each add exactly 1 call |
| a corrupt, headerless or missing cache falls back to the live check | three asserts, each adds 3 calls and keeps the right verdict |
| a lane-data change invalidates every entry | edit to the shim `kit.toml` and an operator `kit.toml` override each add 3 calls |
| the cache write is atomic | temp file plus `mv`; no `.shipped-incomplete.cache.*` file is left behind |

## Run table

| Command | Result |
|---|---|
| `bash tests/test-lane-telemetry.sh` | 57 of 57 (was 29; 28 new) |
| `bash tests/test-meta.sh` | 902 of 902 (clean origin/master export: 902 of 902) |
| `bin/test-affected --base origin/master` | 2 suites failed: `test-gate-validate-round` (1 FAIL, `C12 report --period month`, fails the same on a clean origin/master export) and `test-hooks` (failed under load while other suites ran in parallel; re-run alone: all passed). `test-lane-telemetry`, `test-meta`, `test-e2e`, `test-gate-outcome`, `test-ledger-durability`, `test-lane-classify`, `test-config-stamp` pass |

New asserts were written first and run against the old script: 7 of the 28 failed (rows computed once, cache written, warm run, re-check count, temp file, warm-after-fallback). The identity and fallback asserts passed there by design, because the old script already behaves that way and the change must keep it.

## Negative controls

Each mutation was applied, the suite run, and the file restored by copying the saved good copy back.

| Mutation | Asserts that went red |
|---|---|
| drop the per-file state reset in `_rows` | 7 (identity, misfire lines, filter, mermaid) |
| make the cache lookup never hit | 3 (warm run, changed-ledger count, warm after fallback) |
| drop the lane-data header check | 2 (lane-data change, operator override) |

## Not changed

`_boardless` keeps its per-run greps; only its candidate list now comes from one `grep -l`. The first run after any lane-data or gate-script change is cold again, because those files feed the cache header.
