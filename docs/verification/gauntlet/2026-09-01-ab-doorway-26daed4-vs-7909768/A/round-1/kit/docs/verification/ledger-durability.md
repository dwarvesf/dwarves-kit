# Proof of done: run-ledger durability + per-gate override reasons (SPEC-097, kit-telemetry SG-01)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | durable default is XDG state, not `~/.claude/dwarves-kit` | `test-ledger-durability.sh`: a `record` under fake `$HOME`+`$XDG_STATE_HOME` (env unset) writes `$XDG/dwarves-kit/logs/runs/`, never `$HOME/.claude/...` | PASS |
| AC2 | seeded legacy corpus migrates in additively | test: seeded legacy `runs/*.log` copied to durable; legacy dir left intact | PASS |
| AC3 [reinstall NC] | after migration, wiping the legacy dir leaves records readable; telemetry still reads them | test: `rm -rf $HOME/.claude/dwarves-kit` then `lane-telemetry report`/`misfires` still return the migrated records | PASS |
| AC4 | migration idempotent + non-clobber | test: a divergent durable file keeps its content after a 2nd access; `.migrated` sentinel present | PASS |
| AC5 | explicit `DWARVES_KIT_LOG_DIR` honored; migration never ingests legacy corpus | test: writes land at the explicit path; a seeded legacy file is NOT pulled in | PASS |
| AC6 | blanket override rejected; distinct per-gate reason passes | test: 1st override ok; same reason on another gate -> exit 65; distinct reason ok | PASS |
| AC7 | idempotent same-phase override allowed | test: re-applying the same reason to the SAME gate is accepted | PASS |
| AC8 | corpus migrated (fixture-hermetic in test; live corpus in this proof) | test AC2/AC8 on fixtures + LIVE run-table below (real 8 kit-harden + operate-contract ledgers now at durable path) | PASS |
| AC9 | no regression | `test-hooks` 438/438, `test-meta` 578/578, `test-lane-escalation` 22/22, `test-mega-reconcile` 35/35 | PASS |
| B1 [validate] | lane-classify downgrade writer lands where lane-telemetry reads (no split-brain) | test: `lane-classify check` downgrade writes durable `completeness.log`, never legacy | PASS |
| SEC1 [security] | newline in reason cannot forge a GATE line | test: reason collapses to 1 line; forged `build\|ran` still reported MISSING by `check()` | PASS |
| SEC2 [security] | migration refuses a symlinked legacy dir | test: a symlinked legacy -> `private.txt` NOT copied; record still works | PASS |
| S3 [review] | override guard handles a `\|`-bearing reason (DEC-004 `$5..NF`) | test: full-reason match rejects; pre-pipe prefix does not | PASS |

## Implementation

- `lib/telemetry/kit-log-dir.sh` (new) -- the single resolver: `kit_resolve_log_dir`
  (`$DWARVES_KIT_LOG_DIR` else `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`),
  `kit_legacy_log_dir`, `kit_migrate_log_dir` (sentinel-guarded, additive `cp -Rn`,
  no-ops when the env is set, provably return-0). Idempotent-source guard.
- `lib/gate/gate-ledger.sh` -- sources the resolver + migrate-on-load; `override()` gains
  the blanket-reject guard (reason reused across gates in one run -> exit 65; reason
  reconstructed `$5..NF` so a `|`-bearing reason compares exactly; only `override`
  lines count).
- `lib/gate/proof-ledger.sh`, `lib/telemetry/lane-telemetry.sh`, `lib/precedent.sh`,
  `lib/goal/mega-merge.sh`, `lib/classify/lane-classify.sh` -- source the resolver, migrate-on-load
  (`|| true`), path from resolver. lane-classify moved because it WRITES
  `completeness.log` the moved lane-telemetry READS (validate B1).
- `tests/test-ledger-durability.sh` -- 18 assertions (AC1-AC8 + B1).
- `docs/implementation-notes/ledger-durability.md` -- deltas (path choice, hooks
  out-of-scope, migration triggering, override semantics, B1/B2 corrections).

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-ledger-durability.sh` | 0 | 32/32 passed (AC1-AC9 + B1 + SEC1/2 + S3) |
| `bash tests/test-hooks.sh` | 0 | 438/438 passed |
| `bash tests/test-meta.sh` | 0 | 578/578 passed |
| `bash tests/test-lane-escalation.sh` | 0 | 22/22 passed |
| `bash tests/test-mega-reconcile.sh` | 0 | 35/35 passed |

## Run detail (live migration on this machine, negative control)

The moved libs migrated the REAL corpus on first post-edit access (env unset):

```
$ ls ~/.local/state/dwarves-kit/logs/runs/
kit-harden-01-eff-val.log  kit-harden-02-naming.log  kit-harden-03-advisor.log
kit-harden-04-rightarm.log kit-harden-05-everystep.log kit-harden-06-laneesc.log
kit-harden-07-deploydone.log kit-harden-08-megamirror.log
plugin-native-operate-contract.log  kit-telem-01-ledger.log
$ ls ~/.local/state/dwarves-kit/logs/.migrated   # sentinel
$ ls ~/.claude/dwarves-kit/logs/runs/ | wc -l     # legacy INTACT (additive)
10
```

Negative control (proves the defect is fixed): the pre-SPEC-097 default put the
corpus INSIDE `~/.claude/dwarves-kit/logs`; the automated AC3 case removes the
legacy dir (simulated plugin reinstall) and confirms `lane-telemetry` still reads
every record from the durable XDG path. Before this change that wipe lost the whole
corpus (the 2026-07-01 incident); after it, zero records are lost.

This run's own gate ledger (`kit-telem-01-ledger.log`) is itself proof of continuity:
its `grill`/`think`/`design` records were written to the legacy path before the edit,
migrated in, and `validate`/`test-plan`/`build` appended at the durable path -- one
unbroken ledger across the migration.

## Review

review-team (SPEC-069, lib/ touched), 3 lenses, all findings addressed in-branch:
- architecture 9/10: 2 NITs (lane-classify lazy-migrate placement -> comment added; awk
  extraction -> declined, matches file idiom). Confirmed no split-brain via grep.
- test-coverage 6/10 -> fixed: BLOCKER (no `|`-reason test) + 3 SHOULD-FIX (real cp
  no-clobber path, per-lib smokes for proof-ledger/precedent/mega-merge, fresh-install
  branch) + 2 NIT (stderr assert, trap cleanup) all added; test grew 18 -> 32 cases.
- security: 2 BLOCKERs with PoCs -> fixed (B1 newline log-injection -> `oneline()`
  sanitizer on record/action/override; B2 symlink-follow migration -> `[ ! -L ]` guard)
  + 2 SHOULD-FIX (sentinel-on-success, source-existence guard). Re-verified green.

## Reproduce

```
bash tests/test-ledger-durability.sh   # hermetic; fake $HOME + $XDG_STATE_HOME per case
```
