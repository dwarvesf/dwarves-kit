# Spec: make `gate-ledger.sh check` fast

Generated: 2026-10-04
Status: VALIDATED (design: profile-backed, one cache that reuses an existing key scheme; no validation fan-out run, the lead's advisor reviews the frozen diff)
Lane: full (`lib/gate/` is a hard path)
Type: spec-feature
Source: kit-speed mega-goal, sub-goal 04 (D3: reuse the #863 cache key; target a warm call under 200 ms).

## Problem

`bash lib/gate/gate-ledger.sh check <lane> <rid>` decides whether a push may go out. `hooks/ship-gate.sh` calls it on every push, `lane-telemetry.sh` calls it once per shipped ledger, and `mega-merge.sh` calls it per sub-goal. Each call re-derives the lane's required gates from `kit.toml` with about 100 process spawns, then answers from one small ledger file. The goal cites about 2.2 s per call (seen under a fully loaded host); on a quieter host the same call takes 220 to 250 ms. Both numbers are spawn latency, and they grow with host load.

## Solution

### Approaches considered

1. **Cache the verdict per ledger.** Key: the ledger's size, mtime, inode and ctime, plus a hash of the lane data and the gate scripts. The same key `_shipped_incomplete` uses (#863). A hit skips the lane derivation entirely.
2. **Rewrite the derivation without spawns** (`lane_resolve`, `_ld_array`, `lane_rows` in pure bash). Fixes the cost at the source and helps the first call too. A bigger diff in `lane-data.sh`, which the classifier also reads, so a parity risk far beyond `check`.
3. **Both.** Cache the verdict (approach 1) and remove the one spawn-heavy step that has a trivially safe fast path (`normalize_phase`, 48 of the 103 spawns).

### Chosen approach + why

Approach 3. The profile says the cost is process spawns, so the cheap spawn fix goes in first and the cache then removes the rest on every unchanged ledger. The D3 cache is the contract; the `normalize_phase` fast path is behavior-identical by construction and cuts a miss from 103 to 55 spawns. Approach 2 stays out: `lane-data.sh` has more readers than `check`, and a hit already reaches the target.

### Extensibility & boundaries

The two key helpers (`_lane_fp`, `_file_id`) move to `lib/gate/ledger-key.sh`, sourced by `gate-ledger.sh` and `lane-telemetry.sh`, so both caches share one key format and cannot drift. The cache file lives beside the existing one: `$LOG_DIR/.gate-check.cache`. A ledger the cache cannot key (missing, unstat-able) and an unknown lane never reach the cache.

## Picture

```
 check <lane> <rid>
        |
        v
 known lane? --no--> full path (fail-closed message, unchanged)
        |yes
        v
 id = size/mtime/inode of runs/<rid>.log      fp = cksum(lane data + gate scripts)
        |  (no id: full path)                          |
        +--------------------+-------------------------+
                             v
        $LOG_DIR/.gate-check.cache  line 1 "#fp=..." must equal fp
        entry "lane  rid  kit-lanes  size mtime inode ctime  pass|fail:p1,p2"
                 |hit                                  |miss, bad header, bad entry
                 v                                      v
        replay: exit 0, or the MISSING-GATE      required (lane derivation) + awk per phase
        lines for the stored phases, exit 1               |
                                                          v
                                       write the entry (temp + mv) when the ledger ctime is >= 2 s old
```

## Design

### Approaches considered + chosen

See `## Solution`. Chosen: spawn fix first, then the D3 cache.

### Diagram

See `## Picture`.

### Profile (before any code change)

`check full ledger-check-fast` on master, a 12-gate lane, traced with `BASH_XTRACEFD` (the lane derivation runs under `2>/dev/null`, so a plain `bash -x` hides it). Spawns are external processes.

| Step | Where | Spawns | Share |
|---|---|---|---|
| `normalize_phase` pipeline (`tr`, `sed`, `tr`, `sed`) once per required phase | `gate-ledger.sh` `required` | 48 | 47% |
| `grep -Eq` once per phase name when parsing the `phases` and `light` arrays | `lane-data.sh` `_ld_array` | 14 | 14% |
| `grep -qxF` once per phase to test "is it light" | `lane-data.sh` `lane_rows` | 13 | 13% |
| `awk` once per required phase over the ledger | `gate-ledger.sh` `check` | 12 | 12% |
| `awk` for each `kit.toml` read (lane arrays, `ledger.location`, twice) | `kit-config.sh` `_kit_toml_get` | 10 | 10% |
| `dirname`, `tr` (source setup, `runid`) | startup | 6 | 6% |
| Total | | 103 | |

Wall time on the quieter host (load 25 to 45 from other work), 10 calls: median about 245 ms for `check full`, startup alone (`gate-ledger.sh rid`) about 72 ms. Per-phase timers put roughly 13% in startup (sourcing, log-dir resolve), 70% in the lane derivation and 17% in the per-phase ledger awk. Full numbers: `docs/verification/ledger-check-fast.md`.

Finding: the cost is process spawns, not a slow algorithm, and the derivation repeats unchanged for an unchanged ledger. So the order is: remove the cheapest safe spawns, then cache the rest.

### Cache contract

- File: `$LOG_DIR/.gate-check.cache`, beside `.shipped-incomplete.cache`.
- Line 1: `#fp=<cksum>` from `_lane_fp` (kit root, operator and project `kit.toml`, the project file's tracked-and-clean state, every `lib/gate/*.sh`, `kit-config.sh`). Each file is hashed on its own and labelled by role, so bytes moved between layers change it. A mismatch ignores the whole file.
- Entry: `lane<TAB>rid<TAB>kit-lanes<TAB>size<TAB>mtime<TAB>inode<TAB>ctime<TAB>result`. `rid` is the normalized file name (`runid`), `kit-lanes` is `0` or `1`, `result` is `pass` or `fail:<phase>,<phase>` and must match `^(pass|fail:[a-z0-9-]+(,[a-z0-9-]+)*)$`.
- Hit: replay the stored answer. `pass` exits 0 silent. `fail:` prints one `MISSING-GATE: <phase> (required for lane '<lane>'; no ran/override entry in the ledger)` line per phase, in plan order, to stderr and exits 1. Output is byte-identical to the full path.
- Miss, unreadable file, bad header, malformed entry or any other doubt: the full computation runs, and its result is written back.
- Write: only for a readable ledger whose ctime is at least 2 s old (a user can set mtime, never ctime; a same-size rewrite inside the timestamp second would be invisible to the key), as temp file plus `mv`, newest 400 other entries kept, failure never fatal, temp removed on EXIT, TERM and INT.
- Never cached: an unknown lane (stays fail-closed), an empty `runid`, an unreadable ledger, a ledger `stat` cannot read (including a missing ledger).

### ADR link(s)

None. `docs/decisions/0024-gate-ledger-and-ship-enforcement.md` stays accurate: the cache changes how fast `check` answers, not what it decides.

### Boundaries & failure modes

- The key trusts the filesystem's size, mtime, inode and ctime. ctime moves on every write and cannot be set by a user, so a rewrite that restores size, mtime and inode (`cp -p`, `touch -r`) is still seen. A same-size, same-inode rewrite inside one timestamp second is invisible to the key, which is why a ledger changed under 2 s ago is not cached.
- A concurrent writer can lose another writer's entry (last `mv` wins). The loser re-derives once.
- The cache directory is the ledger root, so anyone who can write a cache entry can already write the ledger.

## Technical Design

### Interfaces (I/O contract)

`gate-ledger.sh check <lane> <rid> [--kit-lanes]`: unchanged arguments, stdout, stderr and exit codes (0 pass, 1 missing gate or unknown lane, 64 usage). `hooks/ship-gate.sh` and `lane-telemetry.sh` call it as before.

### Data model, API, UI, infrastructure changes

- New `lib/gate/ledger-key.sh` (`_lane_fp`, `_file_id`, moved verbatim from `lane-telemetry.sh`).
- `lib/gate/gate-ledger.sh`: `_check_cache_get`, `_check_cache_put`, cache lookup and write in `check`, and a regex fast path in `normalize_phase` for an already-stable key.
- `lib/telemetry/lane-telemetry.sh`: the two helpers are sourced instead of defined (outside the sub-goal's `Touches`, a mechanical move so one key format exists).
- New suite `tests/test-gate-ledger-check-cache.sh`.

## Task Breakdown

### Phase 1: Foundation
- [x] TASK-1: Profile `check` before changing code. AC: the table in `## Design` carries a spawn count per step and a wall-time baseline.

### Phase 2: Core
- [x] TASK-2: Add the `normalize_phase` fast path and the `check` verdict cache, moving the key helpers to `lib/gate/ledger-key.sh`. AC: output and exit code equal master's across every lane and ledger shape; a warm call is under 200 ms.
- [x] TASK-3: Add `tests/test-gate-ledger-check-cache.sh`. AC: it pins parity, the four invalidation controls and the corrupt-cache cases, and goes red when the key drops the inode or the fingerprint.

### Phase 3: Polish
- [x] TASK-4: Implementation note, proof of done, CHANGELOG line, regenerated `docs/FEATURES.md`. AC: `docs/verification/ledger-check-fast.md` carries a `## Recorded run` section per claim.

## After state

- [x] A warm `check` takes under 200 ms (median of 10); master takes about 220 ms on the same host.
- [x] Cold and warm output and exit code equal master's for every fixture ledger.
- [x] Appending a ledger line, editing `[lane.normal]`, editing `gate-ledger.sh`, and swapping the ledger file at the same size and mtime each change the result.
- [x] A corrupt cache file never changes the answer.

## Acceptance Criteria (global)

- [x] All tasks pass their individual acceptance criteria.
- [x] `check` decides exactly what it decided before; speed only.
- [x] No regression in the suites `bin/test-affected` picks for the diff.

## Verification

```bash
bash tests/test-gate-ledger-check-cache.sh
bash tests/test-lane-telemetry.sh
bash tests/test-hooks.sh
bash tests/test-gate-ledger-history.sh
bash tests/test-ship-gate-fail-closed.sh
bash lib/gate/proof-gate.sh contract "cache gate-ledger check"
# parity against master, timing, controls: docs/verification/ledger-check-fast.md
```

## Edge Cases

1. A project `.kit.toml` that is dirty against HEAD: the fingerprint carries the tracked-and-clean flag, so the cached verdict is dropped when the file flips.
2. `--kit-lanes`: its own key field; an operator override makes the two answers differ and both stay correct warm.
3. A read-only log dir: the write fails quietly and every call runs the full path.
4. A ledger changed less than 2 s ago: never cached, so a same-size rewrite in that second is seen.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Stale verdict served after a lane or script edit | `tests/test-gate-ledger-check-cache.sh` N2, N3 | the fingerprint covers `kit.toml`, the operator file and every `lib/gate/*.sh` |
| Stale verdict served after a ledger rewrite | N1, N4, N5, N7 | size, mtime, inode and ctime key; the 2 s write guard on ctime |
| Failure cached for an unreadable ledger | N8 | an unreadable ledger is never cached |
| Bytes moved between kit.toml layers | N9 | per-file, role-labelled hashes in `_lane_fp` |
| Corrupt or hostile cache content | C1 to C8 | a strict result regex; any doubt falls through to the full path |
| Cache write interrupted | C10 | temp file removed on EXIT, TERM and INT |

## Out of Scope

- Rewriting `lane-data.sh` without spawns (approach 2). The lane arrays still cost about 55 spawns on a miss.
- A single awk over the ledger for all required phases. About 11 spawns on a miss, not needed to reach the target.
- Filesystems whose timestamps are coarser than 2 s (FAT keeps a 2 s mtime, some network mounts more). The 2 s guard holds on 1 s and 2 s filesystems, not coarser ones; there a same-size rewrite inside the timestamp window can serve a stale entry. Not guarded: the ledger root is the user's own state directory on a local disk.
- Speeding the fixed startup (log-dir resolve and migrate run `kit_config_get` twice, about 12 spawns).

## Touches

- lib/gate/**
- tests/**
- docs/specs/**
- docs/implementation-notes/**
- docs/verification/**

## Decision Log

- DEC-1: reuse the #863 key and move its two helpers into one shared file rather than copy them. Two copies would let the two caches drift apart. Cost: a four-line edit in `lane-telemetry.sh`, outside the listed `Touches`; flagged for the lead.
- DEC-2: add ctime to the key and a 2 s write guard on ctime on top of the #863 key. That key cannot see a same-size, same-inode rewrite in the same mtime second, and mtime can be set by the user while ctime cannot. The guard costs nothing on a ledger that has aged.
- DEC-3: cache `fail` verdicts with their phase list so a hit prints the exact `MISSING-GATE` lines. Caching only `pass` would leave the failing case, which a push hits again and again, slow.
- DEC-4: no off switch. A cache that cannot be trusted is removed by deleting one dotfile in the log dir, and every miss path is the original code.

## Grounding

- Profile: `BASH_XTRACEFD` trace of master `check full`, counts above; per-phase timers inserted in a scratch copy of master.
- The key scheme: `_shipped_incomplete` and its comment block in `lib/telemetry/lane-telemetry.sh` (#863), `docs/verification/misfires-speed.md`.
- Parity, timing and controls: `docs/verification/ledger-check-fast.md`.

## Test plan

| # | Case | Type | Covers | Check |
|---|---|---|---|---|
| 1 | Warm equals cold for every lane x ledger shape (pass, override, missing one, none, skipped) | parity | After state 2 | `tests/test-gate-ledger-check-cache.sh` P1 |
| 2 | Expected answers pinned, not only cold equals warm | regression | After state 2 | P2 |
| 3 | Append a ledger line flips fail to pass | negative control | After state 3 | N1 |
| 4 | Edit `[lane.normal]` flips pass to fail | negative control | After state 3 | N2 |
| 5 | Edit `gate-ledger.sh` changes the result | negative control | After state 3 | N3 |
| 6 | Same size and mtime, new inode flips fail to pass | negative control | After state 3 | N4 |
| 7 | A fresh ledger is not cached; in-place same-size rewrite is seen | negative control | Edge case 4 | N5 |
| 7b | Same-size rewrite with the mtime restored is seen | negative control | After state 3 | N7 |
| 7c | An unreadable ledger is not cached and recovers | negative control | After state 3 | N8 |
| 7d | A block moved between operator and project kit.toml invalidates | negative control | After state 3 | N9 |
| 8 | `--kit-lanes` keyed apart | regression | Edge case 2 | N6 |
| 9 | Garbage, bad-identity, malformed, truncated, empty and directory cache all answer correctly | robustness | After state 4 | C1 to C8 |
| 10 | Warm call under 200 ms against master's median | timing | After state 1 | `docs/verification/ledger-check-fast.md` |
