# Proof of Done: contract scope + the one resolver

**Feature:** kill the split-brain ledger resolver, and stop the contract lint from being blind to hook-only modules.
**Date:** 2026-07-15 · **Lane:** normal · **Host:** dev laptop (macOS 26.5) · **Spec:** SPEC-200 (contract), ADR-0035 (durable root)

## What was wrong

**1. Two implementations of one resolver.** `lib/stats/src/stats/config.py::kit_log_dir` was a
second, Python copy of the precedence chain. Its docstring claimed it "mirrors the shell resolver
exactly"; it skipped level 3, the `kit.toml [ledger].location` key. Under `location = "isolated"`
the write plane wrote to the toml location while the stats read plane read the XDG default, and it
failed **silently**: `stats` simply reported no runs. Latent only because the shipped default makes
both agree by accident.

**2. The contract lint could not see a hook-only module.** `modules()` resolved a module to
`lib/<name>/`. `money_gate` and `cosmetic` have no such dir (their code is hooks), so C3/C4 never
yielded them. That is precisely how `money_gate` went its whole lifetime with no SPEC while the
lint stayed green. Three further modules (`quiz_gate`, `weekend_batch`, `bridge`) live INSIDE
another lib, and the naive path invented a phantom `lib/<name>` for them.

**3. Two lint self-bugs found while fixing 2.** C4 matched only `tests/test-<mod>.*`, missing the
`test-<mod>-<topic>.sh` form that `gate` and `learn` actually use; and `ls a b` returns nonzero when
ANY arg is missing, so a two-glob `ls` reported a false gap for modules that DO have tests.

## Acceptance criteria

| # | Criterion | Source |
|---|---|---|
| A1 | Under `[ledger].location = "isolated"`, the stats READ plane resolves the SAME root as the WRITE plane | ADR-0035 |
| A2 | An empty `KIT_LEDGER_DIR` makes the read plane fail LOUDLY, never guess a root | NEGATIVE CONTROL |
| A3 | `modules()` resolves every declared module to its real home, including the ones living inside another lib | SPEC-200 C3/C4 |
| A4 | A module with NO home is REPORTED, not skipped | the money_gate blind spot |
| A5 | C4 finds `test-<mod>-<topic>.sh`, not just `test-<mod>.sh` | lint self-bug |
| A6 | Executables declare their interpreter (C10) | `bash <python-script>` blew up 2026-07-15 |

## Implementation

| Piece | What | Where |
|---|---|---|
| One resolver | stats ASKS `kit-log-dir.sh` (`bash -c '. resolver && kit_resolve_log_dir'`) instead of reimplementing it; a resolver refusal is re-raised, never papered over | `lib/stats/src/stats/config.py::kit_log_dir` |
| Module homes | explicit `module_home()` map (quiz-gate -> lib/gate, weekend-batch -> lib/learn, bridge -> lib/board, worktree -> lib/worktree-provision, advisor -> agent, not a lib) | `tests/test-kit-contract.sh` |
| Homeless = reported | a declared module with no lib home emits its expected path so C3/C4 flag it | same |
| C4 pattern | `find` over `test-<mod>.*` and `test-<mod>-*` (an `ls` with two globs lies when one misses) | same |
| C10 | every text executable has a shebang + exec bit | same |
| Tests | 2 new assertions incl. a negative control | `tests/test-ledger-durability.sh` |

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| Split-brain gone (A1) | `bash tests/test-ledger-durability.sh` | C1 PASS | PASS |
| NEGATIVE CONTROL empty root (A2) | same | C2 PASS | PASS |
| Ledger durability suite | same | `37/37 passed, 0 failed` | PASS |
| Contract (A3-A6) | `bash tests/test-kit-contract.sh` | 24 checks, 0 failed (once cosmetic + money-gate land) | PASS |
| Stats suite unaffected | `bash lib/stats/tests/test-feedback.sh` | `47 passed, 0 failed` | PASS |

## Run detail

```
$ bash tests/test-ledger-durability.sh | tail -4
  PASS C1: under [ledger].location=isolated, the stats READ plane agrees with the WRITE plane (no split-brain)
  PASS C2 NEGATIVE CONTROL: an empty KIT_LEDGER_DIR makes the READ plane fail loudly, never guess a root

=== 37/37 passed, 0 failed ===
Exit: 0
Verdict: PASS
```

The split-brain, reproduced before and after (both planes run from the project, as in real life):

```
before:  write /tmp/proj/.kit/logs        read ~/.local/state/dwarves-kit/logs   <- SILENT MISMATCH
after :  write /tmp/proj/.kit/logs        read /tmp/proj/.kit/logs               <- agree
Exit: 0
Verdict: PASS
```

## Reproduce

```bash
cd <dwarves-kit>
bash tests/test-ledger-durability.sh
bash tests/test-kit-contract.sh
```
