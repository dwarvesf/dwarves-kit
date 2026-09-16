# gate-opt-out -- proof of done

Profile: feature
Proof class: behavioral
Branch: feat/gate-opt-out

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | `proof_of_done = false` in a COMMITTED, clean project `.kit.toml` makes the ship-gate pass a behavioral diff with no proof, and logs `OFF-BY-CONFIG`; uncommitted or dirty, the gate stays on and prints the commit hint; the BLOCKED text names the key | PASS | R1 (`== proof_of_done ==`) |
| AC2 | `lane_gates = false` makes the ship-gate pass a spec with no `Lane:` in an adopted repo; a committed `.kit.toml` does not itself owe a proof | PASS | R1 (`== lane_gates ==`) |
| AC3 | `understanding_gate = false` makes the anti-rationalization Stop hook exit 0 and log `OFF-BY-CONFIG` | PASS | R1 |
| AC4 | `commit_format = false` makes the commit-subject lint exit 0 and log `OFF-BY-CONFIG` | PASS | R1 |
| AC5 | The operator overlay switches a gate off for a repo with no `.kit.toml`; unknown key, missing config, explicit `true` all read as on | PASS | R1 |
| AC6 | Safety gate ignores the block: every key `false`, a force push to main still blocks | PASS | R1 |
| AC7 | No `hooks/*.sh` names the config file (the standing lint stays load-bearing) | PASS | R1 + R2 (`test-install-modules`) |
| AC8 | Every gate blocks as before with no config (negative controls inside R1) and the suite goes RED when the policy reader ignores config | PASS | R1, R4 |
| AC9 | The rest of the kit suite is unaffected; codex trust pins follow the edited hooks | PASS | R2, R3 |
| AC10 | Only exit 1 from the policy reader means off: a syntax-broken reader (exit 2) leaves every gate ON | PASS | R1 (`== broken policy reader ==`) |
| AC11 | `adopt` seeds the `[gate]` block with every key commented, so the operator overlay still reaches a fresh repo | PASS | R1 (`== adopt seeds ==`) |
| AC12 | The proof classifier treats a `.kit.toml`-only diff as inert and a diff that also touches code as behavioral | PASS | R1 (`== proof classifier ==`) |

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
| R1 | 2026-09-16 | `bash tests/test-gate-opt-out.sh` | 0 | PASS (ALL PASS, 27 assertions incl. 8 negative controls) |
| R2 | 2026-09-16 | `bash tests/run-all.sh` | 0 after repin | PASS (148 suites run, 1 skipped for missing codex; the one red, `test-codex-hooks`, was the stale trust pins, green after `hooks/codex-hooks.json` repin: 85 passed, 0 failed) |
| R3 | 2026-09-16 | `bash tests/test-meta.sh` | 0 | PASS (FEATURES.md regenerated for the adopt.md text) |
| R4 | 2026-09-16 | `bash lib/gate/negctl.sh . "bash tests/test-gate-opt-out.sh" "<mutate>"` | 0 | PASS (see below) |
| R5 | 2026-09-16 | `/kit:battery` on PR #653: acceptance-verifier (sonnet), code-reviewer (opus), security-reviewer (opus), advisor (sonnet) | n/a | verifier PASS (7 suites + run-all 148 green, own spelling fixture); three review arms FIX THEN SHIP, all findings fixed in `b8e6b2a` and re-verified by R1 |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-gate-opt-out.sh`
- Exit: 0
- Verdict: PASS
- Output tail: `ALL PASS`

### R4 NEGATIVE CONTROL
Mutation: `gate-policy.sh enabled` returns 0 unconditionally (the `[ "$v" = "false" ] || return 0` line replaced by `return 0`), so every hook believes every gate is on.

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

### R5 battery, what each arm caught
- security lens + code reviewer (independently): any nonzero exit from the policy reader read as off; a corrupt reader disabled every gate. Fixed: only exit 1 is off.
- code reviewer: the adopt seed wrote explicit `true` values, so the operator overlay could not reach a fresh repo. Fixed: seeded commented out.
- code reviewer: an uncommitted `.kit.toml` already switched a gate off, contradicting the README. Fixed: project-level `false` applies only when tracked and clean.
- advisor: the BLOCKED messages never named the opt-out; the Stop hook and commit lint skipped silently. Fixed: pointer lines and `OFF-BY-CONFIG` rows.
- all three: the whole-file inert rule was broader than its comment. Accepted and stated.
- security lens: project beats operator on `[gate]`, the reverse of the `kit_config_get_root` doctrine. Accepted as the feature (per-project opt-out is the point) and stated in the README trust-model paragraph.
- verifier: PASS on every listed command plus a spelling fixture (`"false"` quoted is off, `False` is on).

## 5. Reproduce

```
bash tests/test-gate-opt-out.sh
bash tests/test-codex-hooks.sh
bash tests/test-install-modules.sh
```
