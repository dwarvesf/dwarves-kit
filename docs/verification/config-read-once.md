# Proof of done: config-read-once

Branch `perf/config-read-once` on master 2175545b, code commit 8e1c24ce. Spec: `docs/specs/SPEC-398-config-read-once.md`. Notes: `docs/implementation-notes/config-read-once.md`.

Verdict summary: `kit_config_get`, `kit_config_get_root` and the raw `_kit_toml_get` return the same value as the pre-cache resolver in all 3382 differential cases, under bash 3.2 and bash 5.3, through `$(...)`, in one process, and in reverse order. A process now parses each distinct layer content once: 150 lookups after the source spawn no awk. Fifty lookups cost about half the wall time. A saved copy whose cache never invalidates turns the mid-process-edit case red. The host was shared with other sessions the whole time (1-minute load 7 to 65), so wall numbers are noisy; CPU seconds are the steadier column.

## Parity

The oracle is `tests/lib/kit-config-reference.sh`, a frozen copy of master's resolver. Cases come from every `section.key` of the repo kit.toml plus 19 fixture tomls: quotes, inline and full-line comments, arrays (including a continuation line that starts with `[`), duplicate keys and sections, dotted and spaced section names, empty values, CRLF, a BOM, headerless keys, regex-metacharacter keys, an empty file, comment-only, no trailing newline, a directory where the file should be, an unreadable file, and project over operator over root triples with missing layers. 214 distinct keys; 3382 rows: `get` and `root` with and without a default, and the raw getter (found-empty vs absent included, newline compared).

```
Command: bash tests/test-config-cache.sh
Exit: 0
Output: === config-cache: 3382 parity cases over 214 keys, 20 fixtures ===
          PASS parity bash 3.2 sub: 3382 cases, zero diffs
          PASS parity bash 3.2 direct: 3382 cases, zero diffs
          PASS parity bash 3.2 in-process, reversed order: zero diffs
          PASS parity bash 5.3 sub: 3382 cases, zero diffs
          PASS parity bash 5.3 direct: 3382 cases, zero diffs
          PASS bash 3.2 cache: mid-process edit, other root, delete, operator edit, slot recycling
          PASS bash 5.3 cache: mid-process edit, other root, delete, operator edit, slot recycling
          PASS awk runs after source / after 150 lookups / after one edit and 3 lookups
          PASS KIT_CONFIG_NO_PRIME: 0 awk at source, value still read, then 1 parse
          config-cache: 12 passed, 0 failed       (after the flick fix below; the first run, 11 passed, took 133 s at load 10 to 20)
Verdict: PASS (3382 cases, zero diffs)
```

The same run against master's own file instead of the frozen copy (`git show origin/master:lib/config/kit-config.sh`):

```
Command: KIT_CONFIG_REFERENCE=<master copy> bash tests/test-config-cache.sh
Exit: 0
Output: config-cache: 11 passed, 0 failed, run before the NO_PRIME case existed (same 3382 cases, zero diffs on bash 3.2 and 5.3; wall 296 s at load 30 to 47)
Verdict: PASS (the frozen copy and master's file agree on every case)
```

## Timing

Fifty sequential `kit_config_get` calls in one process (five keys cycled, root layer only, kit.toml 53 KB), `/bin/bash` 3.2, source time included. Three alternating repetitions at 1-minute load 7. `sub` is `v="$(kit_config_get ...)"` as the 158 call sites write it; `direct` is a plain call.

| Mode | Resolver | Wall | CPU user+sys | Per call (wall) |
|---|---|---|---|---|
| sub | master | 0.310 to 0.337 s | 0.258 to 0.266 s | 6.2 to 6.7 ms |
| sub | this branch | 0.147 to 0.154 s | 0.139 to 0.150 s | 2.9 to 3.1 ms |
| direct | master | 0.332 to 0.336 s | 0.259 to 0.268 s | 6.6 to 6.7 ms |
| direct | this branch | 0.105 to 0.109 s | 0.107 to 0.111 s | 2.1 to 2.2 ms |

Wall falls 2.1x (sub) and 3.1x (direct); CPU falls about 1.8x and 2.4x. The floor is one read of the 53 KB file per lookup to confirm its content is unchanged (bash 3.2 reads a command substitution 128 bytes at a time); see the notes. In the `sub` row most of what remains is the caller's own subshell.

One real caller: `gate-ledger.sh required full` (reads lane data through `_kit_toml_get`), run 4 times each from a clean `git archive` of master and from the branch, `awk` counted by a PATH shim.

| Tree | Wall (4 runs) | awk spawns per run | Output |
|---|---|---|---|
| master | 143 to 168 ms | 10 | identical |
| this branch | 152 to 160 ms | 5 | identical |

Honest reading: spawns halve, wall does not move for this caller. Its 150 ms is grep, sort and subshells in lane-data and gate-ledger, not config reads. `lane-data.sh` also reads its own checkout's kit.toml at a path the source-time prime does not cover (a one-line `_kit_toml_load` in lane-data.sh would drop 5 spawns to 4); that file is a caller, so it is left as a follow-up.

```
Command: bench3.sh <old|new> <sub|direct>, rt.sh <tree> 4      (scratch drivers; numbers above)
Exit: 0
Verdict: PASS (faster on every row; real caller unchanged in wall, half the awk spawns)
```

## Suites

```
Command: bash tests/test-config.sh ; bash tests/test-config-stamp.sh ; bash tests/test-config-seams.sh
Exit: 0 ; 0 ; 0
Output: PASS kit-config selftest ; === 17/17 passed, 0 failed === ; === 56/56 passed ===
Verdict: PASS
```

```
Command: bash tests/test-config-registry.sh      (branch, then a clean archive of master)
Exit: 1 ; 1
Output: === 57/59 passed === on both. The same two assertions fail on master and on the branch:
        "0 orphans on the live tree" (ORPHAN: KIT_NARROW_PL, set in bin/test-affected) and
        "declared root-only keys == actual kit_config_get_root call sites" (decide.points, read in lib/wrap/)
Verdict: PASS for this change (no new failure; both are existing drift, not touched here)
```

## Negative control

Committed first (8e1c24ce). Then a saved copy of `lib/config/kit-config.sh`, with the identity check in `_kit_toml_slot` replaced by `true &&` so a slot never invalidates. Restored with `command cp -f`; `git diff --quiet` clean afterwards.

```
Command: bash tests/test-config-cache.sh      (broken copy in place)
Exit: 1
Output: FAIL bash 3.2 cache: mid-process edit ... (got [1 2;2 2;3 projA;4 projB;5 projA;6 projA;7 shared;8 opA;9 opA;10 0;]
             want [1 2;2 7;3 projA;4 projB;5 projA;6 projC;7 shared;8 opA;9 opB;10 0;])
        FAIL bash 5.3 cache: mid-process edit ... (same)
        FAIL awk runs after source / after 150 lookups / after one edit and 3 lookups (got [0 0 0] want [0 0 1])
        config-cache: 8 passed, 3 failed
Verdict: PASS (the control went red on the three cache-behaviour cases; parity cases stay green because they never edit a file mid-process, as expected)
```

```
Command: git diff --quiet lib/config/kit-config.sh      (after the restore)
Exit: 0
Verdict: PASS (restored)
```

## Affected suites

One run of `bin/test-affected --base origin/master --no-cache` for the whole diff (36 suites, 2 at a time because load was 30 to 47, 14 m 50 s). It found two things, both handled:

```
Command: bin/test-affected --base origin/master --no-cache
Exit: 1
Output: test-affected: 36 selected, 33 pass, 0 cached, 2 fail, 1 timeout, 1 uncovered
        FAIL tests/test-config-registry.sh   57/59: the same two assertions that fail on master (see Suites)
        FAIL tests/test-flick.sh             338 passed, 1 failed: "the whole batch used exactly one dictionary pass"
        TIMEOUT tests/test-config-cache.sh   killed at 300 s, no assertion failed (296 s alone at load 30 to 47)
        UNCOVERED docs/verification/config-read-once.md   (a doc, no suite owns it)
Verdict: two real findings, fixed below; test-config-registry is existing master drift
```

1. **flick regression, real.** The source-time prime added one awk run per existing layer to every script that sources kit-config.sh. `lib/decide/flick.sh` sources it but reads config with its own reader, and its test pins one awk spawn per dictionary batch. Fix: `KIT_CONFIG_NO_PRIME=1` skips the prime; flick.sh sets it on its source line (the one caller edit); a new case in `tests/test-config-cache.sh` pins the opt-out.
2. **Timeout.** The parity oracle forks three awk per case, so the suite needs more than the 300 s default on a busy host. `bin/test-affected.timeouts` now lists `test-config-cache 900`.

```
Command: bash tests/test-flick.sh ; bash tests/test-config-cache.sh ; bash tests/test-run-all-times.sh ; bash tests/test-test-affected-cache.sh ; bash tests/test-test-affected.sh
Exit: 0 ; 0 ; 0 ; 0 ; 0
Output: flick: 339 passed, 0 failed ; config-cache: 12 passed, 0 failed ; run-all-times: 29 passed, 0 failed ; test-affected-cache: 17 passed, 0 failed ; test-test-affected: 74 passed, 0 failed
Verdict: PASS
```

The other 32 selected suites passed in the run above (adopt, config, config-seams, config-stamp, harvest-sweep, host-load-warn, install-modules, model-routing, orchestrate, precedent, registry-freshness-guard, registry-verbs, reserved-config-guard, suite-knob, sync-cron-launcher, test-affected-parallel, turn-cap, wrap-carry, wrap-deploy, wrap-land, wrap-merge, wrap-rebase, and the test-meta suites). They ran before the NO_PRIME edit, which touches only the prime line and flick.sh; flick and config-cache were re-run after it.
