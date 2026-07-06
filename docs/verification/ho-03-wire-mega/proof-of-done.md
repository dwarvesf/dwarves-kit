# Proof of done: ho-03-wire-mega (harness-ops SG-03)

Sub-goal: `_meta/megagoals/harness-ops/goals/03-wire-mega.md` ("wire-mega").
Canonical companion run-table: `docs/verification/generated/harness-ops-03-mega.md` (generated,
`bash lib/gate/proof-table-gen.sh harness-ops-03-mega`).

## 1. Acceptance criteria (Done =)

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `[mega]` keys (`wave_cap`, `tier4_close`, `multiplexer`) resolve through `lib/config/kit-config.sh` in `orchestrate.sh`, env still wins | PASS | run-table §2 below |
| 2 | `default_model` fallback: goal-file `Model:` wins outright; absent -> `[mega].default_model` via the config layer | PASS | run-table §2 below |
| 3 | `mega_merge_posture` resolves through the config layer in `lib/goal/mega-merge.sh`, flag/env still win | PASS | run-table §2 below |
| 4 | `merge_autonomy` resolution documented to consult the config layer (no runtime env mirror; a scaffold-time decision) | PASS | `commands/mega.md` Step 3 diff |
| 5 | `over_test` fallback documented for UI sub-goals' `Done-mode:` (`commands/ui-design.md`) | PASS | `commands/ui-design.md` diff |
| 6 | No regression: all pre-existing orchestrate/wavefront/mega-merge/hardening tests still green | PASS | run-table §2 below |

## 2. Confirmation (captured run-table)

Fixture: `/tmp/ho03proof/proj` (ROADMAP with SG-01 `Model: opus`, SG-02 no `Model:` line),
project `.kit.toml`:

```toml
[mega]
wave_cap = 3
default_model = "haiku"
mega_merge_posture = "per-pr-review"
```

### 2a. `[mega].wave_cap` resolution (env > project > kit-root > hardcoded)

```
$ KIT_PROJECT_ROOT=/tmp/ho03proof KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot \
    bash -x lib/queue/orchestrate.sh run /tmp/ho03proof/proj --dry-run 2>&1 | grep -m1 'WAVE_CAP='
+ WAVE_CAP=3                     # project .kit.toml's [mega] wave_cap=3, no env set

$ KIT_PROJECT_ROOT=/tmp/ho03proof KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot WAVE_CAP=5 \
    bash -x lib/queue/orchestrate.sh run /tmp/ho03proof/proj --dry-run 2>&1 | grep -m1 'WAVE_CAP='
+ WAVE_CAP=5                     # env WAVE_CAP=5 overrides the project's 3
```

### 2b. `default_model` precedence (goal-file `Model:` > project > kit-root)

```
$ KIT_PROJECT_ROOT=/tmp/ho03proof KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot \
    bash lib/queue/orchestrate.sh run /tmp/ho03proof/proj --dry-run
[plan] mega-goal: /tmp/ho03proof/proj
  -> SG-01 (auto)  [model: opus, effort: inherit]   # goal-file "Model: opus" WINS over config
  -> SG-02 (auto)  [model: haiku, effort: inherit]  # no Model: line -> picks up [mega].default_model="haiku"
  ...

$ KIT_PROJECT_ROOT=/tmp/ho03proof/nowhere KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot \
    bash lib/queue/orchestrate.sh run /tmp/ho03proof/proj --dry-run
[plan] mega-goal: /tmp/ho03proof/proj
  -> SG-01 (auto)  [model: opus, effort: inherit]     # still opus, no config change
  -> SG-02 (auto)  [model: inherit, effort: inherit]  # no config file at all -> pre-existing "inherit" behavior UNCHANGED
  ...
```

### 2c. `mega_merge_posture` resolution (flag > env > project > kit-root > hardcoded)

```
$ KIT_PROJECT_ROOT=/tmp/ho03proof KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot \
    bash -c 'source lib/goal/mega-merge.sh gate 2>/dev/null; _resolve_posture'
per-pr-review                    # project .kit.toml's [mega] mega_merge_posture, no env/flag set

$ KIT_PROJECT_ROOT=/tmp/ho03proof KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot MEGA_MERGE_POSTURE=auto-to-final \
    bash -c 'source lib/goal/mega-merge.sh gate 2>/dev/null; _resolve_posture'
auto-to-final                    # env wins over the project's per-pr-review

$ KIT_PROJECT_ROOT=/tmp/ho03proof/nowhere KIT_CONFIG_ROOT=/tmp/ho03proof/kitroot \
    bash -c 'source lib/goal/mega-merge.sh gate 2>/dev/null; _resolve_posture'
auto-to-final                    # no config, no env -> hardcoded default, unchanged
```

### 2d. Regression suite (all pre-existing, unmodified test files)

| Suite | Result |
|---|---|
| `bash lib/config/kit-config.sh selftest` | PASS (6/6) |
| `tests/test-orchestrate.sh` | ALL PASS |
| `tests/test-orchestrate-hardening.sh` | 12/12 passed |
| `tests/test-orchestrate-wavefront.sh` | 35/35 passed |
| `tests/test-mega-merge.sh` | 30/30 passed |

## 3. Implementation

- `lib/queue/orchestrate.sh`: sources `lib/config/kit-config.sh`; `WAVE_CAP`, `MULTIPLEXER`,
  `TIER4_CLOSE` now resolve `env > kit_config_get mega.<key> > hardcoded default` (a new
  `_kit_bool01` helper normalizes TOML `true`/`false` to `1`/`0`); `_route()`'s goal-file
  `Model:` parse is untouched (still wins outright) and only falls back to
  `kit_config_get mega.default_model` when the field is absent -- with no config file, the
  lookup returns empty and the pre-existing "inherit the session's tier" behavior is
  byte-for-byte unchanged.
- `lib/goal/mega-merge.sh`: sources the same config lib; `_resolve_posture()` gains a middle
  layer, `--posture` flag > `MEGA_MERGE_POSTURE` env > `kit_config_get mega.mega_merge_posture`
  > `auto-to-final` default.
- `commands/mega.md` Step 3: documents the config-layer fallback for `merge_autonomy` (a
  scaffold-time decision with no runtime env mirror) and for `MEGA_MERGE_POSTURE`.
- `commands/ui-design.md` Done-mode section: documents `[mega].over_test` as the fallback
  when a UI sub-goal's `Done-mode:` field is absent (`true` promotes the default from
  `proof` to `over-test`).

## 4. Reproduce

```
bash lib/config/kit-config.sh selftest
bash tests/test-orchestrate.sh
bash tests/test-orchestrate-hardening.sh
bash tests/test-orchestrate-wavefront.sh
bash tests/test-mega-merge.sh
bash lib/gate/proof-table-gen.sh harness-ops-03-mega   # regenerates docs/verification/generated/harness-ops-03-mega.md
```

The `/tmp/ho03proof` fixture used for §2 is not committed (scratch); recreate per the
commands embedded in §2 above, or from `tests/test-orchestrate.sh`'s `mk_megagoal`/`mk_routed`
helpers as a template.
