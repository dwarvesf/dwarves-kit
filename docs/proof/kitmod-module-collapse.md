# Proof of done, kit-modularity SG-01: module-collapse

**Change:** Retire the `lib/`-root symlink aliases (kit-foldin left ~54 symlinks: 33 root
aliases + 21 intra-subsystem cross-symlinks) in favor of ONE resolution mechanism, a
`LIB_ROOT` anchor each script computes from its own `BASH_SOURCE`. Every cross-subsystem
sibling is now referenced as `"$LIB_ROOT/<subsystem>/<file>"`; every call-site across
`lib/`, `hooks/`, `commands/`, `tests/`, `install.sh`, and docs was updated to the real
subsystem path. No shims, no dispatcher.

**Top-dir decision (Design: bearing call):** kept `lib/`, did NOT rename to `modules/`.
Renaming the top dir touches every `lib/<...>` call-site a second time for zero behavioral
gain, and `lib/` is already the loader-neutral home the design note names as the default
(DECISIONS E3: "keep the top dir name `lib/` unless a neutral `modules/` clearly wins").
`modules/` did not clearly win, so the cheaper, lower-blast-radius choice stands.

## 1. Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| AC1 | No lib-root alias symlinks: `find lib -maxdepth 1 -type l` is EMPTY | PASS |
| AC2 | Zero alias symlinks anywhere under `lib/` (intra-subsystem shims also gone) | PASS |
| AC3 | Full kit suite green at the identical pre-restructure pass count | PASS (56/2 before = 56/2 after) |
| AC4 | `orchestrate` + `mega-merge` run end-to-end; cross-subsystem `$LIB_ROOT/...` calls resolve | PASS |
| AC5 | `.github/workflows/` CI-path audit: no hardcoded moved path | PASS (none) |
| AC6 | COVERAGE-DELTA: every updated call-site resolves (no dangling source) | PASS |
| AC7 | Each touched module carries a co-located usage doc + a named firing point | PASS |

## 2. Implementation

- **Resolution mechanism:** each subsystem script adds `LIB_ROOT="$(cd "$SELF_DIR/.." && pwd)"`;
  same-subsystem siblings stay `"$SELF_DIR/<file>"`, cross-subsystem become
  `"$LIB_ROOT/<sub>/<file>"`. Root orphans set `LIB_ROOT="$SELF_DIR"`.
- **Symlinks removed:** all 54 (`git rm`), 33 root aliases + 21 intra-subsystem cross-symlinks.
- **Repo-root fixes:** 6 sites computed repo root as `$DIR/..` assuming root-alias invocation
  (dirname=`lib/`). Now that callers use the real `lib/<sub>/` path, `$DIR/..` = `lib/`, so
  these were corrected to reach the repo root two levels up (`gate-ledger.sh`/`dispatch-gate.sh`
  `KIT_ROOT`, `proof-table-gen.sh` `SCRIPT_ROOT`, `verif-counts.sh` `KIT`, `board/backlog.sh`
  default `BACKLOG_FILE`, `proof-gate.sh` `TASK_TYPE_REGISTRY`; `proof-table-gen.py` resolves
  `gate-ledger.sh` via `lib/gate/`).
- **Silent cross-subsystem miss caught by over-test:** `lane-telemetry.sh` called
  `"$KIT_LIB/gate-ledger.sh"` (KIT_LIB was its own dir) guarded by `2>/dev/null || ...`, so the
  broken path failed silently and mis-flagged complete runs. Fixed to `"$LIB_ROOT/gate/..."`.
- **Orphans:** `adopt.sh` `explain.sh` `pitch.sh` `precedent.sh` stay as bare root modules per
  the binding design note ("single-purpose orphans stay bare standalone scripts").
- **Test-harness updates:** `test-security-hardening.sh` placed a throwaway gate-ledger copy at
  `lib/` root (relied on root-alias resolution); moved to `lib/gate/`. `test-docs-wiring.sh` and
  `test-understanding-wiring.sh` assert exact call-site strings, which moved.

## 3. Confirmation run-table

| NC | Command | Expected | Actual |
|---|---|---|---|
| no-aliases (maxdepth 1) | `find lib -maxdepth 1 -type l` | empty | empty (exit 0) |
| no-aliases (all depth) | `find lib -type l \| wc -l` | 0 | 0 |
| suite-identical (baseline) | run every `tests/test-*.sh` on master | 56 pass / 2 fail | 56 / 2 |
| suite-identical (after) | run every `tests/test-*.sh` post-restructure | 56 pass / 2 fail | 56 / 2 |
| resolution: mega-merge | `mega-merge.sh gate <fully-gated rid> normal` | exit 0 | exit 0 |
| resolution: orchestrate | `orchestrate.sh` loads + sources siblings | usage banner, no "not found" | usage banner |
| CI-path audit | grep `.github/workflows` for moved paths | none | none |
| coverage-delta | resolve every `$LIB_ROOT/<sub>/<file>` literal vs disk | all exist | 0 missing |

The 2 fails are PRE-EXISTING and environmental, identical before and after: `test-classify-md-inert`
(fixture copies a stripped script to `/tmp` expecting a missing `/tmp/kit-log-dir.sh`) and
`test-ship-gate-profiles` (`ship-gate` hook not installed at `~/.claude/dwarves-kit/hooks/`).
Neither is related to the restructure.

## 4. Run detail

```
$ find lib -maxdepth 1 -type l ; echo exit=$?
exit=0
$ find lib -type l | wc -l
0

# baseline (master):  PASS_FILES=56  FAIL_FILES=2  (classify-md-inert, ship-gate-profiles)
# after restructure:  PASS_FILES=56  FAIL_FILES=2  (same two)

$ export DWARVES_KIT_LOG_DIR=$(mktemp -d)
$ bash lib/gate/gate-ledger.sh start nc-mega normal normal feature feature testrepo >/dev/null
$ for g in $(bash lib/gate/gate-ledger.sh required normal); do bash lib/gate/gate-ledger.sh record nc-mega $g ran nc >/dev/null; done
$ bash lib/goal/mega-merge.sh gate nc-mega normal ; echo exit=$?
exit=0            # cross-subsystem $LIB_ROOT/gate/gate-ledger.sh check resolved + passed
$ bash lib/queue/orchestrate.sh 2>&1 | head -1
usage: orchestrate.sh {next|run|flip|queue} ...   # sourced siblings, no "file not found"

$ grep -rE '<moved tools/ + lib/ paths>' .github/workflows/   # -> (none; CI runs bash tests/*.sh)
```

## 5. Reproduce

```
cd <dwarves-kit>
find lib -maxdepth 1 -type l            # must be empty
find lib -type l | wc -l                # must be 0
for t in tests/test-*.sh; do bash "$t" >/dev/null 2>&1 && echo "PASS $t" || echo "FAIL $t"; done
# expect 56 PASS, 2 FAIL (classify-md-inert, ship-gate-profiles; both pre-existing env)
```

## Deferred (flagged for the conductor)

The physical fold of `tools/<x>/` (ledger-observatory, session-observe/recall/intel,
skill-curator, plugin-check) INTO the subsystem structure was NOT done in this PR. Rationale:
(1) `ledger-observatory` is owned by SG-02 (E -> SG-02 renames it to `stats`); folding it here
double-churns. (2) `skill-curator` / `plugin-check` have no subsystem home specified in the
design or DECISIONS. (3) `session-observe/recall/intel` are self-contained tools whose
repo-root locators + `tool.toml` + out-of-CI test suites would all need touching for a
purely-cosmetic relocation, risking a green PR. The lib-vs-tools retirement's LOAD-BEARING
half, Han's no-alias directive across `lib/`, is complete and green. Recommend the `tools/`
fold ride with SG-02 (which already touches ledger-observatory) with a deliberate home
decision for the two homeless tools.
