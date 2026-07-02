# SPEC-097: Run-ledger durability + per-gate override reasons

Status: VALIDATED
Date: 2026-07-02
Lane: full (touches lib/ enforcement-adjacent storage + audit-trail integrity; data-loss class)
Type: feature
Relates-to: ADR-0024 (gate-ledger + ship-enforcement), SPEC-061 (lane-telemetry START facts), SPEC-070 (rid), SPEC-073 (effectiveness eval consumes this corpus)
Board: dwarves-kit ID-082; kit-telemetry mega-goal SG-01 (ops-toolkit `_meta/megagoals/kit-telemetry`); process-audit R1

## Problem
The kit's run telemetry (the corpus that feeds `/kit:retro` and the SPEC-073
effectiveness eval) lives at `~/.claude/dwarves-kit/logs`, INSIDE the plugin's
own state dir. That dir holds the real `logs/` beside symlinks (`lib`,
`AGENTS.md`, `WORKFLOW.md`) that a plugin reinstall regenerates; the 2026-07-01
reinstall recreated the dir and wiped the entire run corpus. Telemetry that
cannot survive a reinstall cannot feed the retro or the eval -- that is the whole
defect (audit R1 / ID-082).

Second, override hygiene is unenforced: `override <rid> <phase> <reason>` accepts
any reason, so the same pasted reason can be stamped across every gate of a run.
The sole surviving pre-July run did exactly this, defeating the per-gate audit
trail the ledger exists to provide.

## Decision
Two changes, both additive and fail-safe.

1. **Durable storage + additive migration.** New shared resolver
   `lib/kit-log-dir.sh` exposing:
   - `kit_resolve_log_dir` -> `$DWARVES_KIT_LOG_DIR` if set, else
     `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs` (outside the
     `~/.claude/dwarves-kit` reinstall blast zone).
   - `kit_legacy_log_dir` -> `$HOME/.claude/dwarves-kit/logs`.
   - `kit_migrate_log_dir` -> one-time, sentinel-guarded, additive: no-op when
     `DWARVES_KIT_LOG_DIR` is set OR the `.migrated` sentinel exists; else
     `cp -Rn legacy/. new/` (never clobbers, never deletes legacy) and drops the
     sentinel. Cheap and idempotent.
   The corpus-bearing libs (`gate-ledger.sh`, `proof-ledger.sh`,
   `lane-telemetry.sh`, `precedent.sh`, `mega-merge.sh`) source it, call
   `kit_migrate_log_dir` once at load, and set `LOG_DIR="$(kit_resolve_log_dir)"`.
   Hook diagnostic logs are out of scope (ephemeral, not corpus; see impl-notes).

2. **Per-gate override reasons.** `gate-ledger.sh override` rejects (exit 65) a
   `<reason>` already recorded as an override reason for a DIFFERENT phase in the
   same run's ledger. A distinct reason per gate passes; re-applying the same
   reason to the SAME phase (idempotent re-run) is allowed.

## Acceptance criteria
- AC1 [durable default]: with `DWARVES_KIT_LOG_DIR` unset and `XDG_STATE_HOME`
  set to a temp dir, a `gate-ledger.sh record` writes under
  `$XDG_STATE_HOME/dwarves-kit/logs/runs/`, NOT under `~/.claude/dwarves-kit`.
- AC2 [migration]: given a seeded legacy `logs/runs/*.log`, first access migrates
  those files to the new dir; the legacy dir is left intact (additive).
- AC3 [survive-reinstall negative control]: after migration, removing the legacy
  dir (simulated reinstall wipe) leaves the run records readable at the new path;
  `lane-telemetry.sh report`/`misfires` still return them.
- AC4 [migration idempotent + non-clobber]: a second access does not re-copy
  (sentinel present) and never overwrites a file already at the new path.
- AC5 [env override honored]: with `DWARVES_KIT_LOG_DIR` set, both resolver and
  migration honor it and migration does NOT pull in the real machine corpus.
- AC6 [blanket override rejected]: overriding phase A with reason R succeeds;
  overriding phase B with the SAME reason R in the same run is rejected (exit 65,
  message names the duplicate); overriding phase B with a distinct reason passes.
- AC7 [idempotent same-phase override]: re-applying reason R to phase A (already
  R) is allowed (not treated as a blanket duplicate).
- AC8 [corpus migrated]: given a fixture legacy dir seeded with kit-harden-style
  ledgers + `completeness.log`, migration copies them to the new path (hermetic,
  under a fake `$HOME`). The LIVE machine corpus (the real 8 kit-harden ledgers +
  `plugin-native-operate-contract.log`) migrating is evidenced separately in the
  proof-of-done run, not asserted by the automated test (which must not depend on
  or mutate real machine state).
- AC9 [no regression]: `test-hooks.sh`, `test-meta.sh`, `test-lane-escalation.sh`,
  `test-mega-reconcile.sh` stay green.

## Tasks
- T1: `lib/kit-log-dir.sh` -- new resolver + legacy + migration functions.
- T2: `lib/gate-ledger.sh` -- source resolver, migrate-on-load, `LOG_DIR` from
  resolver; add blanket-override rejection to `override()`.
- T3: `lib/proof-ledger.sh`, `lib/lane-telemetry.sh`, `lib/precedent.sh`,
  `lib/mega-merge.sh`, `lib/lane-classify.sh` (its `completeness.log` LANE-CHECK
  writer) -- source resolver, migrate-on-load, path from resolver. lane-classify
  is in the set because it WRITES `completeness.log` that the moved lane-telemetry
  READS; leaving it behind would split-brain downgrades (validate finding B1).
- T4: `tests/test-ledger-durability.sh` -- AC1-AC8 with the reinstall NC.
- T5: `docs/verification/ledger-durability.md` -- table-first proof-of-done.
- T6: `docs/implementation-notes/ledger-durability.md` -- deltas (started).

## Verification
```
bash tests/test-ledger-durability.sh   # AC1-AC8
bash tests/test-hooks.sh               # stays green
bash tests/test-meta.sh                # stays green
bash tests/test-lane-escalation.sh     # stays green (lane-classify misfire read path)
bash tests/test-mega-reconcile.sh      # stays green (mega-merge LOG_DIR)
```

## After state
Run telemetry defaults to `${XDG_STATE_HOME:-$HOME/.local/state}/dwarves-kit/logs`,
outside the reinstall blast zone; the existing kit-harden corpus is migrated in
additively (legacy dir untouched); a reinstall wipe of the legacy dir no longer
loses records. `override` refuses a reason reused across gates in one run.

## Out of Scope
- Hook diagnostic logs (`ship-gate.log`, `slop-cleaner.log`, etc.) -- ephemeral,
  regenerate, not corpus; left at the legacy default (impl-notes rationale).
- A new telemetry schema; cloud/remote storage; deleting the legacy dir.
- What the migrated data MEANS (SG-02 eval) or its dashboard (SG-04).

## Decision Log
- DEC-001: XDG_STATE_HOME, not a `~/.claude` sibling -- canonical persistent-state
  home, fully outside any `~/.claude/dwarves-kit*` reinstall.
- DEC-002: migration is on-access + sentinel-guarded, not a separate install step
  -- covers a real reinstall lazily with one cheap `stat`; `cp -Rn` keeps it
  additive and non-clobbering.
- DEC-003: migration no-ops when `DWARVES_KIT_LOG_DIR` is set -- prevents a test
  pointing at a temp dir from ingesting the real machine corpus.
- DEC-004: override rejection keys on reason-reused-across-phases in the ledger,
  not a batch call form -- catches the observed multi-call defect and any future
  batch form. The reason is reconstructed `$5..NF` (split on ' | ') so a reason
  containing ' | ' compares exactly, and only `$4=="override"` lines count (a
  `skipped <reason>` never triggers a false reject).
- DEC-005 (validate B1): `lib/lane-classify.sh` joins the resolver set even though
  it is not a "ledger" -- it writes `completeness.log`, and the reader
  (`lane-telemetry.sh`) moved, so the writer must move too or downgrades split-brain.
- DEC-006 (validate B2): `kit_migrate_log_dir` always returns 0 (guards + `|| true`
  on every fallible op) AND every call site adds `|| true` -- a migration hiccup
  must never abort a lib load under `set -e`, which would make `gate-ledger check`
  exit nonzero and fail-close the ship-gate.
