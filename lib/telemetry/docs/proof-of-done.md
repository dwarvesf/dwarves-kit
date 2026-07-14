# Proof of Done: telemetry

**Feature:** the durable ledger root (`kit-log-dir.sh`, the ONE resolver every kit ledger routes through) and the lane/gate misroute aggregator (`lane-telemetry.sh`).
**Date:** 2026-07-15 · **Lane:** full (lib/ enforcement-adjacent storage; data-loss class) · **Host:** Hans-Air-M4 (macOS 26.5)
**Specs:** `docs/specs/SPEC-097-ledger-durability.md` (origin), `docs/specs/SPEC-182-stats-plane.md` D2 (one root, two planes), `docs/specs/SPEC-061-lane-telemetry.md` (the aggregator) · **ADR:** `docs/decisions/0035-durable-ledger-root.md`

Written to close a gap the module's own records named: `telemetry` shipped the resolver that decides where EVERY durable ledger in the kit is written, and carried no ADR, no proof, and no tests of its own (`tests/kit-contract-known-gaps.txt`, 2026-07-14 doc sweep). The machinery was real and the evidence was not. This proof and the 17-assertion suite it records are new; the behavior they pin is not.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | `KIT_LEDGER_DIR` wins over the `DWARVES_KIT_LOG_DIR` alias AND over `kit.toml [ledger].location` | SPEC-182 D2 |
| A2 | With `KIT_LEDGER_DIR` unset, the `DWARVES_KIT_LOG_DIR` alias still resolves (back-compat: the live corpus and every pre-SPEC-182 test pin ride this) | SPEC-182 D2 |
| A3 | With neither env var set, `kit.toml [ledger].location` decides: `isolated` -> `$PWD/.kit/logs`, an explicit path -> that path | `docs/verification/wire-ledger.md` |
| A4 | The bare default is `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`, and it is never inside `~/.claude` (the reinstall blast zone that wiped the corpus on 2026-07-01) | SPEC-097 AC1 |
| A5 | A set-but-EMPTY `KIT_LEDGER_DIR` FAILS LOUD (nonzero, diagnostic on stderr, no path on stdout) instead of silently resolving a relative root | NEGATIVE CONTROL / SPEC-182 D2 |
| A6 | Migration REFUSES to copy through a symlinked legacy dir (no arbitrary-file exfiltration into the corpus `/kit:retro` reads), and still sentinels so a hostile link is not re-scanned | NEGATIVE CONTROL / SPEC-097 SEC2 |
| A7 | The consumers actually resolve through the resolver: `lane-telemetry report` reads the root it returns, and aggregates a seeded lane misroute | SPEC-061 |
| A8 | No regression in the existing suites that pin this machinery | SPEC-097 AC9 |

## Implementation

| Piece | What | Where |
|---|---|---|
| The resolver | `kit_resolve_log_dir` (4-level precedence + the set-but-empty fatal), `kit_legacy_log_dir`, `kit_migrate_log_dir` (additive, sentinel-guarded, symlink-refusing) | `lib/telemetry/kit-log-dir.sh` |
| The aggregator | `report` / `misfires` / `render` / `trace` over the pipe-delimited run ledgers; pure bash+awk, no new store | `lib/telemetry/lane-telemetry.sh` |
| Config layer (level 3) | `[ledger].location` read via the one TOML reader | `lib/config/kit-config.sh` |
| The lint that keeps it single | C6: no `lib/` code line may hardcode the pre-SPEC-097 path | `tests/test-kit-contract.sh` |
| Tests (new) | 17 assertions: 4 precedence levels, the empty-root fatal + falsifier, the symlink refusal + positive control, consumer wiring | `lib/telemetry/tests/smoke.sh` |
| Records (new) | the decision record this module never had | `docs/decisions/0035-durable-ledger-root.md` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| A1-A4, A7 (precedence + wiring) | `bash lib/telemetry/tests/smoke.sh` | `smoke: all 17 passed` | PASS |
| A5 NEGATIVE CONTROL (empty root fails loud) | `env KIT_LEDGER_DIR= bash lib/queue/queue.sh --help` | refuses, exit 1, names the cause | PASS |
| A5 falsifier (a sane root still works) | `env KIT_LEDGER_DIR=/tmp/kit-nc-root bash lib/queue/queue.sh --help` | usage banner, `Exit: 0` | PASS |
| A6 NEGATIVE CONTROL (symlink refusal) | smoke cases 6a-6d | target contents NOT copied; refusal on stderr; sentinel dropped | PASS |
| A8 no regression | `bash tests/test-lane-telemetry.sh` | `25/25 passed` | PASS |
| A8 no regression | `bash tests/test-ledger-durability.sh` | `35/35 passed` | PASS |
| Contract lint stays green | `bash tests/test-kit-contract.sh` | `22 passed, 0 failed` | PASS |

Run on a clean clone of `master` (`8475ace`) with only this branch's changes applied, because the shared working copy was being written concurrently by a sibling agent (see Notes).

## Run detail

```
$ bash lib/telemetry/tests/smoke.sh
== precedence: KIT_LEDGER_DIR > DWARVES_KIT_LOG_DIR > kit.toml [ledger].location > XDG ==
  ok: P1 KIT_LEDGER_DIR wins over the alias and the toml
  ok: P2 DWARVES_KIT_LOG_DIR (alias) wins over the toml when KIT_LEDGER_DIR is unset
  ok: P3a kit.toml [ledger].location = <explicit path>
  ok: P3b kit.toml location = isolated -> $PWD/.kit/logs
  ok: P4a location = shared -> XDG state default
  ok: P4b no [ledger] key at all -> XDG state default
  ok: P4c the default is outside ~/.claude (the SPEC-097 invariant)
== NEGATIVE CONTROL: a set-but-empty root must FAIL LOUD, not resolve ==
  ok: NC1 empty KIT_LEDGER_DIR exits nonzero (rc=1)
  ok: NC2 empty KIT_LEDGER_DIR prints NO path on stdout
  ok: NC3 the failure names the cause on stderr
  ok: NC4 (falsifier) a non-empty KIT_LEDGER_DIR still resolves
== NEGATIVE CONTROL: migration must refuse a symlinked legacy dir ==
  ok: 6a POSITIVE CONTROL: a real legacy dir IS migrated (so 6b's refusal is falsifiable)
  ok: 6b the symlink target's contents are NOT copied into the corpus
  ok: 6c the refusal is announced on stderr
  ok: 6d the sentinel is dropped, so a hostile link is not re-scanned every command
== wiring: the module's own consumer resolves through the resolver ==
  ok: 7a lane-telemetry report reads the root the resolver returns
  ok: 7b the seeded lane misroute is aggregated (chosen != classified)

smoke: all 17 passed
Exit: 0
```

The A5 NEGATIVE CONTROL, driven organically (an empty root propagating into the one launcher that runs unattended overnight). Both guards fire in sequence: the resolver refuses to return a root, and queue.sh refuses the `/queue-journal.tsv` path it would otherwise have written a whole night's history to.

```
$ env KIT_LEDGER_DIR= bash lib/queue/queue.sh --help
kit-log-dir: KIT_LEDGER_DIR is set but empty; refusing to resolve a ledger root (would write to a relative path)
queue: refusing a filesystem-root journal path (/queue-journal.tsv)
Exit: 1

$ env KIT_LEDGER_DIR=/tmp/kit-nc-root bash lib/queue/queue.sh --help
usage: queue.sh run <src.tsv> [--dry-run] [--max-megas N] [--from-boards] [--journal <path>]
Exit: 0
```

No regression, and the contract lint stays green:

```
$ bash tests/test-lane-telemetry.sh | tail -1
=== 25/25 passed, 0 failed ===
Exit: 0

$ bash tests/test-ledger-durability.sh | tail -1
=== 35/35 passed, 0 failed ===
Exit: 0

$ bash tests/test-kit-contract.sh | tail -1
=== kit-contract: 22 passed, 0 failed ===
Exit: 0
```

## Defect found while writing this proof (NOT fixed here)

The write plane and the read plane disagree about the root whenever `[ledger].location` is not the default. `lib/stats/src/stats/config.py::kit_log_dir` is a SECOND, Python implementation of this precedence and it implements only levels 1, 2 and 4: it never reads `kit.toml [ledger].location`, although its docstring claims it "mirrors the shell resolver exactly (SPEC-182)". The shell resolver gained the config layer later; the Python copy was never updated. SPEC-182 D2 requires precisely the opposite ("the writer writes and `stats` reads the SAME root").

```
kit.toml: [ledger].location = /var/folders/.../tmp.L1Rmg8vmsm/explicit

shell write plane : /var/folders/.../tmp.L1Rmg8vmsm/explicit
python read plane : /var/folders/.../tmp.L1Rmg8vmsm/xdg/dwarves-kit/logs
Exit: 0
```

Latent, not currently firing: the shipped `kit.toml` default is `location = "shared"`, which both planes resolve to XDG. It bites the moment a consumer selects the `isolated` mode the config surface openly offers, and it fails SILENTLY (stats reads an empty root and reports no runs). Recorded in ADR-0035's Consequences with the two exits (shell out to the one resolver, or teach the Python copy the toml layer and lint the two against each other). Choosing between them is a behavior change and needs its own spec, so this branch documents it rather than smuggling a fix into a records PR.

## Reproduce

```bash
cd <dwarves-kit>
bash lib/telemetry/tests/smoke.sh              # 17 assertions: precedence, empty-root fatal, symlink refusal
env KIT_LEDGER_DIR= bash lib/queue/queue.sh --help   # NEGATIVE CONTROL: must refuse, exit 1
bash tests/test-lane-telemetry.sh              # 25/25
bash tests/test-ledger-durability.sh           # 35/35
bash tests/test-kit-contract.sh                # 22 passed, 0 failed

# the write-plane / read-plane divergence (defect above)
W=$(mktemp -d); mkdir -p "$W/root" "$W/proj"
printf '[ledger]\nlocation = "%s/explicit"\n' "$W" > "$W/root/kit.toml"
env HOME="$W/h" XDG_STATE_HOME="$W/xdg" KIT_CONFIG_ROOT="$W/root" KIT_PROJECT_ROOT="$W/proj" \
  bash -c 'source lib/telemetry/kit-log-dir.sh && kit_resolve_log_dir; echo'
env HOME="$W/h" XDG_STATE_HOME="$W/xdg" KIT_CONFIG_ROOT="$W/root" KIT_PROJECT_ROOT="$W/proj" \
  python3 -c "import sys; sys.path.insert(0,'lib/stats/src')
from stats.config import kit_log_dir; print(kit_log_dir())"
```

## Notes

Every command above was run on a clean clone of `master` (`8475ace`) carrying only this branch's changes. The shared working copy could not be trusted as a test bed: a sibling agent was concurrently scaffolding `lib/cosmetic/` and `lib/money-gate/` in the same checkout (and switching its branch), which made `tests/test-kit-contract.sh` report different offenders run to run. That flapping is theirs, not this branch's; on an isolated tree the contract lint is `22 passed, 0 failed`.
