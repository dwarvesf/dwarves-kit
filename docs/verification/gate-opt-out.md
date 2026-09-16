# gate-opt-out -- proof of done

Profile: feature
Proof class: behavioral
Branch: feat/gate-opt-out

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | `proof_of_done = false` in a project `.kit.toml` makes the ship-gate pass a behavioral diff with no proof, and logs `OFF-BY-CONFIG` | PASS | R1 (`== proof_of_done ==`) |
| AC2 | `lane_gates = false` makes the ship-gate pass a spec with no `Lane:` in an adopted repo; a committed `.kit.toml` does not itself owe a proof | PASS | R1 (`== lane_gates ==`) |
| AC3 | `understanding_gate = false` makes the anti-rationalization Stop hook exit 0 | PASS | R1 |
| AC4 | `commit_format = false` makes the commit-subject lint exit 0 | PASS | R1 |
| AC5 | The operator overlay switches a gate off for a repo with no `.kit.toml`; unknown key, missing config, explicit `true` all read as on | PASS | R1 |
| AC6 | Safety gate ignores the block: every key `false`, a force push to main still blocks | PASS | R1 |
| AC7 | No `hooks/*.sh` names the config file (the standing lint stays load-bearing) | PASS | R1 + R2 (`test-install-modules`) |
| AC8 | Every gate blocks as before with no config (negative controls inside R1) and the suite goes RED when the policy reader ignores config | PASS | R1, R4 |
| AC9 | The rest of the kit suite is unaffected; codex trust pins follow the edited hooks | PASS | R2, R3 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `[gate]` block in `kit.toml` (`proof_of_done`, `lane_gates`, `understanding_gate`, `commit_format`); `lib/gate/gate-policy.sh enabled <key> [root]` as the one reader; `hooks/ship-gate.sh`, `hooks/anti-rationalization.sh`, `hooks/commit-format.sh` call it; `lib/adopt.sh` seeds the block; classifier treats `.kit.toml` as inert |
| Where | `lib/gate/gate-policy.sh`, `lib/gate/gate.sh` (`policy` verb), `lib/gate/proof-ledger.sh` (inert rule), the three hooks, `kit.toml`, `lib/adopt.sh`, `lib/config/module-registry.md`, `hooks/codex-hooks.json` (repinned) |
| How it runs | At hook fire: the hook shells out to the policy script with the resolved repo root; project `.kit.toml` > operator `kit.toml` > kit-root `kit.toml` > `true` |
| Reversibility | Revert the branch; no state, no migration. A project that set a key to `false` keeps a harmless unknown key |

## 3. Confirmation (runs)

| Run | When (UTC) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-09-16 | `bash tests/test-gate-opt-out.sh` | 0 | PASS (ALL PASS, 19 assertions incl. 5 negative controls) |
| R2 | 2026-09-16 | `bash tests/run-all.sh` | 0 after repin | PASS (148 suites run, 1 skipped for missing codex; the one red, `test-codex-hooks`, was the stale trust pins, green after `hooks/codex-hooks.json` repin: 85 passed, 0 failed) |
| R3 | 2026-09-16 | `bash tests/test-meta.sh` | 0 | PASS (FEATURES.md regenerated for the adopt.md text) |
| R4 | 2026-09-16 | `bash lib/gate/negctl.sh . "bash tests/test-gate-opt-out.sh" "<mutate>"` | 0 | PASS (see below) |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-gate-opt-out.sh`
- Exit: 0
- Verdict: PASS
- Output tail: `ALL PASS`

### R4 NEGATIVE CONTROL
Mutation: `gate-policy.sh enabled` returns 0 unconditionally (the `[ "$v" != "false" ]` line replaced by `return 0`), so every hook believes every gate is on.

```
## Negative control (negctl)
Command: bash tests/test-gate-opt-out.sh
Exit: 0 (green before mutation)
Mutation: bash $TMPDIR/gate-opt-mutate.sh
Changed: lib/gate/gate-policy.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/gate-policy.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## 5. Reproduce

```
bash tests/test-gate-opt-out.sh
bash tests/test-codex-hooks.sh
bash tests/test-install-modules.sh
```
