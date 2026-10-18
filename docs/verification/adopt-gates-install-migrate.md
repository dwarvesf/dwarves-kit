# Proof of done: adopt gates on, log migration at install

Verdict: PASS

Adopt now seeds `[gate] proof_of_done = true` and `lane_gates = true` into a fresh `.kit.toml`. The legacy-log migration moved out of the ledger and hook-log resolvers into `lib/telemetry/kit-migrate.sh`, which `install.sh` and `lib/adopt.sh` run once.

## Green run

| Suite | Result | What it pins |
|-------|--------|--------------|
| `tests/test-gate-opt-in.sh` | ALL PASS | seed true/true, turn-off comment, operator `false` wins, existing `.kit.toml` byte-identical after adopt and `--refresh`, re-adopt idempotent |
| `tests/test-ledger-durability.sh` | 48/48 | runtime appends copy nothing and drop no sentinel, one stderr note while unmigrated, none after `kit-migrate.sh`, `batch-debt-warn` runs no migration, adopt runs it, `--dry-run` does not, no `cp` in the runtime libs |
| `tests/test-hook-log-dir.sh` | 24/24 | resolver creates and copies nothing, install-time hook-log copy is additive and one-time, pinned and isolated roots, symlink refused |
| `tests/test-adopt.sh` | 63/63 | adopt behavior unchanged elsewhere |
| `tests/test-gate-opt-out.sh` | ALL PASS | gates still switch off through a committed `false` |
| `tests/test-batch-debt-warn.sh` | 8/8 | the hook named in the drift row |
| `tests/test-kit-contract.sh` | 25/25 | executable and registry contract |
| `lib/registry/feature-registry.sh check` | fresh after `--fix` | test refs in `docs/FEATURES.md` |

## Negative control

| Mutation | Suite | Under mutation | After restore |
|----------|-------|----------------|---------------|
| `ledger_root` calls `kit_migrate` again (`lib/ledger/ledger.sh`) | `test-ledger-durability.sh` | exit 1, 46/48 | exit 0, `negctl` Verdict PASS |
| adopt's seed branch for the two gates disabled (`lib/adopt.sh`) | `test-gate-opt-in.sh` | exit 1, 3 FAILS (seed values, operator false, turn-off) | exit 0, `negctl` Verdict PASS |

Both ran through `lib/gate/negctl.sh` after the work was committed, and the tree was clean after each restore.

```
Command: bash tests/test-ledger-durability.sh
Exit: 1 (under mutation, RED expected)
Output: === 46/48 passed, 2 failed ===
Verdict: PASS (restored, green again: 48/48)
```

## Rollback

Revert the commit. The legacy log dir is never deleted or rewritten by the migration, so a revert loses nothing: old runs read the same files. A seeded `.kit.toml` is the repo's own file; set either gate to `false` and commit to turn it off.

## Not proven

- `install.sh` end to end on a fresh `$HOME`: its fixture installs run with a non-default `$CLAUDE_DIR`, which skips the migration by design. The call site is pinned by grep, the entry point by the suites above.
- A real plugin machine upgrade that never runs `install.sh` or `/kit:adopt`: it keeps its old logs and prints the stderr note until the operator runs `kit-migrate.sh`.
