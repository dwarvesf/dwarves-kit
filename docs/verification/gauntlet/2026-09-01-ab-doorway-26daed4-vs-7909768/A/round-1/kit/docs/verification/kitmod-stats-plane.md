# Proof of done: kit-modularity SG-02 (stats-plane)

Spec: `docs/specs/SPEC-182-stats-plane.md`. Branch: `refactor/kitmod-02-stats-plane`.
Machine note honored: all symlink/type checks use `/usr/bin/find` (the shell `find` is a
broken `rtk find` shim).

## Acceptance criteria -> confirmation

| # | Criterion | Result |
|---|---|---|
| 1 | `ledger/` append substrate: ONE `append`/`read`/`root`, one location handler | PASS `lib/ledger/ledger.sh`; gate-ledger + proof-ledger route through `ledger_append` |
| 2 | `KIT_LEDGER_DIR` wired, aligns `DWARVES_KIT_LOG_DIR`, one root both planes | PASS precedence `KIT_LEDGER_DIR > DWARVES_KIT_LOG_DIR > XDG`; shared-root NC green |
| 3 | `ledger-observatory` -> `stats`, read-side carries no `-ledger` | PASS dir `lib/stats/`, entry `stats`, env `STATS_*`, skill+docs; write-side `-ledger` kept |
| 4 | `stats` is a pure stateless projection, persists NOTHING | PASS in-memory `:memory:` per invocation; full-snapshot NC green |
| 5 | `tools/` empty / retired | PASS `/usr/bin/find tools -type f` = 0; gone from `git ls-files` |
| 6 | session tools + orphans folded into `lib/` | PASS `lib/session/{observe,recall,intel}/`, `lib/skill-curator/`, `lib/plugin-check/` |
| 7 | suite identical-or-better | PASS (see run-table) |
| 8 | standing anti-drift lint | PASS grep-lint in `tests/test-stats-no-persist.sh`, wired to CI |

## Ledger substrate interface (the contract)

```
ledger append <stream> <text...>   # append one line to <root>/<stream> (newlines collapsed)
ledger read   <stream>             # print <root>/<stream> (empty if absent, exit 0)
ledger root                        # print the resolved root
```
Sourced form: `ledger_append` / `ledger_read` / `ledger_root`.
Root precedence (one resolver, both planes): `$KIT_LEDGER_DIR` (canonical, wins) ->
`$DWARVES_KIT_LOG_DIR` (back-compat alias) -> `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`.
A set-but-EMPTY `$KIT_LEDGER_DIR` is a clean fatal error (the silent-wrong-path guard).

## Named negative controls (actual runs)

### NC substrate + shared-root + empty-dir + honest-empty + back-compat (`tests/test-ledger-substrate.sh`)
```
  PASS  round-trip returns both rows in order
  PASS  an embedded newline does not forge a second ledger line
  PASS  root == KIT_LEDGER_DIR
  PASS  missing stream -> empty, exit 0
  PASS  empty KIT_LEDGER_DIR -> nonzero exit + a clear 'empty' error (not a silent relative write)
  PASS  no stray relative path written on the empty-root error
  PASS  DWARVES_KIT_LOG_DIR (legacy alias) writes under its root
  PASS  KIT_LEDGER_DIR takes precedence
  PASS  the GATE line gate-ledger wrote is readable through the substrate on the same root
== 9 passed, 0 failed ==
```

### NC no-persisted-projection (LOAD-BEARING) + honest-zero + determinism (`tests/test-stats-no-persist.sh`)
```
== LINT: the stats source persists no derived view (standing anti-drift, advisor P6) ==
  PASS  every duckdb.connect() is :memory: (no persistent db opened)
  PASS  no persistent-cache path (.duckdb / .stats-cache / db_path) in the stats source
== RUNTIME: full temp-HOME snapshot is byte-identical across two lens runs (advisor P5) ==
  PASS  stats gate-yield ran twice cleanly over the fixture ledger
  PASS  no-persisted-projection: FULL snapshot (temp HOME + ledger dir + repo-local) is byte-identical before/after two lens runs -- NO file written ANYWHERE
== RUNTIME honest-zero + determinism: empty ledger -> zeros, same answer twice ==
  PASS  honest-zero: empty ledger returns cleanly + the projection is deterministic (delete output, re-run, same answer)
== 5 passed, 0 failed, 0 skipped ==
```
The full-HOME snapshot method: warm uv first (so the runner's own package cache is in the
baseline), snapshot temp-HOME + `$KIT_LEDGER_DIR` + repo-local `*.duckdb`/`.stats-cache` as
`path+sha`, run `stats gate-yield` twice, snapshot again; byte-identical => no projection
persisted anywhere. Fresh-context recheck of this NC (Rung 3): **HOLDS** -- an independent
fresh-context verifier re-ran it venv-direct (uv bypassed), got a byte-identical snapshot
diff, confirmed both `duckdb.connect()` calls are `:memory:`, and correctly excluded the
uv-runner-cache confounder (the 6 `~/.cache/uv/*` files are the launcher's, not the projection's).

### NC tools/-empty
```
$ /usr/bin/find tools -type f | wc -l
0
$ git ls-files tools/     # (empty: tools/ gone from git)
```

### NC no alias shims at lib/ root
```
$ /usr/bin/find lib -maxdepth 1 -type l    # (empty)
```

## Suite before/after (identical-or-better)

Baseline (master `cb64f15`, CI-enumerated list): PASS=38, FAIL=1.
After (this branch, + 2 new tests): see run-table below.
The one FAIL is `test-board.sh` NC-e, a PRE-EXISTING local-only env drift: it compares the
real ops-toolkit `_meta/board` wrapper (which sources the STALE installed
`~/.claude/dwarves-kit/lib/board.sh` SG-01 relocated) against the repo board. It SKIPS in
CI (ops-toolkit absent), so CI is all-green; unchanged by this branch.

| Suite | Tests | PASS | FAIL | Note |
|---|---|---|---|---|
| Baseline (master cb64f15) | 39 | 38 | 1 | `test-board.sh` NC-e (pre-existing local env) |
| After (this branch) | 42 | 41 | 1 | same `test-board.sh`; +2 new tests both PASS |
| stats tool suite (`lib/stats/tests`) | 14 | 14 | 0 | out-of-CI; rename + in-memory + locator fix |
| moved-tool suites (session/skill-curator/plugin-check) | 16 | 16 | 0 | out-of-CI; locators resolve post-fold |

CI (`.github/workflows/test.yml`): all steps green (test-board's NC-e SKIPS when ops-toolkit
is absent, which is always true in CI). Two new CI steps added: `test-ledger-substrate.sh`
and `test-stats-no-persist.sh` (the latter runs the standing grep-lint in CI; the runtime
snapshot skips without uv).

## Reproduce

```
cd <repo>
git checkout refactor/kitmod-02-stats-plane
bash tests/test-ledger-substrate.sh          # substrate + KIT_LEDGER_DIR
bash tests/test-stats-no-persist.sh          # no-persist lint + full-snapshot NC
( cd lib/stats && uv sync && for t in tests/test-*.sh; do bash "$t"; done )   # stats tool suite (14)
/usr/bin/find tools -type f | wc -l          # 0
```
