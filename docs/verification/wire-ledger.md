# Proof of done: wire-ledger (SPEC-186, harness-ops sub-goal 02)

Behavioral change: the `[ledger]` config section is now live. `lib/telemetry/kit-log-dir.sh`
(`kit_resolve_log_dir`) and `lib/gate/proof-ledger.sh` (`KIT_DELIVERY_RATIO_WARN` /
`KIT_DELIVERY_REAL_FLOOR`) source `lib/config/kit-config.sh` and insert config as the layer
BETWEEN the env var and the hardcoded default: `env > project .kit.toml > kit-root kit.toml >
hardcoded default`. `location = "isolated"` resolves to `$PWD/.kit/logs`; `"shared"` (or unset)
to the XDG default; any other value is treated as an explicit path. An explicit env var
(`KIT_LEDGER_DIR`, `KIT_DELIVERY_RATIO_WARN`, `KIT_DELIVERY_REAL_FLOOR`) still wins over both
config layers, back-compat preserved.

## Green run

Command: `bash /tmp/ho02-proof.sh <repo-root>` (isolated/shared/env-wins run-table script,
transcribed below)

```
== NC1: [ledger] location=isolated resolves under $PWD/.kit/logs ==
  location=isolated -> /var/folders/.../tmp.AydX1pVImY/.kit/logs
  PASS isolated resolves to PWD/.kit/logs
== NC2: [ledger] location=shared resolves to XDG default ==
  location=shared -> ~/.local/state/dwarves-kit/logs
  PASS shared resolves to XDG default
== NC3 (negative control): KIT_LEDGER_DIR env wins over BOTH config values ==
  KIT_LEDGER_DIR=/var/folders/.../tmp.AydX1pVImY/env-wins-dir + location=shared -> /var/folders/.../tmp.AydX1pVImY/env-wins-dir
  PASS env wins over config (location=shared still in file)
== NC4: [ledger] delivery_ratio_warn / delivery_real_floor read through proof-ledger.sh ==
  config ratio=7 floor=5 -> ratio=7 floor=5
  PASS config values read through resolver
== NC5 (negative control): KIT_DELIVERY_RATIO_WARN env wins over config's 7 ==
  KIT_DELIVERY_RATIO_WARN=99 (config says 7) -> ratio=99
  PASS env wins over config for delivery thresholds too
== NC6: unset config + no env -> hardcoded defaults (3 / 40) unchanged ==
  no config, no env -> ratio=3 floor=40
  PASS hardcoded default preserved (3/40)

ALL PASS
```
Exit: 0

Command: `bash lib/config/kit-config.sh selftest`
Exit: 0
Output: `PASS kit-config selftest` (6/6 checks, unchanged, confirms the resolver itself is
untouched by this wiring)

Command: `bash tests/test-install-modules.sh`
Exit: 0
Output (tail): `== 21 passed, 0 failed ==` , includes "STANDING ANTI-DRIFT LINT: no hook reads
kit.toml at runtime" (PASS, leaked: none). Confirms no hot hook reaches `kit-config.sh`
transitively through this change (`kit-log-dir.sh` and `proof-ledger.sh` are sourced only by
non-hook commands: `gate-ledger.sh`, `lane-classify.sh`, `ledger.sh`, `precedent.sh`,
`lane-telemetry.sh`, `mega-merge.sh`, `weekend-batch.sh`, `proof-table-gen.sh`; none are hooks).

Command: `bash tests/test-ledger-substrate.sh && bash tests/test-delivery-ratio.sh && bash tests/test-ledger-durability.sh && bash tests/test-advisor-ledger-emit.sh`
Exit: 0
Output (tail): `9 passed, 0 failed` / `8 passed, 0 failed` / `35/35 passed, 0 failed` /
`27/27 passed, 0 failed` , confirms zero regression on the existing env-var precedence,
delivery-ratio, ledger-substrate, and advisor-ledger-emit suites.

## NEGATIVE CONTROL

Two negative controls, both exercised live (NC3 and NC5 above), not asserted:

- **NC3**: `KIT_LEDGER_DIR` set to an explicit dir while `.kit.toml` still says
  `location = "shared"` -> resolves to the ENV path, not XDG. Config never wins over an
  explicit env var.
- **NC5**: `KIT_DELIVERY_RATIO_WARN=99` set while `.kit.toml` says `delivery_ratio_warn = 7`
  -> resolves to `99`, not `7`. Same precedence contract for the delivery thresholds.

Both negative controls PASS: env beats config in every code path this sub-goal touched.

## Reproduce

```bash
cd dwarves-kit
bash lib/config/kit-config.sh selftest
bash tests/test-install-modules.sh
bash tests/test-ledger-substrate.sh
bash tests/test-delivery-ratio.sh
```

VERDICT: PASS
