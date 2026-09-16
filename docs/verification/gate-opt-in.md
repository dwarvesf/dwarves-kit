# gate-opt-in -- proof of done

Profile: feature
Proof class: behavioral
Branch: feat/gate-opt-in (follows #653, gate-opt-out)

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| AC1 | With the kit root alone, every `[gate]` key resolves off; the ship-gate passes a behavioral diff with no proof and logs `OFF-BY-CONFIG`; the Stop hook and commit lint pass | PASS | R1 (`== kit defaults ==`) |
| AC2 | A project `<key> = true` turns that gate on, committed or not; the BLOCKED text keeps the opt-out pointer | PASS | R1 (`== a project true ==`) |
| AC3 | `adopt` seeds `[gate]` with explicit resolved values (`false` with no overlay, `true` under a gates-on overlay) and a comment explaining each key | PASS | R1 (`== adopt seeds ==`) |
| AC4 | `install.sh` ends with the how-to tip | PASS | R1 |
| AC5 | Every behavior from #653 holds with the gates turned on through an overlay (commit-gated project `false`, only exit 1 is off, skips logged, safety gate immune) | PASS | R2 |
| AC6 | The suites that exercise a gate's block path are hermetic: they read `tests/fixtures/gates-on` and no longer depend on the developer's own overlay | PASS | R3 |
| AC7 | The whole suite is green; FEATURES.md regenerated | PASS | R3, R4 |
| AC8 | The opt-in suite goes RED when a project `true` stops turning a gate on | PASS | R5 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `kit.toml` `[gate]` keys default `false`; `lib/gate/gate-policy.sh` is on only for a literal `true` (project > operator > root), project `true` never commit-gated, project `false` over operator `true` commit-gated; `lib/adopt.sh` seeds explicit resolved values with per-key comments; `install.sh` tip; `tests/fixtures/gates-on/kit.toml` overlay pinned by 12 suites |
| Where | `kit.toml`, `lib/gate/gate-policy.sh`, `lib/adopt.sh`, `install.sh`, `lib/gate/README.md`, `lib/config/module-registry.md`, `commands/adopt.md`, ADR-0025, `tests/` |
| How it runs | Unchanged path: hooks shell out to the reader with the repo root; the reader resolves the layered config at fire time |
| Reversibility | Revert the branch. An operator who wants the old always-on behavior sets the four keys `true` in `~/.config/dwarves-kit/kit.toml` (this machine's overlay did, dotfiles `feat/kit-gates-on`) |

## 3. Confirmation (runs)

| Run | When (UTC) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-09-16 | `bash tests/test-gate-opt-in.sh` | 0 | PASS (ALL PASS, 16 assertions) |
| R2 | 2026-09-16 | `bash tests/test-gate-opt-out.sh` | 0 | PASS (ALL PASS, 27 assertions, overlay = `tests/fixtures/gates-on`) |
| R3 | 2026-09-16 | the 12 pinned suites + `test-adopt`, `test-config-registry`, `test-install-modules`, `test-config-seams` | 0 each | PASS |
| R4 | 2026-09-16 | `bash tests/test-meta.sh` | 0 | PASS |
| R5 | 2026-09-16 | `bash lib/gate/negctl.sh . "bash tests/test-gate-opt-in.sh" "<mutate>"` | 0 | PASS (see below) |

## 4. Run detail

### R1 GREEN
- Command: `bash tests/test-gate-opt-in.sh`
- Exit: 0
- Verdict: PASS

### R5 NEGATIVE CONTROL
Mutation: in `gate-policy.sh`, a project `true` returns 1 instead of 0, so no repo can turn a gate on.

```
## Negative control (negctl)
Command: bash tests/test-gate-opt-in.sh
Exit: 0 (green before mutation)
Changed: lib/gate/gate-policy.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/gate/gate-policy.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## 5. Reproduce

```
bash tests/test-gate-opt-in.sh
bash tests/test-gate-opt-out.sh
bash tests/test-ship-gate-profiles.sh
```
